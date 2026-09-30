-- Run as SQLQueryStress's parameter query, in the same database as calls.sql.
-- Table variables keep eligibility selection bounded and support SchemaOnly/Get Columns.
-- Cached until the next run. Gap/window biased, not statistically uniform.
SET NOCOUNT ON;
DECLARE @Start int = 1 + ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % NULLIF((SELECT MAX(Id) FROM dbo.Posts),0);
DECLARE @Posts table(Id int PRIMARY KEY,PostTypeId int,OwnerUserId int,ParentId int,ClosedDate datetime,AcceptedAnswerId int,Tags nvarchar(150),CreationDate datetime,Title nvarchar(250));
INSERT @Posts SELECT TOP(4096) Id,PostTypeId,OwnerUserId,ParentId,ClosedDate,AcceptedAnswerId,Tags,CreationDate,Title
FROM dbo.Posts WHERE Id>=@Start ORDER BY Id;
DECLARE @Remaining int=4096-(SELECT COUNT(*) FROM @Posts);
IF @Remaining>0
 INSERT @Posts SELECT TOP(@Remaining) Id,PostTypeId,OwnerUserId,ParentId,ClosedDate,AcceptedAnswerId,Tags,CreationDate,Title
 FROM dbo.Posts WHERE Id>0 AND Id<@Start ORDER BY Id;
DECLARE @UserStart int = 1 + ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % NULLIF((SELECT MAX(Id) FROM dbo.Users),0);
DECLARE @Users table(Id int PRIMARY KEY);
INSERT @Users SELECT TOP(512) Id FROM dbo.Users WHERE Id>=@UserStart AND Id>0 ORDER BY Id;
SET @Remaining=512-(SELECT COUNT(*) FROM @Users);
IF @Remaining>0 INSERT @Users SELECT TOP(@Remaining) Id FROM dbo.Users WHERE Id>0 AND Id<@UserStart ORDER BY Id;
DECLARE @Tag1 nvarchar(150),@Tag2 nvarchar(150);
;WITH T AS (SELECT TOP(2) TagName,ROW_NUMBER() OVER(ORDER BY Id) rn FROM dbo.Tags t
 WHERE LEN(TagName) BETWEEN 1 AND 60 AND CHARINDEX('<',TagName)=0 AND CHARINDEX('>',TagName)=0
 AND (SELECT COUNT(*) FROM dbo.Tags x WHERE x.TagName=t.TagName)=1 ORDER BY Id)
SELECT @Tag1=MAX(CASE WHEN rn=1 THEN TagName END),@Tag2=MAX(CASE WHEN rn=2 THEN TagName END) FROM T;
IF @Tag2 IS NULL THROW 51101,'Need two distinct existing tags of at most 60 characters.',1;
;WITH P AS (SELECT *,ROW_NUMBER() OVER(ORDER BY Id) rn FROM @Posts WHERE PostTypeId=1 AND ClosedDate IS NULL),
U AS (SELECT Id,ROW_NUMBER() OVER(ORDER BY Id) rn FROM @Users)
SELECT TOP(512) P.Id AS QuestionId,U.Id AS UserId,@Tag1 AS TagName FROM P JOIN U ON U.rn=1+(P.rn-1) % NULLIF((SELECT COUNT(*) FROM @Users),0)
 ORDER BY P.Id;
