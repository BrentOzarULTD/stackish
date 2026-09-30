SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_ListBadges
    @NamePrefix nvarchar(40) = NULL,
    @Offset int = 0,
    @PageSize int = 30
AS
BEGIN
    SET NOCOUNT ON;

    IF @Offset IS NULL OR @Offset < 0 THROW 50953, 'Offset must be zero or greater.', 1;
    IF @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100 THROW 50954, 'PageSize must be between 1 and 100.', 1;

    -- The prefix is literal text: escape LIKE metacharacters. An empty prefix matches everything.
    DECLARE @pattern nvarchar(200) =
        REPLACE(REPLACE(REPLACE(REPLACE(@NamePrefix, N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'[', N'\[') + N'%';

    -- Badge names come only from award rows; there is no badge catalog or class metadata.
    -- Awards to user IDs that no longer exist in Users still count. UserId 0 means no user, so
    -- those awards count as awards but not as a recipient.
    SELECT b.Name,
           COUNT_BIG(*) AS AwardCount,
           COUNT_BIG(DISTINCT b.UserId) - MAX(IIF(b.UserId = 0, 1, 0)) AS RecipientCount,
           MIN(b.Date) AS FirstAwarded
    FROM dbo.Badges b
    WHERE @NamePrefix IS NULL
       OR b.Name LIKE @pattern ESCAPE N'\'
    GROUP BY b.Name
    ORDER BY AwardCount DESC, b.Name ASC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END;
GO
