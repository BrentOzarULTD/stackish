-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Choice int=ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 100;

IF @Choice<70 EXEC dbo.Stackish_GetQuestionPage @QuestionId=@InputQuestionId,@AnswerPageSize=10,@CommentLimit=5;
ELSE IF @Choice<90 EXEC dbo.Stackish_GetPostComments @PostId=@InputQuestionId,@PageSize=30;
ELSE EXEC dbo.Stackish_GetPostVoteSummary @PostId=@InputQuestionId;
