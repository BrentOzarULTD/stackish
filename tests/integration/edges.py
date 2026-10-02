#!/usr/bin/env python3
"""Focused page/reference and caller-session checks using owned, rolled-back rows."""
import argparse
from common import call,connect,emit,query,rows,scalar


def check(c):
    query(c,'SET NOCOUNT ON; SET XACT_ABORT OFF; BEGIN TRANSACTION;')
    try:
        def applied(name,**kw):return call(c,name,'Applied',**kw)[0][0][1]
        tag=scalar(c,"SELECT TOP(1) TagName FROM dbo.Tags t WHERE LEN(TagName)<60 AND (SELECT COUNT(*) FROM dbo.Tags x WHERE x.TagName=t.TagName)=1 ORDER BY Id")
        u=applied('CreateUser',DisplayName='Stackish reference fixture')
        q=applied('CreateQuestion',UserId=u,Title='Reference fixture',Body='Body',Tags='<'+tag+'>')
        a=applied('CreateAnswer',QuestionId=q,UserId=u,Body='Answer')
        history_id=scalar(c,'SELECT MAX(Id) FROM dbo.PostHistory WHERE PostId=%s',(q,))
        query(c,'UPDATE dbo.PostHistory SET UserId=0 WHERE Id=%s',(history_id,))
        history=call(c,'GetPostHistory',PostId=q)[0]
        assert next(r for r in history if r[0]==history_id)[4] is None
        # Only owned rows are given unusual legacy states, all rolled back below.
        query(c,"UPDATE dbo.Posts SET ParentId=Id,AcceptedAnswerId=Id,Title=N'Wrong-type parent' WHERE Id=%s",(a,))
        user_posts=call(c,'GetUserPosts',UserId=u)[0]
        answer=next(r for r in user_posts if r[0]==a)
        assert answer[2]==a and answer[3] is None and answer[-1] is False,('wrong-type parent',answer)
        profile=call(c,'GetUserProfile',UserId=u)
        answer=next(r for r in profile[2] if r[0]==a)
        assert answer[3] is None and answer[-1] is False,('profile wrong-type parent',answer)
        query(c,'UPDATE dbo.Posts SET ParentId=%s,AcceptedAnswerId=NULL,Title=NULL WHERE Id=%s',(q,a))
        newer=applied('CreateAnswer',QuestionId=q,UserId=u,Body='Newer answer')
        qc=applied('AddComment',PostId=q,UserId=u,Text='Question comment')
        applied('AddComment',PostId=a,UserId=u,Text='Off-page answer comment')
        ac=applied('AddComment',PostId=newer,UserId=u,Text='First visible answer comment')
        applied('AddComment',PostId=newer,UserId=u,Text='Second visible answer comment')
        limited=call(c,'GetQuestionPage',QuestionId=q,AnswerPageSize=1,CommentLimit=1)
        assert len(limited[1])==1 and limited[1][0][0]==newer
        # New identities can acquire imported orphan comments. Preserve those rows and
        # compare the preview with each post's actual oldest row, not fixture IDs.
        oldest={scalar(c,'SELECT TOP(1) Id FROM dbo.Comments WHERE PostId=%s ORDER BY CreationDate,Id',(post,)) for post in (q,newer)}
        assert {r[0] for r in limited[2]}==oldest,limited[2]
        assert [r[1] for r in limited[2]]==sorted((q,newer))
        assert not call(c,'GetQuestionPage',QuestionId=q,AnswerPageSize=1,CommentLimit=0)[2]
        query(c,'UPDATE dbo.Posts SET OwnerUserId=0,AcceptedAnswerId=0,LastEditorUserId=0 WHERE Id=%s',(q,))
        before=scalar(c,'SELECT ViewCount FROM dbo.Posts WHERE Id=%s',(q,))
        page=call(c,'GetQuestionPage',QuestionId=q)
        assert page[0][0][10] is None and page[0][0][11] is None and page[0][0][17] is None
        assert scalar(c,'SELECT ViewCount FROM dbo.Posts WHERE Id=%s',(q,))==before
        query(c,"UPDATE dbo.Posts SET Tags=N'<stackish-missing-catalog-e184>' WHERE Id=%s",(q,))
        assert scalar(c,"SELECT COUNT_BIG(*) FROM dbo.Tags WHERE TagName=N'stackish-missing-catalog-e184'")==0
        assert not any(call(c,'GetQuestionsByTag',TagName='stackish-missing-catalog-e184'))
        query(c,'DELETE dbo.Users WHERE Id=%s',(u,))
        # Content remains visible without its author, while missing-user pages are empty.
        assert call(c,'GetQuestionPage',QuestionId=q)[1][0][9] is None
        assert not any(call(c,'GetUserProfile',UserId=u))
        assert not any(call(c,'GetUserPosts',UserId=u))
        emit('reference edge assertions passed')
    finally:query(c,'IF @@TRANCOUNT>0 ROLLBACK;')
    for setting,state in [('OFF',1),('ON',-1)]:
        # Catch within the SAME SQL batch: an uncaught error can make SQL Server
        # roll back the doomed transaction before the client sends its next query.
        result=query(c,f"""SET XACT_ABORT {setting}; BEGIN TRANSACTION;
        BEGIN TRY
         EXEC dbo.Stackish_CreateUser @DisplayName=N'';
        END TRY
        BEGIN CATCH
         SELECT XACT_STATE() AS StateInsideCatch,ERROR_NUMBER() AS ErrorNumber;
        END CATCH;
        IF @@TRANCOUNT>0 ROLLBACK;""")
        assert len(result)==1 and result[0][1]==[(state,50101)],(setting,result)
        assert scalar(c,'SELECT @@TRANCOUNT')==0
    query(c,'SET XACT_ABORT OFF;')
    emit('inherited session policy assertions passed')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--allow-mutations',action='store_true');a=p.parse_args()
    if not a.allow_mutations:p.error('--allow-mutations required')
    with connect() as c:check(c)
