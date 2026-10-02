#!/usr/bin/env python3
"""Read-only parameter validation by default; bounded mixed run requires explicit --run.
This is an evidence client for the SAME SQLQueryStress batches, not a database dispatcher.
"""
import argparse
import concurrent.futures
import json
import re
import time
from collections import Counter
from datetime import datetime
from common import CONTRACTS, ROOT, connect, emit, query, scalar
from package_workload import DEFAULT, SHAPES, build, decode

GROUPS=json.loads((ROOT/'workload/manifest.json').read_text())


def static():
    assert sum(g['share'] for g in GROUPS)==100
    for filename, sql in build().items():
        assert (ROOT/'workload'/filename).read_text()==sql, 'Run tests/integration/package_workload.py'
    for group in [DEFAULT]+GROUPS:
        sql=(ROOT/'workload'/group['name']/'calls.sql').read_text()
        inputs=set(re.findall(r'@Input\w+',sql))
        assert inputs=={'@'+name for name in group['mappings']},group['name']
        assert not re.search(r'^\s*GO\s*$',sql,re.M|re.I)
        assert not re.search(r'ORDER BY\s+NEWID',sql,re.I)
        for name,arguments in re.findall(r'EXEC dbo\.(Stackish_\w+) ([^;]+);',sql):
            supplied=set(re.findall(r'(@\w+)\s*=',arguments))
            signature=CONTRACTS[name]['parameters']
            allowed={p['name'] for p in signature}
            required={p['name'] for p in signature if p['default'] is None}
            assert required<=supplied<=allowed,(group['name'],name,supplied)
    sql=(ROOT/'workload/calls.sql').read_text()
    routes=[(int(limit),name) for limit,name in re.findall(r'IF @Operation<(\d+) -- \d+%: (\S+)',sql)]
    counts=Counter(next(name for limit,name in routes if roll<limit) for roll in range(100))
    assert counts=={g['name']:g['share'] for g in GROUPS if g['share']}, counts
    emit('workload offline mapping and routing checks',groups=len(GROUPS),default_mappings=DEFAULT['mappings'])


def validate_targets(c,values):
    """Decode every generated target through SQL's actual typed projection, without EXEC."""
    payloads=[row[0] for row in values]
    decoded=[json.loads(payload) for payload in payloads]
    groups=[g for g in GROUPS if g['share'] and g['mappings']]
    expected_keys={g['name'] for g in groups}
    assert all(set(row)==expected_keys for row in decoded)
    sets=[]
    for group in groups:
        projection=decode(group).replace('@InputTargets','j.value')
        cols=','.join('v.['+col+']' for col,_ in SHAPES[group['name'][:2]])
        sets.append(f'SELECT {cols} FROM OPENJSON(@Payloads) j CROSS APPLY {projection} v ORDER BY CONVERT(int,j.[key]);')
    actual=query(c,'DECLARE @Payloads nvarchar(max)=%s;\n'+'\n'.join(sets),(json.dumps(decoded),))
    assert len(actual)==len(groups)
    for group,(shape,rows) in zip(groups,actual):
        specification=SHAPES[group['name'][:2]]
        assert shape==[list(col) for col in specification],(group['name'],shape)
        expected=[]
        for payload in decoded:
            target=payload[group['name']]
            assert set(target)=={col for col,_ in specification}
            assert all(value is not None for value in target.values())
            expected.append(tuple(datetime.fromisoformat(target[col]) if typ=='datetime' else target[col]
                                  for col,typ in specification))
        assert rows==expected,(group['name'],'JSON changed a value or tuple')
    hot={(r['11-hot-counters']['QuestionId'],r['11-hot-counters']['UserId']) for r in decoded}
    assert 1<=len(hot)<=8
    emit('single-window target round trip',rows=len(values),branches=len(groups),hot_targets=len(hot),workload_executed=False)


def compile_batch(c,group,shape):
    types=dict(shape)
    declarations='\n'.join('DECLARE @'+name+' '+types[col]+';' for name,col in group['mappings'].items())
    sql=(ROOT/'workload'/group['name']/'calls.sql').read_text()
    try:
        query(c,'SET NOEXEC ON;\n'+declarations+'\n'+sql+'\nSET NOEXEC OFF;')
    finally:
        query(c,'SET NOEXEC OFF;')
    emit('workload batch compiled',group=group['name'],executed=False)


def parameters(c,group):
    start=time.monotonic()
    sql=(ROOT/'workload'/group['name']/'parameters.sql').read_text()
    try:
        schema_sets=query(c,'SET FMTONLY ON;\n'+sql+'\nSET FMTONLY OFF;')
    finally:
        query(c,'SET FMTONLY OFF;')
    sets=query(c,sql)
    assert [s[0] for s in schema_sets]==[s[0] for s in sets],(group['name'],'SQLQueryStress Get Columns shape differs')
    assert len(sets)==1,(group['name'],'exactly one parameter result required')
    shape,values=sets[0]
    compile_batch(c,group,shape)
    columns=[c[0] for c in shape]
    assert values,(group['name'],'No eligible rows in bounded window; reload parameter query, do not run empty pool')
    assert set(group['mappings'].values())<=set(columns),(group['name'],columns)
    for row in values:
        assert all(row[columns.index(col)] is not None for col in group['mappings'].values()),(group['name'],'NULL parameter')
    if group==DEFAULT:
        assert shape==[['TargetsJson','nvarchar(max)']],shape
        validate_targets(c,values)
    emit('parameter pool',group=group['name'],rows=len(values),milliseconds=round((time.monotonic()-start)*1000,2))
    return [dict(zip(columns,row)) for row in values]


def run_one(group,pool,index):
    # One connection per worker below would match SQLQueryStress pooling more closely;
    # connection time is reported separately from batch execution time here.
    started=time.monotonic()
    with connect() as c:
        connected=time.monotonic()
        sql=(ROOT/'workload'/group['name']/'calls.sql').read_text().replace('%','%%')
        args=[]
        row=pool[index % len(pool)]
        def replace(match):
            args.append(row[group['mappings'][match[0][1:]]]);return '%s'
        sql=re.sub(r'@Input\w+',replace,sql)
        # Empty args would bypass %-formatting in the driver.
        if not args: sql=sql.replace('%%','%')
        try:
            sets=query(c,sql,args)
            outcomes=[r[0] for shape,data in sets if shape and shape[0][0]=='Outcome' for r in data]
            assert scalar(c,'SELECT @@TRANCOUNT')==0,'Open transaction after workload call'
            result={'group':group['name'],'outcomes':outcomes,'rows':[len(s[1]) for s in sets],
                    'milliseconds':round((time.monotonic()-connected)*1000,2),
                    'connection_ms':round((connected-started)*1000,2)}
        except Exception as exc:
            result={'group':group['name'],'error':str(exc),'milliseconds':round((time.monotonic()-connected)*1000,2)}
        emit('workload call',**result)
        return result


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--static',action='store_true')
    parser.add_argument('--compile-only',action='store_true',help='SchemaOnly selectors and NOEXEC calls; no query data or workload execution')
    parser.add_argument('--run',action='store_true',help='Execute mixed workload, including committed mutations')
    parser.add_argument('--allow-mutations',action='store_true')
    parser.add_argument('--calls',type=int,default=100,help='Total bounded calls; default uses the single-window random mix')
    parser.add_argument('--threads',type=int,default=4)
    parser.add_argument('--groups',nargs='*',help='Optional exact group names; selected weights are renormalized')
    args=parser.parse_args();static()
    if args.static:return
    if args.run and not args.allow_mutations:parser.error('--run requires --allow-mutations on a disposable database')
    if not 1<=args.calls<=10000 or not 1<=args.threads<=32:parser.error('calls 1..10000; threads 1..32')
    groups=[g for g in GROUPS if g['name'] in args.groups] if args.groups else [DEFAULT]
    if not groups or (args.groups and set(args.groups)!={g['name'] for g in groups}):parser.error('Unknown/empty group selection')
    pools={}
    with connect() as c:
        for group in groups:
            if args.compile_only:
                sql=(ROOT/'workload'/group['name']/'parameters.sql').read_text()
                try: sets=query(c,'SET FMTONLY ON;\n'+sql+'\nSET FMTONLY OFF;')
                finally: query(c,'SET FMTONLY OFF;')
                assert len(sets)==1
                compile_batch(c,group,sets[0][0])
            else:pools[group['name']]=parameters(c,group)
    if args.compile_only:return
    if not args.run:
        emit('parameter validation complete',workload_executed=False);return
    # Largest remainder apportionment gives exact bounded total and approximate invocation mix.
    weights=[g['share'] or 1 for g in groups];total=sum(weights)
    counts=[args.calls*w//total for w in weights]
    order=sorted(range(len(groups)),key=lambda i:args.calls*weights[i]%total,reverse=True)
    for i in order[:args.calls-sum(counts)]:counts[i]+=1
    jobs=[]
    for group,count in zip(groups,counts):
        if group['name']=='13-comment-maintenance' and count>len(pools[group['name']]):
            parser.error('Comment-maintenance calls must not exceed its parameter pool')
        jobs.extend((group,pools[group['name']],i) for i in range(count))
    # Interleave groups deterministically so the short run is mixed from the start.
    jobs.sort(key=lambda j:(j[2],j[0]['name']))
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.threads) as workers:
        results=list(workers.map(lambda job:run_one(*job),jobs))
    outcomes=Counter(o for r in results for o in r.get('outcomes',[]))
    errors=sum('error' in r for r in results)
    emit('mixed run summary',calls=len(results),errors=errors,outcomes=dict(outcomes))
    if errors:raise SystemExit(1)

if __name__=='__main__':main()
