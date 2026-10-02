-- Initial-deployment access paths, explicitly authorized for the desktop/release wave.
-- Creates only missing nonunique indexes. Never drops/rebuilds existing indexes or edits data.
-- A suitable enabled, unfiltered rowstore index under ANY name is reused when its
-- leading keys/directions satisfy the specification. INCLUDE columns improve coverage
-- on newly created indexes; an existing seek path can use base-row lookups. Full reversal
-- of all key directions is equivalent (backward scan). Extra trailing keys are allowed.
SET NOCOUNT ON;
DECLARE @Indexes table(TableName sysname, IndexName sysname, KeysJson nvarchar(max), IncludesJson nvarchar(max));
INSERT @Indexes VALUES
(N'Votes',N'IX_Stackish_Votes_PostId_UserId',N'[{"column":"PostId","descending":0},{"column":"UserId","descending":0}]',N'["VoteTypeId"]'),
(N'Posts',N'IX_Stackish_Posts_ParentId_PostTypeId',N'[{"column":"ParentId","descending":0},{"column":"PostTypeId","descending":0}]',N'["Score","OwnerUserId"]'),
(N'Posts',N'IX_Stackish_Posts_OwnerUserId_PostTypeId',N'[{"column":"OwnerUserId","descending":0},{"column":"PostTypeId","descending":0}]',N'["Score","ParentId","Tags","CreationDate","LastActivityDate"]'),
(N'Comments',N'IX_Stackish_Comments_PostId_CreationDate',N'[{"column":"PostId","descending":0},{"column":"CreationDate","descending":0},{"column":"Id","descending":0}]',N'["UserId","Score"]'),
(N'Comments',N'IX_Stackish_Comments_UserId',N'[{"column":"UserId","descending":0}]',N'[]'),
(N'Badges',N'IX_Stackish_Badges_UserId_Name',N'[{"column":"UserId","descending":0},{"column":"Name","descending":0}]',N'["Date"]'),
(N'Badges',N'IX_Stackish_Badges_Name_Date',N'[{"column":"Name","descending":0},{"column":"Date","descending":1},{"column":"Id","descending":1}]',N'["UserId"]'),
(N'PostLinks',N'IX_Stackish_PostLinks_PostId_RelatedPostId',N'[{"column":"PostId","descending":0},{"column":"RelatedPostId","descending":0},{"column":"LinkTypeId","descending":0}]',N'["CreationDate"]'),
(N'PostHistory',N'IX_Stackish_PostHistory_PostId_CreationDate',N'[{"column":"PostId","descending":0},{"column":"CreationDate","descending":1},{"column":"Id","descending":1}]',N'[]'),
(N'Tags',N'IX_Stackish_Tags_TagName',N'[{"column":"TagName","descending":0}]',N'["Count","ExcerptPostId","WikiPostId"]'),
(N'Posts',N'IX_Stackish_Posts_PostTypeId_CreationDate',N'[{"column":"PostTypeId","descending":0},{"column":"CreationDate","descending":1},{"column":"Id","descending":1}]',N'["Tags","Score","OwnerUserId","ClosedDate","AcceptedAnswerId"]'),
(N'Posts',N'IX_Stackish_Posts_PostTypeId_LastActivityDate',N'[{"column":"PostTypeId","descending":0},{"column":"LastActivityDate","descending":1},{"column":"Id","descending":1}]',N'[]'),
(N'Users',N'IX_Stackish_Users_Reputation',N'[{"column":"Reputation","descending":1},{"column":"Id","descending":0}]',N'["DisplayName"]');
DECLARE @Table sysname,@Name sysname,@Keys nvarchar(max),@Includes nvarchar(max),@Object int,@Existing sysname,@Sql nvarchar(max),@KeySql nvarchar(max),@IncludeSql nvarchar(max);
DECLARE indexes_to_check CURSOR LOCAL FAST_FORWARD FOR SELECT TableName,IndexName,KeysJson,IncludesJson FROM @Indexes;
OPEN indexes_to_check;
FETCH NEXT FROM indexes_to_check INTO @Table,@Name,@Keys,@Includes;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @Object=OBJECT_ID(N'dbo.'+QUOTENAME(@Table));
 SET @Existing=NULL;
 SELECT TOP(1) @Existing=i.name FROM sys.indexes i
 WHERE i.object_id=@Object AND i.type IN (1,2) AND i.is_disabled=0 AND i.is_hypothetical=0 AND i.has_filter=0
 AND EXISTS (
  SELECT 1 FROM (VALUES(0),(1)) direction(ReverseKeys)
  WHERE NOT EXISTS (
   SELECT 1 FROM OPENJSON(@Keys) k
   WHERE NOT EXISTS (
    SELECT 1 FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
    WHERE ic.object_id=i.object_id AND ic.index_id=i.index_id AND ic.key_ordinal=CONVERT(int,k.[key])+1
     AND c.name=JSON_VALUE(k.value,'$.column') COLLATE database_default
     AND ic.is_descending_key=CONVERT(int,JSON_VALUE(k.value,'$.descending')) ^ direction.ReverseKeys)))

 ORDER BY i.index_id;
 IF @Existing IS NOT NULL
  SELECT @Table AS TableName,@Existing AS IndexName,CONVERT(varchar(20),'Reused') AS DeploymentAction;
 ELSE
 BEGIN
  IF EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=@Object AND name=@Name)
  BEGIN
   DECLARE @Conflict nvarchar(2048)=N'Index dbo.'+QUOTENAME(@Table)+N'.'+QUOTENAME(@Name)+N' exists with an incompatible definition. Deployment will not replace it.';
   THROW 51006,@Conflict,1;
  END;
  SELECT @KeySql=STRING_AGG(CONVERT(nvarchar(max),QUOTENAME(JSON_VALUE(value,'$.column'))+CASE JSON_VALUE(value,'$.descending') WHEN '1' THEN N' DESC' ELSE N' ASC' END),N',') WITHIN GROUP(ORDER BY CONVERT(int,[key])) FROM OPENJSON(@Keys);
  SELECT @IncludeSql=STRING_AGG(CONVERT(nvarchar(max),QUOTENAME(value)),N',') FROM OPENJSON(@Includes);
  SET @Sql=N'CREATE NONCLUSTERED INDEX '+QUOTENAME(@Name)+N' ON dbo.'+QUOTENAME(@Table)+N' ('+@KeySql+N')'+CASE WHEN @IncludeSql IS NULL THEN N'' ELSE N' INCLUDE ('+@IncludeSql+N')' END+N';';
  -- No ONLINE, compression, filegroup, recovery, or other database setting assumptions.
  EXEC sys.sp_executesql @Sql;
  SELECT @Table AS TableName,@Name AS IndexName,CONVERT(varchar(20),'Created') AS DeploymentAction;
 END;
 FETCH NEXT FROM indexes_to_check INTO @Table,@Name,@Keys,@Includes;
END;
CLOSE indexes_to_check;
DEALLOCATE indexes_to_check;
GO
