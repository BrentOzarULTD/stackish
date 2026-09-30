DECLARE @QuestionId int=(SELECT TOP(1) Id FROM dbo.Posts WHERE PostTypeId=1 ORDER BY Id);
DECLARE @UserId int=(SELECT TOP(1) Id FROM dbo.Users WHERE Id>0 ORDER BY Id);
EXEC dbo.Stackish_GetQuestionPage @QuestionId=@QuestionId;
EXEC dbo.Stackish_GetUserProfile @UserId=@UserId;
EXEC dbo.Stackish_GetUserPosts @UserId=@UserId;
EXEC dbo.Stackish_GetPostHistory @PostId=@QuestionId;
EXEC dbo.Stackish_GetQuestionPage @QuestionId=2147483647;
EXEC dbo.Stackish_GetUserProfile @UserId=2147483647;
