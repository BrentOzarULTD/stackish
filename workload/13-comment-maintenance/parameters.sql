-- Optional substitution within edits (7%) / maintenance (3%), never extra baseline weight.
SET NOCOUNT ON;
DECLARE @Start int=1+ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % NULLIF((SELECT MAX(Id) FROM dbo.Comments),0);
DECLARE @Comments table(Id int PRIMARY KEY,UserId int,PostId int);
INSERT @Comments SELECT TOP(4096) Id,UserId,PostId FROM dbo.Comments WHERE Id>=@Start ORDER BY Id;
DECLARE @Remaining int=4096-(SELECT COUNT(*) FROM @Comments);
IF @Remaining>0 INSERT @Comments SELECT TOP(@Remaining) Id,UserId,PostId FROM dbo.Comments WHERE Id>0 AND Id<@Start ORDER BY Id;
SELECT TOP(512) C.Id AS CommentId,C.UserId FROM @Comments C JOIN dbo.Users U ON U.Id=C.UserId AND U.Id>0
JOIN dbo.Posts P ON P.Id=C.PostId AND P.PostTypeId IN(1,2) ORDER BY C.Id;
