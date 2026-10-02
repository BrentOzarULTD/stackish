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
;WITH P AS (SELECT *,ROW_NUMBER() OVER(ORDER BY Id) rn FROM @Posts WHERE PostTypeId=1),
U AS (SELECT Id,ROW_NUMBER() OVER(ORDER BY Id) rn FROM @Users)
SELECT TOP(512) P.Id AS QuestionId,U.Id AS UserId FROM P JOIN U ON U.rn=1+(P.rn-1) % NULLIF((SELECT COUNT(*) FROM @Users),0)
 ORDER BY P.Id;
