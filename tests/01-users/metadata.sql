-- Read-only assertions: the six Users procedures exist with the contracted parameters,
-- defaults and result shapes. Throws on any mismatch.
SET NOCOUNT ON;

DECLARE @expected TABLE (Proc_ sysname, Ord int, Name sysname, TypeName sysname, MaxLen smallint);
INSERT @expected VALUES
 (N'Stackish_CreateUser',1,N'@DisplayName',N'nvarchar',-1),(N'Stackish_CreateUser',2,N'@AboutMe',N'nvarchar',-1),
 (N'Stackish_CreateUser',3,N'@Location',N'nvarchar',-1),(N'Stackish_CreateUser',4,N'@WebsiteUrl',N'nvarchar',-1),
 (N'Stackish_CreateUser',5,N'@Age',N'int',4),
 (N'Stackish_UpdateUserProfile',1,N'@UserId',N'int',4),(N'Stackish_UpdateUserProfile',2,N'@DisplayName',N'nvarchar',-1),
 (N'Stackish_UpdateUserProfile',3,N'@AboutMe',N'nvarchar',-1),(N'Stackish_UpdateUserProfile',4,N'@Location',N'nvarchar',-1),
 (N'Stackish_UpdateUserProfile',5,N'@WebsiteUrl',N'nvarchar',-1),(N'Stackish_UpdateUserProfile',6,N'@Age',N'int',4),
 (N'Stackish_RecordUserAccess',1,N'@UserId',N'int',4),
 (N'Stackish_RecordProfileView',1,N'@UserId',N'int',4),
 (N'Stackish_GetUserCard',1,N'@UserId',N'int',4),
 (N'Stackish_ListUsers',1,N'@NamePrefix',N'nvarchar',80),(N'Stackish_ListUsers',2,N'@Sort',N'varchar',20),
 (N'Stackish_ListUsers',3,N'@Offset',N'int',4),(N'Stackish_ListUsers',4,N'@PageSize',N'int',4);

IF (SELECT COUNT(*) FROM sys.procedures WHERE schema_id = SCHEMA_ID(N'dbo')
      AND name IN (SELECT DISTINCT Proc_ FROM @expected)) <> 6
    THROW 51100, 'One or more Users procedures are missing (or are not stored procedures).', 1;

DECLARE @actual TABLE (Proc_ sysname, Ord int, Name sysname, TypeName sysname, MaxLen smallint);
INSERT @actual
SELECT o.name, p.parameter_id, p.name, TYPE_NAME(p.user_type_id), p.max_length
  FROM sys.procedures o JOIN sys.parameters p ON p.object_id = o.object_id
 WHERE o.schema_id = SCHEMA_ID(N'dbo') AND o.name IN (SELECT DISTINCT Proc_ FROM @expected);
IF EXISTS (SELECT * FROM @expected EXCEPT SELECT * FROM @actual) OR EXISTS (SELECT * FROM @actual EXCEPT SELECT * FROM @expected)
    THROW 51101, 'Parameter count, order, name, type or length mismatch.', 1;
IF EXISTS (SELECT 1 FROM sys.parameters p JOIN sys.procedures o ON o.object_id = p.object_id
            WHERE o.name IN (SELECT DISTINCT Proc_ FROM @expected) AND o.schema_id = SCHEMA_ID(N'dbo') AND p.is_output = 1)
    THROW 51102, 'No Users procedure has OUTPUT parameters.', 1;

-- Defaults are not in sys.parameters. Compare the header text (keywords lower-cased, whitespace
-- removed); a header containing comments or other syntax fails closed.
DECLARE @headers TABLE (Proc_ sysname, Header nvarchar(1000));
INSERT @headers VALUES
 (N'Stackish_CreateUser',N'@displaynamenvarchar(max),@aboutmenvarchar(max)=null,@locationnvarchar(max)=null,@websiteurlnvarchar(max)=null,@ageint=null'),
 (N'Stackish_UpdateUserProfile',N'@useridint,@displaynamenvarchar(max),@aboutmenvarchar(max)=null,@locationnvarchar(max)=null,@websiteurlnvarchar(max)=null,@ageint=null'),
 (N'Stackish_RecordUserAccess',N'@useridint'),
 (N'Stackish_RecordProfileView',N'@useridint'),
 (N'Stackish_GetUserCard',N'@useridint'),
 (N'Stackish_ListUsers',N'@nameprefixnvarchar(40)=null,@sortvarchar(20)=''reputation'',@offsetint=0,@pagesizeint=30');
IF EXISTS (
    SELECT 1
      FROM @headers h
      JOIN sys.sql_modules m ON m.object_id = OBJECT_ID(N'dbo.' + h.Proc_)
     CROSS APPLY (SELECT LOWER(REPLACE(REPLACE(REPLACE(REPLACE(m.definition, CHAR(13), N' '), CHAR(10), N' '), CHAR(9), N' '), N' ', N'')) AS d) x
     CROSS APPLY (SELECT CHARINDEX(N'@', x.d) AS s, CHARINDEX(N'asbeginsetnocount', x.d) AS e) p
     WHERE p.s = 0 OR p.e <= p.s OR SUBSTRING(x.d, p.s, p.e - p.s) <> h.Header)
    THROW 51103, 'Parameter defaults or declaration text do not match the contract.', 1;

-- Result shapes, in order. Writes: Outcome/EntityId. Reads: UserCard.
DECLARE @shape TABLE (Proc_ sysname, Ord int, Name sysname, TypeName nvarchar(256));
INSERT @shape VALUES
 (N'Stackish_CreateUser',1,N'Outcome',N'varchar(20)'),(N'Stackish_CreateUser',2,N'EntityId',N'int'),
 (N'Stackish_UpdateUserProfile',1,N'Outcome',N'varchar(20)'),(N'Stackish_UpdateUserProfile',2,N'EntityId',N'int'),
 (N'Stackish_RecordUserAccess',1,N'Outcome',N'varchar(20)'),(N'Stackish_RecordUserAccess',2,N'EntityId',N'int'),
 (N'Stackish_RecordProfileView',1,N'Outcome',N'varchar(20)'),(N'Stackish_RecordProfileView',2,N'EntityId',N'int'),
 (N'Stackish_GetUserCard',1,N'UserId',N'int'),(N'Stackish_GetUserCard',2,N'DisplayName',N'nvarchar(40)'),
 (N'Stackish_GetUserCard',3,N'Reputation',N'int'),(N'Stackish_GetUserCard',4,N'Location',N'nvarchar(100)'),
 (N'Stackish_GetUserCard',5,N'CreationDate',N'datetime'),(N'Stackish_GetUserCard',6,N'LastAccessDate',N'datetime'),
 (N'Stackish_ListUsers',1,N'UserId',N'int'),(N'Stackish_ListUsers',2,N'DisplayName',N'nvarchar(40)'),
 (N'Stackish_ListUsers',3,N'Reputation',N'int'),(N'Stackish_ListUsers',4,N'Location',N'nvarchar(100)'),
 (N'Stackish_ListUsers',5,N'CreationDate',N'datetime'),(N'Stackish_ListUsers',6,N'LastAccessDate',N'datetime');

DECLARE @found TABLE (Proc_ sysname, Ord int, Name sysname, TypeName nvarchar(256), Err int);
INSERT @found
SELECT c.Proc_, r.column_ordinal, r.name, r.system_type_name, r.error_number
  FROM (SELECT DISTINCT Proc_ FROM @shape) c
 CROSS APPLY sys.dm_exec_describe_first_result_set_for_object(OBJECT_ID(N'dbo.' + c.Proc_), 0) r;
IF EXISTS (SELECT 1 FROM @found WHERE Err IS NOT NULL)
    THROW 51104, 'Result metadata could not be discovered statically.', 1;
IF EXISTS (SELECT * FROM @shape EXCEPT SELECT Proc_, Ord, Name, TypeName FROM @found)
   OR EXISTS (SELECT Proc_, Ord, Name, TypeName FROM @found EXCEPT SELECT * FROM @shape)
    THROW 51105, 'Result column count, order, name or type mismatch.', 1;

PRINT 'Users metadata assertions passed.';
