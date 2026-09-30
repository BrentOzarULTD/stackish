-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Choice int=ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 100;

-- Only attributed up/down votes belong to this actor. Anonymous/zero votes stay untouched.
IF EXISTS(SELECT 1 FROM dbo.Votes WHERE PostId=@InputPostId AND UserId=@InputUserId AND VoteTypeId IN(2,3))
 EXEC dbo.Stackish_RemovePostVote @PostId=@InputPostId,@UserId=@InputUserId;
ELSE IF @InputPostTypeId=1 AND @Choice<80 EXEC dbo.Stackish_UpvoteQuestion @QuestionId=@InputPostId,@UserId=@InputUserId;
ELSE IF @InputPostTypeId=1 EXEC dbo.Stackish_DownvoteQuestion @QuestionId=@InputPostId,@UserId=@InputUserId;
ELSE IF @Choice<80 EXEC dbo.Stackish_UpvoteAnswer @AnswerId=@InputPostId,@UserId=@InputUserId;
ELSE EXEC dbo.Stackish_DownvoteAnswer @AnswerId=@InputPostId,@UserId=@InputUserId;
