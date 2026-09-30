SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_RemoveQuestionLink
    @LinkId int,
    @UserId int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @outcome varchar(20), @found bit = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @found = 1
        FROM dbo.PostLinks WITH (UPDLOCK)
        WHERE Id = @LinkId;

        IF @found = 0
            SET @outcome = 'NotFound';
        ELSE IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId AND Id > 0)
            SET @outcome = 'Conflict';
        ELSE
        BEGIN
            -- Exactly this LinkId; closure and history are untouched.
            DELETE dbo.PostLinks WHERE Id = @LinkId;
            SET @outcome = 'Applied';
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @outcome AS Outcome, @LinkId AS EntityId;
END;
GO
