-- Run after deployment in the intended database. All calls in this file are read-only.
-- The leaderboard can scan many questions on the unmodified public schema.
SET NOCOUNT ON;
DECLARE @TagName nvarchar(150) = (SELECT TOP (1) TagName FROM dbo.Tags ORDER BY Id);
IF @TagName IS NULL THROW 50000, 'These examples require a populated Tags catalog.', 1;
DECLARE @MissingTag nvarchar(150) = N'stackish-missing-' + CONVERT(nvarchar(36), NEWID());
WHILE EXISTS (SELECT 1 FROM dbo.Tags WHERE TagName = @MissingTag)
    SET @MissingTag = N'stackish-missing-' + CONVERT(nvarchar(36), NEWID());

SELECT TagName FROM dbo.Stackish_SplitTags(N'<sql-server><c#><c++><日本語><sql-server>') ORDER BY TagName;
SELECT TagName FROM dbo.Stackish_SplitTags(NULL);

EXEC dbo.Stackish_ListTags @PageSize = 10;
EXEC dbo.Stackish_ListTags @NamePrefix = @TagName, @Sort = 'name', @Offset = 0, @PageSize = 10;
EXEC dbo.Stackish_ListTags @NamePrefix = @MissingTag;
EXEC dbo.Stackish_GetTagDetail @TagName = @TagName;
EXEC dbo.Stackish_GetTagDetail @TagName = @MissingTag;
EXEC dbo.Stackish_GetTagTopUsers @TagName = @TagName, @PageSize = 10;
EXEC dbo.Stackish_GetTagTopUsers @TagName = @MissingTag;
