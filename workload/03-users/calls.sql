-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Choice int=ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 100;

IF @Choice<55 EXEC dbo.Stackish_GetUserCard @UserId=@InputUserId;
ELSE IF @Choice<85 EXEC dbo.Stackish_GetUserPosts @UserId=@InputUserId,@PageSize=20;
ELSE IF @Choice<95 EXEC dbo.Stackish_GetUserProfile @UserId=@InputUserId,@TopCount=5;
ELSE EXEC dbo.Stackish_ListUsers @Sort='reputation',@PageSize=20;
