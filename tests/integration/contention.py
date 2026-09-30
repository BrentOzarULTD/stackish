#!/usr/bin/env python3
"""Bounded correctness races, not a throughput test. Commits then deletes owned fixtures.
No modified procedure builds, schema changes, WAITFOR, or imported-row cleanup.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from collections import Counter
import threading
import time
import uuid
from common import call, connect, emit, query, rows, scalar


def race(control, jobs, gate_table, gate_id):
    """Queue real sessions behind an owned fixture row; release after observing overlap."""
    barrier=threading.Barrier(len(jobs)+1)
    session_ids=[]
    lock=threading.Lock()
    def worker(job):
        with connect() as c:
            spid=scalar(c,'SELECT @@SPID')
            with lock:session_ids.append(spid)
            barrier.wait(timeout=30)
            name,args=job
            result=call(c,name,**args)[0][0]
            assert scalar(c,'SELECT @@TRANCOUNT')==0
            return result
    assert gate_table in ('Users','Posts')
    with connect() as gate,ThreadPoolExecutor(max_workers=len(jobs)) as workers:
        query(gate,'BEGIN TRANSACTION;')
        rows(gate,f'SELECT Id FROM dbo.{gate_table} WITH(XLOCK,HOLDLOCK) WHERE Id=%s',(gate_id,))
        futures=[workers.submit(worker,job) for job in jobs]
        try:
            barrier.wait(timeout=30)
            deadline=time.monotonic()+20
            overlap=0
            while time.monotonic()<deadline:
                ids=','.join(str(int(i)) for i in session_ids)
                overlap=scalar(control,f"SELECT COUNT(*) FROM sys.dm_exec_requests WHERE session_id IN ({ids}) AND wait_type LIKE 'LCK_M%'")
                if overlap==len(jobs):break
                # Client coordination only; no delay is inserted into shipped SQL/workload.
                time.sleep(.05)
            emit('race gate',queued=overlap,workers=len(jobs))
        finally:
            query(gate,'ROLLBACK;')
        # Drain ALL workers before asserting or cleaning up, including after one failure.
        results=[];errors=[]
        for future in futures:
            try:results.append(future.result())
            except Exception as exc:errors.append(str(exc))
        assert not errors,errors
        assert overlap==len(jobs),'Could not prove overlapping calls; race is inconclusive'
    emit('race outcomes',outcomes=dict(Counter(r[0] for r in results)))
    return results


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--allow-mutations',action='store_true')
    parser.add_argument('--workers',type=int,default=8)
    args=parser.parse_args()
    if not args.allow_mutations:parser.error('--allow-mutations is required for committed fixtures')
    if not 2<=args.workers<=16:parser.error('workers must be 2..16')
    n=args.workers
    marker='stkint-'+uuid.uuid4().hex[:20]
    users=[];posts=[];tag_ids=[]
    with connect() as c:
        emit('contention target',database=scalar(c,'SELECT DB_NAME()'),marker=marker,workers=n)
        base={table:scalar(c,f'SELECT COALESCE(MAX(Id),0) FROM dbo.{table}') for table in ('Votes','Comments','PostHistory','PostLinks')}
        def applied(name,**kw):return call(c,name,'Applied',**kw)[0][0][1]
        def same(name,kw,table,id_,applied_count=1,other='NoChange'):
            result=race(c,[(name,kw)]*n,table,id_)
            assert Counter(r[0] for r in result)==Counter({'Applied':applied_count,other:n-applied_count})
            return result
        try:
            query(c,'BEGIN TRANSACTION;')
            for i in range(n+1):users.append(applied('CreateUser',DisplayName=f'{marker}-{i}'))
            for suffix in ('a','b'):
                tag_ids.append(scalar(c,'INSERT dbo.Tags(TagName,[Count],ExcerptPostId,WikiPostId) OUTPUT inserted.Id VALUES(%s,0,0,0)',(marker+'-'+suffix,)))
            t1,t2=f'<{marker}-a>',f'<{marker}-b>'
            for i in range(2):posts.append(applied('CreateQuestion',UserId=users[0],Title=marker+str(i),Body=marker,Tags=t1))
            query(c,'COMMIT;')
            q,q2=posts;owner,voter=users[:2]
            emit('owned fixtures',users=users,posts=posts,tags=tag_ids,related_id_baselines=base)
            user_list=','.join(map(str,users));post_list=','.join(map(str,posts))
            assert scalar(c,f'SELECT COUNT_BIG(*) FROM dbo.Votes WHERE PostId IN ({post_list}) AND UserId IN ({user_list}) AND VoteTypeId IN(2,3)')==0,'Fixture collides with attributed orphan votes; rerun'
            assert scalar(c,'SELECT COUNT_BIG(*) FROM dbo.PostLinks WHERE PostId=%s AND RelatedPostId=%s',(q,q2))==0,'Fixture collides with orphan links; rerun'
            for proc,param,column,table,id_ in [('RecordQuestionView','QuestionId','ViewCount','Posts',q),('RecordProfileView','UserId','Views','Users',owner)]:
                before=scalar(c,f'SELECT {column} FROM dbo.{table} WHERE Id=%s',(id_,))
                result=race(c,[(proc,{param:id_})]*n,table,id_)
                assert all(r[0]=='Applied' for r in result)
                assert scalar(c,f'SELECT {column} FROM dbo.{table} WHERE Id=%s',(id_,))==before+n
            before=scalar(c,'SELECT AnswerCount FROM dbo.Posts WHERE Id=%s',(q,))
            result=race(c,[('CreateAnswer',dict(QuestionId=q,UserId=voter,Body=marker))]*n,'Posts',q)
            posts.extend(r[1] for r in result if r[0]=='Applied')
            assert all(r[0]=='Applied' for r in result)
            assert scalar(c,'SELECT AnswerCount FROM dbo.Posts WHERE Id=%s',(q,))==before+n
            before=scalar(c,'SELECT CommentCount FROM dbo.Posts WHERE Id=%s',(q,))
            result=race(c,[('AddComment',dict(PostId=q,UserId=voter,Text=marker))]*n,'Posts',q)
            assert all(r[0]=='Applied' for r in result)
            assert scalar(c,'SELECT CommentCount FROM dbo.Posts WHERE Id=%s',(q,))==before+n
            comment=result[0][1]
            same('DeleteComment',dict(CommentId=comment,UserId=voter),'Users',voter,other='NotFound')
            assert scalar(c,'SELECT CommentCount FROM dbo.Posts WHERE Id=%s',(q,))==before+n-1
            score=scalar(c,'SELECT Score FROM dbo.Posts WHERE Id=%s',(q,))
            rep=scalar(c,'SELECT Reputation FROM dbo.Users WHERE Id=%s',(owner,))
            up=scalar(c,'SELECT UpVotes FROM dbo.Users WHERE Id=%s',(voter,))
            same('UpvoteQuestion',dict(QuestionId=q,UserId=voter),'Users',voter)
            assert scalar(c,'SELECT Score FROM dbo.Posts WHERE Id=%s',(q,))==score+1
            assert scalar(c,'SELECT Reputation FROM dbo.Users WHERE Id=%s',(owner,))==rep+10
            assert scalar(c,'SELECT UpVotes FROM dbo.Users WHERE Id=%s',(voter,))==up+1
            same('RemovePostVote',dict(PostId=q,UserId=voter),'Users',voter)
            assert scalar(c,'SELECT Score FROM dbo.Posts WHERE Id=%s',(q,))==score
            assert scalar(c,'SELECT Reputation FROM dbo.Users WHERE Id=%s',(owner,))==rep
            result=race(c,[('UpvoteQuestion',dict(QuestionId=q,UserId=u)) for u in users[1:]],'Posts',q)
            assert all(r[0]=='Applied' for r in result)
            assert scalar(c,'SELECT Score FROM dbo.Posts WHERE Id=%s',(q,))==score+n
            assert scalar(c,'SELECT Reputation FROM dbo.Users WHERE Id=%s',(owner,))==rep+10*n
            assert scalar(c,f'SELECT COUNT_BIG(*) FROM dbo.Votes WHERE PostId={q} AND Id>{base["Votes"]} AND UserId IN ({user_list})')==n
            counts=rows(c,'SELECT Id,[Count] FROM dbo.Tags WHERE Id IN (%s,%s) ORDER BY Id',tuple(tag_ids))
            same('RetagQuestion',dict(QuestionId=q,EditorUserId=voter,Tags=t2),'Posts',q)
            assert rows(c,'SELECT Id,[Count] FROM dbo.Tags WHERE Id IN (%s,%s) ORDER BY Id',tuple(tag_ids))==[(tag_ids[0],counts[0][1]-1),(tag_ids[1],counts[1][1]+1)]
            result=same('AddQuestionLink',dict(QuestionId=q,RelatedQuestionId=q2,UserId=voter),'Users',voter)
            assert len({r[1] for r in result})==1
            link=result[0][1]
            assert scalar(c,'SELECT COUNT_BIG(*) FROM dbo.PostLinks WHERE PostId=%s AND RelatedPostId=%s AND LinkTypeId=1',(q,q2))==1
            same('RemoveQuestionLink',dict(LinkId=link,UserId=voter),'Users',voter,other='NotFound')
            same('CloseQuestion',dict(QuestionId=q,UserId=voter,Reason=marker),'Users',voter)
            same('ReopenQuestion',dict(QuestionId=q,UserId=voter),'Users',voter)
            before=scalar(c,'SELECT AnswerCount FROM dbo.Posts WHERE Id=%s',(q,))
            jobs=[('CreateAnswer',dict(QuestionId=q,UserId=voter,Body=marker))]*n
            jobs.insert(n//2,('CloseQuestion',dict(QuestionId=q,UserId=voter,Reason=marker)))
            result=race(c,jobs,'Posts',q)
            answers=[r[1] for job,r in zip(jobs,result) if job[0]=='CreateAnswer' and r[0]=='Applied']
            posts.extend(answers)
            assert all(r[0] in ('Applied','Conflict') for r in result)
            assert result[n//2][0]=='Applied'
            assert scalar(c,'SELECT AnswerCount FROM dbo.Posts WHERE Id=%s',(q,))==before+len(answers)
            assert scalar(c,f'SELECT COUNT_BIG(*) FROM dbo.Posts a JOIN dbo.Posts q ON q.Id=a.ParentId WHERE q.Id={q} AND a.Id>{q2} AND a.CreationDate>q.ClosedDate')==0
            # Forced arithmetic failure on OWNED user only, after vote/score insertion.
            # Full caller rollback is the documented contract for these mutators.
            applied('RemovePostVote',PostId=q,UserId=voter)
            before=scalar(c,'SELECT Score FROM dbo.Posts WHERE Id=%s',(q,))
            failure=query(c,f"""BEGIN TRANSACTION;
            UPDATE dbo.Users SET Reputation=2147483647 WHERE Id={int(owner)};
            BEGIN TRY
             EXEC dbo.Stackish_UpvoteQuestion @QuestionId={int(q)},@UserId={int(voter)};
            END TRY
            BEGIN CATCH
             SELECT ERROR_NUMBER() AS ErrorNumber,@@TRANCOUNT AS TransactionCount;
            END CATCH;""")
            assert len(failure)==1 and failure[0][1]==[(8115,0)],failure
            emit('expected vote overflow',error_number=8115,transaction_count=0)
            assert scalar(c,'SELECT @@TRANCOUNT')==0
            assert scalar(c,'SELECT Score FROM dbo.Posts WHERE Id=%s',(q,))==before
            assert scalar(c,'SELECT COUNT_BIG(*) FROM dbo.Votes WHERE PostId=%s AND UserId=%s AND VoteTypeId IN(2,3)',(q,voter))==0
            emit('contention assertions passed',answer_race_applied=len(answers),answer_race_conflict=n-len(answers),forced_failure_rolled_back=True)
        finally:
            query(c,'IF @@TRANCOUNT>0 ROLLBACK;')
            # An interrupted/erroring worker may have created a child before its result reached
            # the client. It still carries this run's unique body/owner and new parent IDs.
            if posts and users:
                discovered=rows(c,'SELECT Id FROM dbo.Posts WHERE ParentId IN (%s,%s) AND OwnerUserId=%s AND Body=%s',(posts[0],posts[1],users[1],marker)) if len(posts)>1 else []
                posts=list(set(posts+[r[0] for r in discovered]))
                pids=','.join(map(str,posts));uids=','.join(map(str,users))
                query(c,'BEGIN TRANSACTION;')
                for table in ('Votes','Comments','PostHistory','PostLinks'):
                    ids=[r[0] for r in rows(c,f'SELECT Id FROM dbo.{table} WHERE Id>{base[table]} AND PostId IN ({pids})')]
                    if ids:query(c,f'DELETE dbo.{table} WHERE Id IN ({",".join(map(str,ids))});')
                query(c,f'DELETE dbo.Posts WHERE Id IN ({pids});')
                query(c,f'DELETE dbo.Users WHERE Id IN ({uids});')
                if tag_ids:query(c,f'DELETE dbo.Tags WHERE Id IN ({",".join(map(str,tag_ids))});')
                query(c,'COMMIT;')
                assert scalar(c,f'SELECT COUNT_BIG(*) FROM dbo.Posts WHERE Id IN ({pids})')==0
                assert scalar(c,f'SELECT COUNT_BIG(*) FROM dbo.Users WHERE Id IN ({uids})')==0
            emit('owned fixture cleanup complete',marker=marker,identities_not_reseeded=True)

if __name__=='__main__':main()
