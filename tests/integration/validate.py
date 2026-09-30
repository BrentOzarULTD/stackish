#!/usr/bin/env python3
"""Offline contracts, repeatable deployment, or rolled-back integration smoke."""
import argparse
import re
from common import ROOT, CONTRACTS, batches, call, connect, emit, query, rows, scalar


def header_parameters(text):
    text=re.sub(r'--[^\n]*|/\*.*?\*/','',text,flags=re.S)
    matches=re.findall(r'(@\w+)\s+(\w+(?:\s*\(\s*(?:max|\d+)\s*\))?)\s*(?:=\s*(NULL|N?\'[^\']*\'|-?\d+))?',text,re.I)
    return [{'name':name,'type':re.sub(r'\s','',typ.lower()),'default':default or None} for name,typ,default in matches]


def static():
    found={}
    for path in (ROOT/'sql').glob('*/Stackish_*.sql'):
        for kind,name,header in re.findall(r'CREATE OR ALTER (PROCEDURE|FUNCTION) dbo\.(Stackish_\w+)(.*?)(?:\bAS\b|\bRETURNS\b)',path.read_text(),re.S|re.I):
            assert name not in found, name
            found[name]=path
            expected=CONTRACTS[name]
            assert expected['kind']==('P' if kind.upper()=='PROCEDURE' else 'IF')
            actual=header_parameters(header)
            assert actual==expected['parameters'],(name,actual,expected['parameters'])
    assert set(found)==set(CONTRACTS),set(CONTRACTS)^set(found)
    deployed='\n'.join(batches(ROOT/'sql/deploy.sql'))
    assert deployed.index('FUNCTION dbo.Stackish_SplitTags') < deployed.index('PROCEDURE dbo.')
    names=re.findall(r'CREATE OR ALTER (?:PROCEDURE|FUNCTION) dbo\.(Stackish_\w+)',deployed,re.I)
    assert sorted(names)==sorted(CONTRACTS)
    # Deployment may create modules only; no data writes, schema migrations or settings.
    for part in deployed.split('CREATE OR ALTER')[0], (ROOT/'sql/inventory.sql').read_text():
        assert not re.search(r'\b(?:UPDATE|DELETE|INSERT\s+(?:INTO\s+)?dbo\.|ALTER DATABASE|CREATE TABLE|CREATE INDEX)\b',part,re.I)
    emit('offline contracts and deployment inventory', objects=len(found))


def metadata(c):
    for name,expected in CONTRACTS.items():
        got=rows(c,"""SELECT p.name,TYPE_NAME(p.user_type_id),p.max_length,p.is_output
         FROM sys.parameters p WHERE p.object_id=OBJECT_ID(%s) AND p.parameter_id>0 ORDER BY p.parameter_id""",('dbo.'+name,))
        actual=[]
        for pname,typ,size,out in got:
            assert not out,(name,pname,'unexpected OUTPUT')
            if typ in ('nvarchar','varchar'):
                typ+=f"({'max' if size==-1 else size//(2 if typ=='nvarchar' else 1)})"
            actual.append((pname,typ))
        assert actual==[(p['name'],p['type']) for p in expected['parameters']],(name,actual)
        definition=scalar(c,'SELECT OBJECT_DEFINITION(OBJECT_ID(%s))',('dbo.'+name,))
        header=re.split(r'\bAS\b|\bRETURNS\b',definition,flags=re.I)[0]
        assert header_parameters(header)==expected['parameters'],(name,'defaults/header')
    parser=query(c,"SELECT * FROM dbo.Stackish_SplitTags(N'<integration><tags>') ORDER BY TagName;")
    assert [s[0] for s in parser]==CONTRACTS['Stackish_SplitTags']['results']
    assert parser[0][1]==[('integration',),('tags',)]
    emit('deployed signatures and defaults',objects=len(CONTRACTS))


def fingerprint(c):
    # All base schemas/indexes/constraints and relevant database settings; no data scan.
    return rows(c,"""SELECT (SELECT t.name AS TableName,c.name AS ColumnName,c.column_id,c.user_type_id,c.max_length,c.is_nullable,c.is_identity,c.default_object_id
     FROM sys.tables t JOIN sys.columns c ON c.object_id=t.object_id ORDER BY t.object_id,c.column_id FOR JSON PATH),
     (SELECT i.object_id,i.index_id,i.name,i.type,i.is_unique,i.filter_definition,ic.column_id,ic.key_ordinal,ic.is_included_column
     FROM sys.indexes i JOIN sys.tables t ON t.object_id=i.object_id LEFT JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
     ORDER BY i.object_id,i.index_id,ic.index_column_id FOR JSON PATH),
     (SELECT object_id,parent_object_id,name,type,modify_date FROM sys.objects WHERE type IN ('C','D','F','PK','UQ','TR') ORDER BY object_id FOR JSON PATH),
     (SELECT compatibility_level,collation_name,is_read_committed_snapshot_on,snapshot_isolation_state,is_auto_close_on,is_auto_shrink_on,recovery_model
     FROM sys.databases WHERE database_id=DB_ID() FOR JSON PATH)""")[0]


def deploy(c):
    before=fingerprint(c)
    for attempt in (1,2):
        for batch in batches(ROOT/'sql/deploy.sql'):
            query(c,batch)
        assert fingerprint(c)==before,'Deployment changed base schema/indexes/constraints/settings'
        metadata(c)
        emit('deployment',attempt=attempt,base_metadata_unchanged=True)


def smoke(c, quick=False):
    metadata(c)
    query(c,'SET NOCOUNT ON; SET XACT_ABORT OFF; BEGIN TRANSACTION;')
    options=scalar(c,'SELECT @@OPTIONS')
    history_start=scalar(c,'SELECT COALESCE(MAX(Id),0) FROM dbo.PostHistory')
    missing=-2147483648
    try:
        for table in ('Users','Posts','Comments','PostLinks'):
            assert scalar(c,f'SELECT COUNT_BIG(*) FROM dbo.{table} WHERE Id=%s',(missing,))==0
        tags=rows(c,"""SELECT TOP(2) TagName,[Count] FROM dbo.Tags t WHERE LEN(TagName) BETWEEN 1 AND 60
          AND CHARINDEX('<',TagName)=0 AND CHARINDEX('>',TagName)=0
          AND (SELECT COUNT_BIG(*) FROM dbo.Tags x WHERE x.TagName=t.TagName)=1 ORDER BY Id""")
        assert len(tags)==2,'Two usable existing tags required'
        t1,t2=(r[0] for r in tags)
        def tag_count(t): return scalar(c,'SELECT [Count] FROM dbo.Tags WHERE TagName=%s',(t,))
        def applied(name,**kw): return call(c,name,'Applied',**kw)[0][0][1]
        u=applied('CreateUser',DisplayName='Stackish integration owner')
        v=applied('CreateUser',DisplayName='Stackish integration actor')
        profile_baseline=rows(c,'''SELECT
         (SELECT COUNT_BIG(*) FROM dbo.Posts WHERE OwnerUserId=%s AND PostTypeId=1),
         (SELECT COUNT_BIG(*) FROM dbo.Posts WHERE OwnerUserId=%s AND PostTypeId=2),
         (SELECT COUNT_BIG(*) FROM dbo.Comments WHERE UserId=%s),
         (SELECT COUNT_BIG(*) FROM dbo.Badges WHERE UserId=%s)''',(u,u,u,u))[0]
        q=applied('CreateQuestion',UserId=u,Title='Stackish integration question',Body='Integration body',Tags=f'<{t1}>')
        q2=applied('CreateQuestion',UserId=u,Title='Stackish integration related',Body='Related body',Tags=f'<{t2}>')
        assert [tag_count(t1),tag_count(t2)]==[tags[0][1]+1,tags[1][1]+1]
        # Legacy rows can point at fresh identities. Never delete them to make a fixture clean.
        assert scalar(c,'SELECT COUNT_BIG(*) FROM dbo.Votes WHERE PostId=%s AND UserId=%s AND VoteTypeId IN(2,3)',(q,v))==0,'Fixture collided with attributed historical vote; rollback and rerun'
        historical_votes=rows(c,'SELECT Id,UserId,VoteTypeId FROM dbo.Votes WHERE PostId=%s ORDER BY Id',(q,))
        before=scalar(c,'SELECT COALESCE(AnswerCount,0) FROM dbo.Posts WHERE Id=%s',(q,))
        a=applied('CreateAnswer',QuestionId=q,UserId=v,Body='Integration answer')
        assert scalar(c,'SELECT AnswerCount FROM dbo.Posts WHERE Id=%s',(q,))==before+1
        before=scalar(c,'SELECT COALESCE(CommentCount,0) FROM dbo.Posts WHERE Id=%s',(a,))
        comment=applied('AddComment',PostId=a,UserId=u,Text='Integration comment')
        assert scalar(c,'SELECT CommentCount FROM dbo.Posts WHERE Id=%s',(a,))==before+1
        applied('EditComment',CommentId=comment,UserId=u,Text='Edited integration comment')
        applied('EditQuestion',QuestionId=q,EditorUserId=v,Title='Edited integration question',Body='Edited body')
        applied('EditAnswer',AnswerId=a,EditorUserId=u,Body='Edited answer')
        applied('RetagQuestion',QuestionId=q,EditorUserId=v,Tags=f'<{t2}>')
        assert [tag_count(t1),tag_count(t2)]==[tags[0][1],tags[1][1]+2]
        applied('UpdateUserProfile',UserId=u,DisplayName='Edited integration owner',Location='Integration')
        for name,key,id_,column,table in [('RecordQuestionView','QuestionId',q,'ViewCount','Posts'),('RecordProfileView','UserId',u,'Views','Users')]:
            initial=scalar(c,f'SELECT {column} FROM dbo.{table} WHERE Id=%s',(id_,))
            applied(name,**{key:id_})
            assert scalar(c,f'SELECT {column} FROM dbo.{table} WHERE Id=%s',(id_,))==initial+1
        applied('RecordUserAccess',UserId=u)
        for name,key,post,actor,owner,delta,counter in [
            ('UpvoteQuestion','QuestionId',q,v,u,1,'UpVotes'),('DownvoteQuestion','QuestionId',q,v,u,-1,'DownVotes'),
            ('UpvoteAnswer','AnswerId',a,u,v,1,'UpVotes'),('DownvoteAnswer','AnswerId',a,u,v,-1,'DownVotes')]:
            baseline=rows(c,f'SELECT p.Score,o.Reputation,v.{counter} FROM dbo.Posts p CROSS JOIN dbo.Users o CROSS JOIN dbo.Users v WHERE p.Id=%s AND o.Id=%s AND v.Id=%s',(post,owner,actor))[0]
            applied(name,**{key:post,'UserId':actor})
            now=rows(c,f'SELECT p.Score,o.Reputation,v.{counter} FROM dbo.Posts p CROSS JOIN dbo.Users o CROSS JOIN dbo.Users v WHERE p.Id=%s AND o.Id=%s AND v.Id=%s',(post,owner,actor))[0]
            assert now==(baseline[0]+delta,max(1,baseline[1]+(10 if delta==1 else -2)),baseline[2]+1),(name,baseline,now)
            call(c,name,'NoChange',**{key:post,'UserId':actor})
            applied('RemovePostVote',PostId=post,UserId=actor)
            after=rows(c,f'SELECT p.Score,o.Reputation,v.{counter} FROM dbo.Posts p CROSS JOIN dbo.Users o CROSS JOIN dbo.Users v WHERE p.Id=%s AND o.Id=%s AND v.Id=%s',(post,owner,actor))[0]
            assert after==(baseline[0],max(1,now[1]+(-10 if delta==1 else 2)),baseline[2])
        assert rows(c,'SELECT Id,UserId,VoteTypeId FROM dbo.Votes WHERE PostId=%s ORDER BY Id',(q,))==historical_votes
        acceptance_users=rows(c,'SELECT Id,Reputation,UpVotes,DownVotes FROM dbo.Users WHERE Id IN (%s,%s) ORDER BY Id',(u,v))
        applied('SetAcceptedAnswer',QuestionId=q,UserId=u,AnswerId=a)
        assert scalar(c,'SELECT AcceptedAnswerId FROM dbo.Posts WHERE Id=%s',(q,))==a
        # Linked pair may collide with imported orphan links; abort rather than remove history.
        assert scalar(c,'SELECT COUNT_BIG(*) FROM dbo.PostLinks WHERE PostId=%s AND RelatedPostId=%s',(q,q2))==0
        link=applied('AddQuestionLink',QuestionId=q,RelatedQuestionId=q2,UserId=v)
        page=call(c,'GetQuestionPage',QuestionId=q)
        assert page[0][0][0]==q and page[0][0][10]==a
        assert any(r[0]==a and r[-1] for r in page[1])
        assert any(r[0]==comment for r in page[2])
        assert any(r[0]==link for r in page[3]) and page[4]==[(t2,)]
        profile_before=scalar(c,'SELECT Views FROM dbo.Users WHERE Id=%s',(u,))
        profile=call(c,'GetUserProfile',UserId=u)
        assert profile[0][0][0]==u
        assert profile[1][0]==(u,profile_baseline[0]+2,profile_baseline[1],profile_baseline[2]+1,profile_baseline[3]),profile[1]
        assert scalar(c,'SELECT Views FROM dbo.Users WHERE Id=%s',(u,))==profile_before
        applied('SetAcceptedAnswer',QuestionId=q,UserId=u,AnswerId=None)
        assert scalar(c,'SELECT AcceptedAnswerId FROM dbo.Posts WHERE Id=%s',(q,)) is None
        assert rows(c,'SELECT Id,Reputation,UpVotes,DownVotes FROM dbo.Users WHERE Id IN (%s,%s) ORDER BY Id',(u,v))==acceptance_users
        assert rows(c,'SELECT Id,UserId,VoteTypeId FROM dbo.Votes WHERE PostId=%s ORDER BY Id',(q,))==historical_votes
        applied('CloseQuestion',QuestionId=q,UserId=v,Reason='Integration close')
        call(c,'CreateAnswer','Conflict',QuestionId=q,UserId=v,Body='Must be rejected')
        applied('ReopenQuestion',QuestionId=q,UserId=v)
        applied('RemoveQuestionLink',LinkId=link,UserId=v)
        applied('DeleteComment',CommentId=comment,UserId=u)
        assert scalar(c,'SELECT CommentCount FROM dbo.Posts WHERE Id=%s',(a,))==before
        history=rows(c,'SELECT PostHistoryTypeId,COUNT_BIG(*) FROM dbo.PostHistory WHERE PostId=%s AND Id>%s GROUP BY PostHistoryTypeId ORDER BY PostHistoryTypeId',(q,history_start))
        assert history==[(kind,1) for kind in (1,2,3,4,5,6,10,11)],history
        assert scalar(c,'SELECT COUNT(DISTINCT RevisionGUID) FROM dbo.PostHistory WHERE PostId=%s AND Id>%s AND PostHistoryTypeId IN(1,2,3)',(q,history_start))==1
        calls={
            'GetUserCard':dict(UserId=u),'ListUsers':dict(NamePrefix='Edited integration owner'),
            'ListQuestions':{},'SearchQuestions':dict(OwnerUserId=u,Text='Edited integration'),
            'GetQuestionsByTag':dict(TagName=t2),'GetUnansweredQuestions':dict(TagName=t2),
            'GetRelatedQuestions':dict(QuestionId=q),'ListTags':dict(NamePrefix=t2),
            'GetTagDetail':dict(TagName=t2),'GetTagTopUsers':dict(TagName=t2),
            'GetUserPosts':dict(UserId=u),'GetPostHistory':dict(PostId=q),
            'GetPostComments':dict(PostId=a),'GetPostVoteSummary':dict(PostId=q),
            'GetUserBadges':dict(UserId=u),'ListBadges':{},
            'GetBadgeRecipients':dict(BadgeName=scalar(c,'SELECT TOP(1) Name FROM dbo.Badges ORDER BY Id'))}
        if quick:
            expensive={'ListQuestions','GetQuestionsByTag','GetUnansweredQuestions','GetRelatedQuestions','GetTagTopUsers','ListBadges','GetBadgeRecipients'}
            calls={name:args for name,args in calls.items() if name not in expensive}
            emit('quick smoke',omitted_global_read_checks=sorted(expensive))
        for name,args in calls.items():
            if any(p['name']=='@PageSize' for p in CONTRACTS['Stackish_'+name]['parameters']): args['PageSize']=2
            call(c,name,**args)
        # Every missing-target page result must be present, typed, and empty.
        for name,args in [('GetQuestionPage',dict(QuestionId=missing)),('GetQuestionPage',dict(QuestionId=a)),('GetUserProfile',dict(UserId=missing))]:
            assert not any(call(c,name,**args)),name
        for name,args in calls.items():
            args=args.copy()
            key=next((k for k in ('UserId','PostId','QuestionId','OwnerUserId','TagName','BadgeName','NamePrefix') if k in args),None)
            if key:
                args[key]=('stackish-missing-6d2ea849' if key in ('TagName','BadgeName','NamePrefix') else missing)
                assert not any(call(c,name,**args)),(name,'missing target not empty')
        # Required valid actor/text values accompany missing mutation targets.
        missing_calls={
            'UpdateUserProfile':dict(UserId=missing,DisplayName='Missing'),
            'RecordUserAccess':dict(UserId=missing),'RecordProfileView':dict(UserId=missing),
            'CreateQuestion':dict(UserId=missing,Title='Missing',Body='Missing',Tags=f'<{t1}>'),
            'EditQuestion':dict(QuestionId=missing,EditorUserId=u,Title='Missing',Body='Missing'),
            'RetagQuestion':dict(QuestionId=missing,EditorUserId=u,Tags=f'<{t1}>'),
            'RecordQuestionView':dict(QuestionId=missing),
            'CreateAnswer':dict(QuestionId=missing,UserId=u,Body='Missing'),
            'EditAnswer':dict(AnswerId=missing,EditorUserId=u,Body='Missing'),
            'SetAcceptedAnswer':dict(QuestionId=missing,UserId=u),
            'AddComment':dict(PostId=missing,UserId=u,Text='Missing'),
            'EditComment':dict(CommentId=missing,UserId=u,Text='Missing'),
            'DeleteComment':dict(CommentId=missing,UserId=u),
            'RemovePostVote':dict(PostId=missing,UserId=u),
            'CloseQuestion':dict(QuestionId=missing,UserId=u,Reason='Missing'),
            'ReopenQuestion':dict(QuestionId=missing,UserId=u),
            'AddQuestionLink':dict(QuestionId=missing,RelatedQuestionId=q,UserId=u),
            'RemoveQuestionLink':dict(LinkId=missing,UserId=u)}
        for name in ('UpvoteQuestion','DownvoteQuestion','UpvoteAnswer','DownvoteAnswer'):
            missing_calls[name]={('QuestionId' if name.endswith('Question') else 'AnswerId'):missing,'UserId':u}
        for name,args in missing_calls.items(): call(c,name,'Conflict' if name=='CreateQuestion' else 'NotFound',**args)
        assert scalar(c,'SELECT @@TRANCOUNT')==1
        assert scalar(c,'SELECT @@OPTIONS')==options,'Procedure leaked session options'
        emit('smoke assertions passed',rollback=True)
    finally:
        query(c,'IF @@TRANCOUNT>0 ROLLBACK;')
        assert scalar(c,'SELECT @@TRANCOUNT')==0
        emit('smoke fixture rollback complete',identity_allocations_not_reseeded=True)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('mode',choices=['static','deploy','smoke'])
    parser.add_argument('--quick',action='store_true',help='Workflow/page checks only; omit seven expensive global read checks')
    parser.add_argument('--allow-mutations',action='store_true',help='Acknowledge deployment or disposable-database fixture mutations')
    args=parser.parse_args()
    static()
    if args.mode!='static':
        if not args.allow_mutations: parser.error('--allow-mutations is required')
        with connect() as c:
            emit('target',database=scalar(c,'SELECT DB_NAME()'),engine=scalar(c,"SELECT CONVERT(varchar(30),SERVERPROPERTY('ProductVersion'))"))
            deploy(c) if args.mode=='deploy' else smoke(c,quick=args.quick)

if __name__=='__main__': main()
