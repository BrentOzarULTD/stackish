/* Multi-result-set smoke checks. Each EXEC must be consumed as five/one result sets by the harness. */
SET NOCOUNT ON;
DECLARE @Q int=(SELECT TOP(1) Id FROM dbo.Posts WHERE PostTypeId=1 ORDER BY Id), @U int=(SELECT TOP(1) Id FROM dbo.Users WHERE Id>0 ORDER BY Id);
IF @Q IS NULL OR @U IS NULL THROW 50890,'Fixture source rows are unavailable.',1;
EXEC dbo.Stackish_GetQuestionPage @QuestionId=@Q,@AnswerPageSize=2,@CommentLimit=1;
EXEC dbo.Stackish_GetQuestionPage @QuestionId=2147483647;
EXEC dbo.Stackish_GetUserProfile @UserId=@U,@TopCount=2;
EXEC dbo.Stackish_GetUserProfile @UserId=2147483647;
EXEC dbo.Stackish_GetUserPosts @UserId=@U,@Sort='score',@Offset=0,@PageSize=2;
EXEC dbo.Stackish_GetPostHistory @PostId=@Q,@PageSize=2;
EXEC dbo.Stackish_GetPostHistory @PostId=2147483647;
-- Verify all result sets with a client supporting multiple results; do not infer page coverage from the first set.
