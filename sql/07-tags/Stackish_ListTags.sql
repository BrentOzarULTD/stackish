SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_ListTags
    @NamePrefix nvarchar(150) = NULL,
    @Sort varchar(20) = 'popular',
    @Offset int = 0,
    @PageSize int = 30
AS
BEGIN
    SET NOCOUNT ON;

    IF @Offset IS NULL OR @Offset < 0 OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100
        THROW 50001, 'Offset must be nonnegative and PageSize must be between 1 and 100.', 1;
    IF @Sort IS NULL OR @Sort NOT IN ('popular', 'name', 'newest')
        THROW 50002, 'Tag sort must be popular, name, or newest.', 1;

    -- Escape the escape character first. Prefixes are literal, including %, _ and [.
    DECLARE @pattern nvarchar(301) =
        REPLACE(REPLACE(REPLACE(REPLACE(@NamePrefix, N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[') + N'%';

    ;WITH TagPage AS
    (
        SELECT t.Id, t.TagName, t.[Count], t.ExcerptPostId
        FROM dbo.Tags AS t
        WHERE @NamePrefix IS NULL OR t.TagName LIKE @pattern ESCAPE N'~'
        ORDER BY
            CASE WHEN @Sort = 'popular' THEN t.[Count] END DESC,
            CASE WHEN @Sort = 'name' THEN t.TagName END ASC,
            CASE WHEN @Sort = 'newest' THEN t.Id END DESC,
            t.Id ASC
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY
    )
    SELECT t.Id AS TagId, t.TagName, t.[Count] AS QuestionCount, excerpt.Body AS Excerpt
    FROM TagPage AS t
    LEFT JOIN dbo.Posts AS excerpt
      ON excerpt.Id = t.ExcerptPostId AND t.ExcerptPostId > 0 AND excerpt.PostTypeId = 4
    ORDER BY
        CASE WHEN @Sort = 'popular' THEN t.[Count] END DESC,
        CASE WHEN @Sort = 'name' THEN t.TagName END ASC,
        CASE WHEN @Sort = 'newest' THEN t.Id END DESC,
        t.Id ASC;
END;
GO
