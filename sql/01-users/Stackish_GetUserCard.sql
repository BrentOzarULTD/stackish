SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetUserCard
    @UserId int
AS
BEGIN
    SET NOCOUNT ON;

    -- No range check: imported Community/special users (Id <= 0) are valid read targets.
    -- A missing or NULL id gives an empty, correctly typed result.
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation, u.Location, u.CreationDate, u.LastAccessDate
      FROM dbo.Users AS u
     WHERE u.Id = @UserId;
END;
GO
