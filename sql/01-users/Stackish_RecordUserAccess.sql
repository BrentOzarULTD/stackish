SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_RecordUserAccess
    @UserId int
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserId IS NULL
        THROW 50111, 'UserId is required.', 1;

    DECLARE @updated int = 0;
    IF @UserId > 0
    BEGIN
        UPDATE dbo.Users
           SET LastAccessDate = GETUTCDATE()
         WHERE Id = @UserId;
        SET @updated = @@ROWCOUNT;
    END;

    SELECT CAST(CASE WHEN @updated = 1 THEN 'Applied' ELSE 'NotFound' END AS varchar(20)) AS Outcome,
           @UserId AS EntityId;
END;
GO
