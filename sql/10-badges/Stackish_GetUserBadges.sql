SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetUserBadges
    @UserId int,
    @Offset int = 0,
    @PageSize int = 30
AS
BEGIN
    SET NOCOUNT ON;

    IF @Offset IS NULL OR @Offset < 0 THROW 50951, 'Offset must be zero or greater.', 1;
    IF @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100 THROW 50952, 'PageSize must be between 1 and 100.', 1;

    -- Every award row is returned, so a repeatable badge shows up once per award.
    SELECT b.Id AS BadgeId,
           b.Name,
           b.Date AS AwardedDate
    FROM dbo.Badges b
    WHERE b.UserId = @UserId
      AND EXISTS (SELECT 1 FROM dbo.Users u WHERE u.Id = @UserId)
    ORDER BY b.Date DESC, b.Id DESC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
