SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetTagTopUsers
    @TagName nvarchar(150),
    @Offset int = 0,
    @PageSize int = 30
AS
BEGIN
    SET NOCOUNT ON;
    IF @TagName IS NULL OR LEN(REPLACE(REPLACE(REPLACE(@TagName, NCHAR(9), N''), NCHAR(10), N''), NCHAR(13), N'')) = 0
        THROW 50003, 'TagName must not be blank.', 1;
    IF @Offset IS NULL OR @Offset < 0 OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100
        THROW 50001, 'Offset must be nonnegative and PageSize must be between 1 and 100.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Tags WHERE TagName = @TagName)
    BEGIN
        SELECT CAST(NULL AS int) AS UserId, CAST(NULL AS nvarchar(40)) AS DisplayName,
               CAST(NULL AS bigint) AS AnswerCount, CAST(NULL AS bigint) AS TotalScore
        WHERE 1 = 0;
        RETURN;
    END;

    -- Canonical spelling also avoids a trailing-space equality/substring mismatch.
    -- Imported duplicate catalog names must not multiply a question's answers.
    DECLARE @catalogName nvarchar(150);
    SELECT TOP (1) @catalogName = TagName FROM dbo.Tags WHERE TagName = @TagName ORDER BY Id;

    CREATE TABLE #TagQuestions (Id int NOT NULL PRIMARY KEY);
    INSERT #TagQuestions (Id)
        SELECT p.Id
        FROM dbo.Posts AS p
        WHERE p.PostTypeId = 1
          AND (CHARINDEX(N'<' + @catalogName + N'>', p.Tags) > 0
               OR (LEFT(p.Tags,1)=N'|' AND RIGHT(p.Tags,1)=N'|' AND CHARINDEX(N'|',@catalogName)=0 AND CHARINDEX(N'|' + @catalogName + N'|',p.Tags)>0));

    -- Materialize the matching questions before aggregating their answers.
    -- Delimiters give exact membership without expanding every tag on every post.
    SELECT u.Id AS UserId, u.DisplayName,
           COUNT_BIG(*) AS AnswerCount,
           SUM(CONVERT(bigint, a.Score)) AS TotalScore
    FROM #TagQuestions AS q
    JOIN dbo.Posts AS a ON a.ParentId = q.Id AND a.PostTypeId = 2
    JOIN dbo.Users AS u ON u.Id = a.OwnerUserId AND u.Id > 0
    GROUP BY u.Id, u.DisplayName
    ORDER BY TotalScore DESC, AnswerCount DESC, u.Id ASC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
