-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Choice int=ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 100;

IF @Choice<35 EXEC dbo.Stackish_GetQuestionsByTag @TagName=@InputTagName,@PageSize=20;
ELSE IF @Choice<55 EXEC dbo.Stackish_SearchQuestions @Text=@InputSearchText,@FromDate=@InputFromDate,@ToDate=@InputToDate,@SearchBody=1,@PageSize=20;
ELSE IF @Choice<70 EXEC dbo.Stackish_GetUnansweredQuestions @TagName=@InputTagName,@Mode='no_solution',@PageSize=20;
ELSE IF @Choice<80 EXEC dbo.Stackish_GetRelatedQuestions @QuestionId=@InputQuestionId,@PageSize=10;
ELSE IF @Choice<90 EXEC dbo.Stackish_GetTagTopUsers @TagName=@InputTagName,@PageSize=10;
ELSE IF @Choice<95 EXEC dbo.Stackish_ListBadges @PageSize=20;
ELSE EXEC dbo.Stackish_GetBadgeRecipients @BadgeName=@InputBadgeName,@PageSize=20;
