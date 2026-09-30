-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Choice int=ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 100;

IF @Choice<45 EXEC dbo.Stackish_GetTagDetail @TagName=@InputTagName;
ELSE IF @Choice<75 EXEC dbo.Stackish_ListTags @NamePrefix=@InputTagName,@PageSize=20;
ELSE IF @Choice<95 EXEC dbo.Stackish_GetUserBadges @UserId=@InputUserId,@PageSize=20;
ELSE EXEC dbo.Stackish_GetPostHistory @PostId=@InputPostId,@PageSize=20;
