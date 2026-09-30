SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetBadgeRecipients
    @BadgeName nvarchar(40),
    @Offset int = 0,
    @PageSize int = 30
AS
BEGIN
    SET NOCOUNT ON;

    IF @BadgeName IS NULL OR TRIM(@BadgeName) = N'' THROW 50955, 'BadgeName is required and cannot be blank.', 1;
    IF @Offset IS NULL OR @Offset < 0 THROW 50956, 'Offset must be zero or greater.', 1;
    IF @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100 THROW 50957, 'PageSize must be between 1 and 100.', 1;

    -- One row per award (a user with repeated awards appears repeatedly). Recipients
    -- missing from Users keep their award with a NULL DisplayName.
    SELECT b.Id AS BadgeId,
           NULLIF(b.UserId, 0) AS UserId,
           u.DisplayName,
           b.Date AS AwardedDate
    FROM dbo.Badges b
    LEFT JOIN dbo.Users u ON u.Id = b.UserId AND b.UserId <> 0
    WHERE b.Name = @BadgeName
    ORDER BY b.Date DESC, b.Id DESC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
