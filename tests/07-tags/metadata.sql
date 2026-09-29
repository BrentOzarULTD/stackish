-- Read-only assertions for the public object inventory, parameters and result metadata.
SET NOCOUNT ON;
DECLARE @objects TABLE (ObjectName sysname, ObjectType char(2), Declaration nvarchar(1000));
-- Default values are not exposed for T-SQL parameters by sys.parameters.
-- Compare the declaration from sys.sql_modules as well as catalog metadata.
-- This deliberately checks these four simple headers, not arbitrary T-SQL syntax.
INSERT @objects VALUES
(N'Stackish_SplitTags','IF',N'@tagsnvarchar(150))'),
(N'Stackish_ListTags','P',N'@nameprefixnvarchar(150)=null,@sortvarchar(20)=''popular'',@offsetint=0,@pagesizeint=30'),
(N'Stackish_GetTagDetail','P',N'@tagnamenvarchar(150)'),
(N'Stackish_GetTagTopUsers','P',N'@tagnamenvarchar(150),@offsetint=0,@pagesizeint=30');
IF EXISTS (
    SELECT 1 FROM @objects e LEFT JOIN sys.objects o
      ON o.schema_id=SCHEMA_ID(N'dbo') AND o.name=e.ObjectName
    WHERE o.object_id IS NULL OR o.type COLLATE DATABASE_DEFAULT<>e.ObjectType
) THROW 51000, 'Step 1 object missing or wrong object type.', 1;

DECLARE @expectedParameters TABLE
(ObjectName sysname, Ordinal int, ParameterName sysname, TypeName sysname, MaxLength smallint, IsOutput bit);
INSERT @expectedParameters VALUES
(N'Stackish_SplitTags',1,N'@Tags',N'nvarchar',300,0),
(N'Stackish_ListTags',1,N'@NamePrefix',N'nvarchar',300,0),
(N'Stackish_ListTags',2,N'@Sort',N'varchar',20,0),
(N'Stackish_ListTags',3,N'@Offset',N'int',4,0),
(N'Stackish_ListTags',4,N'@PageSize',N'int',4,0),
(N'Stackish_GetTagDetail',1,N'@TagName',N'nvarchar',300,0),
(N'Stackish_GetTagTopUsers',1,N'@TagName',N'nvarchar',300,0),
(N'Stackish_GetTagTopUsers',2,N'@Offset',N'int',4,0),
(N'Stackish_GetTagTopUsers',3,N'@PageSize',N'int',4,0);
DECLARE @actualParameters TABLE
(ObjectName sysname, Ordinal int, ParameterName sysname, TypeName sysname, MaxLength smallint, IsOutput bit);
INSERT @actualParameters
SELECT o.ObjectName,p.parameter_id,p.name,TYPE_NAME(p.user_type_id),p.max_length,p.is_output
FROM @objects o JOIN sys.parameters p ON p.object_id=OBJECT_ID(N'dbo.'+o.ObjectName);
IF EXISTS (SELECT * FROM @expectedParameters EXCEPT SELECT * FROM @actualParameters)
OR EXISTS (SELECT * FROM @actualParameters EXCEPT SELECT * FROM @expectedParameters)
    THROW 51000, 'Step 1 parameter count, order, name, type, length or direction mismatch.', 1;

-- Normalize keyword case and ordinary formatting. A header with comments or a
-- different declaration syntax fails closed and needs an explicit test update.
-- Read only the header, so matching defaults elsewhere in the body cannot pass.
DECLARE @definitions TABLE (ObjectName sysname, Definition nvarchar(max), Declaration nvarchar(1000));
INSERT @definitions
SELECT e.ObjectName,
       LOWER(REPLACE(REPLACE(REPLACE(m.definition,CHAR(13),N' '),CHAR(10),N' '),CHAR(9),N' ')),
       e.Declaration
FROM @objects e LEFT JOIN sys.sql_modules m ON m.object_id=OBJECT_ID(N'dbo.'+e.ObjectName);
IF EXISTS (SELECT 1 FROM @definitions WHERE Definition IS NULL)
    THROW 51000, 'Module definitions are required to verify T-SQL parameter defaults.', 1;
IF EXISTS (
    SELECT 1 FROM @definitions d
    CROSS APPLY (VALUES(CHARINDEX(N'@',d.Definition),
        CASE WHEN d.ObjectName=N'Stackish_SplitTags' THEN CHARINDEX(N' returns ',d.Definition)
             ELSE CHARINDEX(N' as ',d.Definition) END)) pos(StartAt,EndAt)
    WHERE pos.StartAt=0 OR pos.EndAt<=pos.StartAt
       OR REPLACE(SUBSTRING(d.Definition,pos.StartAt,
              CASE WHEN pos.EndAt>pos.StartAt THEN pos.EndAt-pos.StartAt ELSE 0 END),N' ',N'')<>d.Declaration
) THROW 51000, 'Step 1 parameter declaration/default mismatch (or unsupported header syntax).', 1;

DECLARE @expectedResults TABLE (ObjectName sysname, Ordinal int, ColumnName sysname, TypeName nvarchar(256));
INSERT @expectedResults VALUES
(N'Stackish_SplitTags',1,N'TagName',N'nvarchar(150)'),
(N'Stackish_ListTags',1,N'TagId',N'int'),
(N'Stackish_ListTags',2,N'TagName',N'nvarchar(150)'),
(N'Stackish_ListTags',3,N'QuestionCount',N'int'),
(N'Stackish_ListTags',4,N'Excerpt',N'nvarchar(max)'),
(N'Stackish_GetTagDetail',1,N'TagId',N'int'),
(N'Stackish_GetTagDetail',2,N'TagName',N'nvarchar(150)'),
(N'Stackish_GetTagDetail',3,N'QuestionCount',N'int'),
(N'Stackish_GetTagDetail',4,N'Excerpt',N'nvarchar(max)'),
(N'Stackish_GetTagDetail',5,N'WikiBody',N'nvarchar(max)');
DECLARE @actualResults TABLE
(ObjectName sysname, Ordinal int, ColumnName sysname, TypeName nvarchar(256), ErrorNumber int);
INSERT @actualResults
SELECT calls.ObjectName,r.column_ordinal,r.name,r.system_type_name,r.error_number
FROM (VALUES
    (N'Stackish_SplitTags',N'SELECT TagName FROM dbo.Stackish_SplitTags(NULL)'),
    (N'Stackish_ListTags',N'EXEC dbo.Stackish_ListTags'),
    (N'Stackish_GetTagDetail',N'EXEC dbo.Stackish_GetTagDetail @TagName=N''sql''')
) calls(ObjectName,SqlText)
CROSS APPLY sys.dm_exec_describe_first_result_set(calls.SqlText,NULL,0) r;
-- Catalog columns also detect an extra TVF output that the explicit SELECT omits.
IF (SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.Stackish_SplitTags'))<>1
    THROW 51000, 'Tag parser must return exactly one column.', 1;
IF EXISTS (SELECT 1 FROM @actualResults WHERE ErrorNumber IS NOT NULL)
OR EXISTS (SELECT * FROM @expectedResults EXCEPT SELECT ObjectName,Ordinal,ColumnName,TypeName FROM @actualResults)
OR EXISTS (SELECT ObjectName,Ordinal,ColumnName,TypeName FROM @actualResults EXCEPT SELECT * FROM @expectedResults)
    THROW 51000, 'Step 1 result column count, order, name or type mismatch.', 1;

-- GetTagTopUsers uses a local temp table: static discovery cannot describe that
-- branch. acceptance.sql exercises its runtime shape, paging and bigint aggregate.
PRINT 'Step 1 metadata assertions passed; leaderboard runtime checks are in acceptance.sql.';
