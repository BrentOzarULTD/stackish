/* Read-only smoke/contract checks. Run on a disposable StackOverflow restore. */
SET NOCOUNT ON;
DECLARE @Q int=(SELECT TOP(1) Id FROM dbo.Posts WHERE PostTypeId=1 ORDER BY Id), @Tag nvarchar(150)=(SELECT TOP(1) TagName FROM dbo.Tags ORDER BY Id);
IF @Q IS NULL OR @Tag IS NULL THROW 50690,'Fixture source rows are unavailable.',1;
EXEC dbo.Stackish_ListQuestions @Sort='newest',@Offset=0,@PageSize=2;
EXEC dbo.Stackish_ListQuestions @Sort='active',@Offset=0,@PageSize=2;
EXEC dbo.Stackish_ListQuestions @Sort='score',@Offset=0,@PageSize=2;
EXEC dbo.Stackish_ListQuestions @Sort='views',@Offset=0,@PageSize=2;
EXEC dbo.Stackish_SearchQuestions @Text=N'%',@SearchBody=1,@PageSize=2;
EXEC dbo.Stackish_SearchQuestions @TagName=@Tag,@HasAccepted=0,@FromDate='2008-01-01',@ToDate='2027-01-01',@PageSize=2;
EXEC dbo.Stackish_GetQuestionsByTag @TagName=@Tag,@Sort='active',@PageSize=2;
EXEC dbo.Stackish_GetQuestionsByTag @TagName=N'__stackish_missing__';
EXEC dbo.Stackish_GetUnansweredQuestions @Mode='no_answers',@PageSize=2;
EXEC dbo.Stackish_GetUnansweredQuestions @Mode='no_solution',@PageSize=2;
EXEC dbo.Stackish_GetRelatedQuestions @QuestionId=@Q,@PageSize=2;
EXEC dbo.Stackish_GetRelatedQuestions @QuestionId=2147483647;
-- The caller should compare pre/post snapshots of Posts and Users around this script: all procedures are reads.
