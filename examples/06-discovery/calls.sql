DECLARE @QuestionId int=(SELECT TOP(1) Id FROM dbo.Posts WHERE PostTypeId=1 ORDER BY Id);
DECLARE @Tag nvarchar(150)=(SELECT TOP(1) TagName FROM dbo.Tags ORDER BY Id);
EXEC dbo.Stackish_ListQuestions;
EXEC dbo.Stackish_SearchQuestions @Text=N'%',@SearchBody=1;
EXEC dbo.Stackish_GetQuestionsByTag @TagName=@Tag;
EXEC dbo.Stackish_GetUnansweredQuestions @Mode='no_answers';
EXEC dbo.Stackish_GetRelatedQuestions @QuestionId=@QuestionId;
EXEC dbo.Stackish_GetQuestionsByTag @TagName=N'__missing_stackish_tag__';
