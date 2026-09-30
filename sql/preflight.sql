-- Read-only preflight. Fail before creating/altering any Stackish object.
IF DB_ID() <= 4 THROW 51000, 'Select the intended Stack Overflow database explicitly.', 1;
IF CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) < 17
 THROW 51000, 'Stackish requires SQL Server 2025 or later.', 1;
IF (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID()) < 170
 THROW 51000, 'Stackish requires compatibility level 170 or later; deployment never changes settings.', 1;
DECLARE @Expected table(TableName sysname, ColumnName sysname, TypeName sysname, MaxLength smallint, Nullable bit, IdentityColumn bit);
INSERT @Expected VALUES
(N'Badges',N'Id',N'int',4,0,1),
(N'Badges',N'Name',N'nvarchar',80,0,0),
(N'Badges',N'UserId',N'int',4,0,0),
(N'Badges',N'Date',N'datetime',8,0,0),
(N'Comments',N'Id',N'int',4,0,1),
(N'Comments',N'CreationDate',N'datetime',8,0,0),
(N'Comments',N'PostId',N'int',4,0,0),
(N'Comments',N'Score',N'int',4,1,0),
(N'Comments',N'Text',N'nvarchar',1400,0,0),
(N'Comments',N'UserId',N'int',4,1,0),
(N'LinkTypes',N'Id',N'int',4,0,1),
(N'LinkTypes',N'Type',N'varchar',50,0,0),
(N'PostHistory',N'Id',N'int',4,0,1),
(N'PostHistory',N'PostHistoryTypeId',N'int',4,0,0),
(N'PostHistory',N'PostId',N'int',4,0,0),
(N'PostHistory',N'RevisionGUID',N'uniqueidentifier',16,0,0),
(N'PostHistory',N'CreationDate',N'datetime',8,0,0),
(N'PostHistory',N'UserId',N'int',4,1,0),
(N'PostHistory',N'UserDisplayName',N'nvarchar',80,1,0),
(N'PostHistory',N'Comment',N'nvarchar',-1,1,0),
(N'PostHistory',N'Text',N'nvarchar',-1,1,0),
(N'PostHistoryTypes',N'Id',N'int',4,0,1),
(N'PostHistoryTypes',N'Type',N'nvarchar',100,0,0),
(N'PostLinks',N'Id',N'int',4,0,1),
(N'PostLinks',N'CreationDate',N'datetime',8,0,0),
(N'PostLinks',N'PostId',N'int',4,0,0),
(N'PostLinks',N'RelatedPostId',N'int',4,0,0),
(N'PostLinks',N'LinkTypeId',N'int',4,0,0),
(N'Posts',N'Id',N'int',4,0,1),
(N'Posts',N'AcceptedAnswerId',N'int',4,1,0),
(N'Posts',N'AnswerCount',N'int',4,1,0),
(N'Posts',N'Body',N'nvarchar',-1,0,0),
(N'Posts',N'ClosedDate',N'datetime',8,1,0),
(N'Posts',N'CommentCount',N'int',4,1,0),
(N'Posts',N'CommunityOwnedDate',N'datetime',8,1,0),
(N'Posts',N'CreationDate',N'datetime',8,0,0),
(N'Posts',N'FavoriteCount',N'int',4,1,0),
(N'Posts',N'LastActivityDate',N'datetime',8,0,0),
(N'Posts',N'LastEditDate',N'datetime',8,1,0),
(N'Posts',N'LastEditorDisplayName',N'nvarchar',80,1,0),
(N'Posts',N'LastEditorUserId',N'int',4,1,0),
(N'Posts',N'OwnerUserId',N'int',4,1,0),
(N'Posts',N'ParentId',N'int',4,1,0),
(N'Posts',N'PostTypeId',N'int',4,0,0),
(N'Posts',N'Score',N'int',4,0,0),
(N'Posts',N'Tags',N'nvarchar',300,1,0),
(N'Posts',N'Title',N'nvarchar',500,1,0),
(N'Posts',N'ViewCount',N'int',4,0,0),
(N'PostTypes',N'Id',N'int',4,0,1),
(N'PostTypes',N'Type',N'nvarchar',100,0,0),
(N'Tags',N'Id',N'int',4,0,1),
(N'Tags',N'TagName',N'nvarchar',300,0,0),
(N'Tags',N'Count',N'int',4,0,0),
(N'Tags',N'ExcerptPostId',N'int',4,0,0),
(N'Tags',N'WikiPostId',N'int',4,0,0),
(N'Users',N'Id',N'int',4,0,1),
(N'Users',N'AboutMe',N'nvarchar',-1,1,0),
(N'Users',N'Age',N'int',4,1,0),
(N'Users',N'CreationDate',N'datetime',8,0,0),
(N'Users',N'DisplayName',N'nvarchar',80,0,0),
(N'Users',N'DownVotes',N'int',4,0,0),
(N'Users',N'EmailHash',N'nvarchar',80,1,0),
(N'Users',N'LastAccessDate',N'datetime',8,0,0),
(N'Users',N'Location',N'nvarchar',200,1,0),
(N'Users',N'Reputation',N'int',4,0,0),
(N'Users',N'UpVotes',N'int',4,0,0),
(N'Users',N'Views',N'int',4,0,0),
(N'Users',N'WebsiteUrl',N'nvarchar',400,1,0),
(N'Users',N'AccountId',N'int',4,1,0),
(N'Votes',N'Id',N'int',4,0,1),
(N'Votes',N'PostId',N'int',4,0,0),
(N'Votes',N'UserId',N'int',4,1,0),
(N'Votes',N'BountyAmount',N'int',4,1,0),
(N'Votes',N'VoteTypeId',N'int',4,0,0),
(N'Votes',N'CreationDate',N'datetime',8,0,0),
(N'VoteTypes',N'Id',N'int',4,0,1),
(N'VoteTypes',N'Name',N'varchar',50,0,0);
IF EXISTS (
 SELECT 1 FROM @Expected e
 LEFT JOIN sys.tables t ON t.name=e.TableName AND t.schema_id=SCHEMA_ID('dbo')
 LEFT JOIN sys.columns c ON c.object_id=t.object_id AND c.name=e.ColumnName
 WHERE c.column_id IS NULL OR TYPE_NAME(c.user_type_id)<>e.TypeName OR c.max_length<>e.MaxLength
 OR c.is_nullable<>e.Nullable OR c.is_identity<>e.IdentityColumn OR c.is_computed=1
)
BEGIN
 SELECT e.*, TYPE_NAME(c.user_type_id) ActualType, c.max_length ActualLength,
 c.is_nullable ActualNullable, c.is_identity ActualIdentity
 FROM @Expected e LEFT JOIN sys.tables t ON t.name=e.TableName AND t.schema_id=SCHEMA_ID('dbo')
 LEFT JOIN sys.columns c ON c.object_id=t.object_id AND c.name=e.ColumnName
 WHERE c.column_id IS NULL OR TYPE_NAME(c.user_type_id)<>e.TypeName OR c.max_length<>e.MaxLength
 OR c.is_nullable<>e.Nullable OR c.is_identity<>e.IdentityColumn OR c.is_computed=1;
 THROW 51001, 'Required base schema mismatch; inspect preceding rows. No schema was changed.', 1;
END;
IF EXISTS (
 SELECT 1 FROM sys.columns c JOIN sys.tables t ON t.object_id=c.object_id
 WHERE t.schema_id=SCHEMA_ID('dbo') AND t.name IN (SELECT TableName FROM @Expected)
 AND NOT EXISTS (SELECT 1 FROM @Expected e WHERE e.TableName=t.name AND e.ColumnName=c.name)
 AND c.is_nullable=0 AND c.is_identity=0 AND c.is_computed=0 AND c.default_object_id=0
)
 THROW 51002, 'Unexpected required base column prevents inserts; inspect the target schema.', 1;
IF EXISTS (
 SELECT DISTINCT e.TableName FROM @Expected e
 WHERE NOT EXISTS (SELECT 1 FROM sys.indexes i
 JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.key_ordinal=1
 JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
 WHERE i.object_id=OBJECT_ID(N'dbo.'+e.TableName) AND i.is_primary_key=1 AND i.is_disabled=0 AND c.name=N'Id'
 AND NOT EXISTS(SELECT 1 FROM sys.index_columns more WHERE more.object_id=i.object_id AND more.index_id=i.index_id AND more.key_ordinal>1))
)
 THROW 51005, 'Required single-column Id primary key is missing or disabled.', 1;
EXEC(N'IF EXISTS (SELECT Id, Label FROM (VALUES (1,N''Question''),(2,N''Answer''),(4,N''TagWikiExerpt''),(5,N''TagWiki'')) e(Id,Label) EXCEPT SELECT Id,[Type] COLLATE database_default FROM dbo.PostTypes) THROW 51003, ''Required PostTypes lookup ID/label mismatch.'', 1;');
EXEC(N'IF EXISTS (SELECT Id, Label FROM (VALUES (1,N''AcceptedByOriginator''),(2,N''UpMod''),(3,N''DownMod''),(5,N''Favorite''),(8,N''BountyStart''),(9,N''BountyClose'')) e(Id,Label) EXCEPT SELECT Id,[Name] COLLATE database_default FROM dbo.VoteTypes) THROW 51003, ''Required VoteTypes lookup ID/label mismatch.'', 1;');
EXEC(N'IF EXISTS (SELECT Id, Label FROM (VALUES (1,N''InitialTitle''),(2,N''InitialBody''),(3,N''InitialTags''),(4,N''EditTitle''),(5,N''EditBody''),(6,N''EditTags''),(10,N''PostClosed''),(11,N''PostReopened'')) e(Id,Label) EXCEPT SELECT Id,[Type] COLLATE database_default FROM dbo.PostHistoryTypes) THROW 51003, ''Required PostHistoryTypes lookup ID/label mismatch.'', 1;');
EXEC(N'IF EXISTS (SELECT Id, Label FROM (VALUES (1,N''Linked''),(3,N''Duplicate'')) e(Id,Label) EXCEPT SELECT Id,[Type] COLLATE database_default FROM dbo.LinkTypes) THROW 51003, ''Required LinkTypes lookup ID/label mismatch.'', 1;');
SELECT DB_NAME() AS DeploymentDatabase, CONVERT(varchar(30), SERVERPROPERTY('ProductVersion')) AS EngineVersion;
GO
