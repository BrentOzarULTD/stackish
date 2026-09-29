-- Read-only checks for the public object inventory and result metadata.
SET NOCOUNT ON;
IF (SELECT COUNT(*) FROM sys.objects WHERE schema_id=SCHEMA_ID(N'dbo') AND name IN
    (N'Stackish_SplitTags',N'Stackish_ListTags',N'Stackish_GetTagDetail',N'Stackish_GetTagTopUsers'))<>4
    THROW 51000, 'One or more step-1 objects are missing.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id=OBJECT_ID(N'dbo.Stackish_SplitTags') AND type='IF')
    THROW 51000, 'The parser must be an inline table-valued function.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.Stackish_SplitTags')
               AND name=N'TagName' AND TYPE_NAME(system_type_id)=N'nvarchar' AND max_length=300)
    THROW 51000, 'Parser result metadata does not match TagName nvarchar(150).', 1;
SELECT OBJECT_NAME(p.object_id) AS ObjectName,p.parameter_id,p.name,TYPE_NAME(p.user_type_id) AS TypeName,p.max_length
FROM sys.parameters p WHERE p.object_id IN
    (OBJECT_ID(N'dbo.Stackish_SplitTags'),OBJECT_ID(N'dbo.Stackish_ListTags'),
     OBJECT_ID(N'dbo.Stackish_GetTagDetail'),OBJECT_ID(N'dbo.Stackish_GetTagTopUsers'))
ORDER BY ObjectName,p.parameter_id;
SELECT column_ordinal,name,system_type_name
FROM sys.dm_exec_describe_first_result_set(N'EXEC dbo.Stackish_ListTags',NULL,0);
SELECT column_ordinal,name,system_type_name
FROM sys.dm_exec_describe_first_result_set(N'EXEC dbo.Stackish_GetTagDetail @TagName=N''sql''',NULL,0);
-- GetTagTopUsers uses a local temp table: static result-set discovery cannot describe
-- that branch. acceptance.sql verifies its returned shape with INSERT ... EXEC.
PRINT 'Step 1 metadata checks passed.';
