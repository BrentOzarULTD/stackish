#!/usr/bin/env python3
"""Release-format regressions: owned fixtures roll back; no imported-row changes."""
import argparse
import uuid
from common import ROOT,batches,call,connect,emit,query,rows,scalar


def check(c):
    for source,expected in [(None,[]),('',[]),('|java|javascript|java|',[('java',),('javascript',)]),
                            ('<java><javascript>',[('java',),('javascript',)]),
                            ('|java| |',[('java',)]),('java|',[]),('|java',[])]:
        assert rows(c,'SELECT TagName FROM dbo.Stackish_SplitTags(%s) ORDER BY TagName',(source,))==expected
    emit('both imported tag formats parsed')
    query(c,'SET NOCOUNT ON; SET XACT_ABORT OFF; BEGIN TRANSACTION;')
    try:
        marker='stkrelease-'+uuid.uuid4().hex[:16]
        for name in (marker,marker+'x'):
            query(c,'INSERT dbo.Tags(TagName,[Count],ExcerptPostId,WikiPostId) VALUES(%s,0,0,0)',(name,))
        def applied(name,**args):return call(c,name,'Applied',**args)[0][0][1]
        u=applied('CreateUser',DisplayName=marker)
        q=applied('CreateQuestion',UserId=u,Title=marker,Body=marker,Tags='<'+marker+'>')
        q2=applied('CreateQuestion',UserId=u,Title=marker,Body=marker,Tags='<'+marker+'>')
        wrong=applied('CreateQuestion',UserId=u,Title=marker,Body=marker,Tags='<'+marker+'x>')
        q3=applied('CreateQuestion',UserId=u,Title=marker,Body=marker,Tags='<'+marker+'><'+marker+'x>')
        a=applied('CreateAnswer',QuestionId=q,UserId=u,Body=marker)
        query(c,'UPDATE dbo.Posts SET Tags=%s WHERE Id=%s',('|'+marker+'|',q))
        query(c,'UPDATE dbo.Posts SET Tags=%s WHERE Id=%s',('|'+marker+'x|',wrong))
        query(c,'UPDATE dbo.Posts SET Tags=%s WHERE Id=%s',('|'+marker+'|'+marker+'x|',q3))
        before=rows(c,'SELECT TagName,[Count] FROM dbo.Tags WHERE TagName IN (%s,%s) ORDER BY TagName',(marker,marker+'x'))
        call(c,'RetagQuestion','NoChange',QuestionId=q,EditorUserId=u,Tags='<'+marker+'>')
        assert rows(c,'SELECT TagName,[Count] FROM dbo.Tags WHERE TagName IN (%s,%s) ORDER BY TagName',(marker,marker+'x'))==before
        assert call(c,'GetQuestionPage',QuestionId=q)[4]==[(marker,)]
        assert {r[0] for r in call(c,'SearchQuestions',TagName=marker,OwnerUserId=u)[0]}=={q,q2,q3}
        assert not call(c,'SearchQuestions',TagName=marker+'|'+marker+'x',OwnerUserId=u)[0]
        assert {r[0] for r in call(c,'GetQuestionsByTag',TagName=marker)[0]}=={q,q2,q3}
        assert {r[0] for r in call(c,'GetUnansweredQuestions',TagName=marker)[0]}=={q2,q3}
        assert {r[0] for r in call(c,'GetRelatedQuestions',QuestionId=q2)[0]}=={q,q3}
        leaders=call(c,'GetTagTopUsers',TagName=marker)[0]
        assert len(leaders)==1 and leaders[0][0]==u and leaders[0][2]==1
        call(c,'RetagQuestion','Applied',QuestionId=q,EditorUserId=u,Tags='<'+marker+'x>')
        after=rows(c,'SELECT TagName,[Count] FROM dbo.Tags WHERE TagName IN (%s,%s) ORDER BY TagName',(marker,marker+'x'))
        assert after==[(marker,before[0][1]-1),(marker+'x',before[1][1]+1)]
        emit('pipe-tag page search exact-membership and retag deltas passed')
    finally:
        query(c,'IF @@TRANCOUNT>0 ROLLBACK;')
        emit('release fixtures rolled back',identities_not_reseeded=True)
    # Rename one deployment-owned index inside a transaction to verify reuse by
    # structure, not by its name. Restore metadata by rollback, not a rebuild.
    if scalar(c,"SELECT COUNT(*) FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Tags') AND name='IX_Stackish_Tags_TagName'"):
        query(c,'BEGIN TRANSACTION;')
        try:
            query(c,"EXEC sys.sp_rename N'dbo.Tags.IX_Stackish_Tags_TagName',N'Stackish_TestEquivalentTagIndex',N'INDEX';")
            actions=[]
            for batch in batches(ROOT/'sql/indexes.sql'):
                actions.extend(row for _,result in query(c,batch) for row in result)
            assert len(actions)==13 and all(row[2]=='Reused' for row in actions),actions
            assert ('Tags','Stackish_TestEquivalentTagIndex','Reused') in actions
            emit('all 13 index specifications reused; alternate name accepted')
        finally:query(c,'IF @@TRANCOUNT>0 ROLLBACK;')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--allow-mutations',action='store_true');args=parser.parse_args()
    if not args.allow_mutations:parser.error('--allow-mutations required')
    with connect() as c:check(c)
