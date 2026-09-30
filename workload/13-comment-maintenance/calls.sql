-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Choice int=ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 100;

DECLARE @Text nvarchar(max)=CONCAT(N'Stackish comment edit ',CONVERT(nvarchar(36),NEWID()));
IF @Choice<90 EXEC dbo.Stackish_EditComment @CommentId=@InputCommentId,@UserId=@InputUserId,@Text=@Text;
ELSE EXEC dbo.Stackish_DeleteComment @CommentId=@InputCommentId,@UserId=@InputUserId;
