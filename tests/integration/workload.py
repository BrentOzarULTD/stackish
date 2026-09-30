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
from common import ROOT, connect, emit, query, scalar

GROUPS=json.loads((ROOT/'workload/manifest.json').read_text())


def static():
    assert sum(g['share'] for g in GROUPS)==100
    for group in GROUPS:
        sql=(ROOT/'workload'/group['name']/'calls.sql').read_text()
        inputs=set(re.findall(r'@Input\w+',sql))
        assert inputs=={'@'+name for name in group['mappings']},group['name']
        assert not re.search(r'^\s*GO\s*$',sql,re.M|re.I)
        assert not re.search(r'ORDER BY\s+NEWID',sql,re.I)
    emit('workload offline mapping checks',groups=len(GROUPS))


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
    parser.add_argument('--calls',type=int,default=100,help='Total bounded calls, apportioned by documented shares')
    parser.add_argument('--threads',type=int,default=4)
    parser.add_argument('--groups',nargs='*',help='Optional exact group names; selected weights are renormalized')
    args=parser.parse_args();static()
    if args.static:return
    if args.run and not args.allow_mutations:parser.error('--run requires --allow-mutations on a disposable database')
    if not 1<=args.calls<=10000 or not 1<=args.threads<=32:parser.error('calls 1..10000; threads 1..32')
    groups=[g for g in GROUPS if (g['name'] in args.groups if args.groups else g['share']>0)]
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
