SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetTagDetail
    @TagName nvarchar(150)
AS
BEGIN
    SET NOCOUNT ON;
    IF @TagName IS NULL OR LEN(REPLACE(REPLACE(REPLACE(@TagName, NCHAR(9), N''), NCHAR(10), N''), NCHAR(13), N'')) = 0
        THROW 50003, 'TagName must not be blank.', 1;

    SELECT t.Id AS TagId, t.TagName, t.[Count] AS QuestionCount,
           excerpt.Body AS Excerpt, wiki.Body AS WikiBody
    FROM dbo.Tags AS t
    LEFT JOIN dbo.Posts AS excerpt
      ON excerpt.Id = t.ExcerptPostId AND t.ExcerptPostId > 0 AND excerpt.PostTypeId = 4
    LEFT JOIN dbo.Posts AS wiki
      ON wiki.Id = t.WikiPostId AND t.WikiPostId > 0 AND wiki.PostTypeId = 5
    WHERE t.TagName = @TagName
    ORDER BY t.Id;
END;
GO
