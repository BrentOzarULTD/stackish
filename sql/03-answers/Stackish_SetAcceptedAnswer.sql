SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_SetAcceptedAnswer
    @QuestionId int,
    @UserId int,
    @AnswerId int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @AnswerId = 0 THROW 50341, 'AnswerId zero is not valid; pass NULL to clear acceptance.', 1;

    SET XACT_ABORT ON;
    DECLARE @ownerUserId int, @current int, @found bit = 0, @now datetime = GETUTCDATE(), @lockResult int;
    DECLARE @lockResource nvarchar(255) = CONCAT(N'Stackish_SetAcceptedAnswer:', @QuestionId);
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC @lockResult = sys.sp_getapplock @Resource = @lockResource,
            @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @lockResult < 0 THROW 50342, 'Could not acquire acceptance lock.', 1;

        SELECT @ownerUserId = OwnerUserId, @current = NULLIF(AcceptedAnswerId, 0), @found = 1
        FROM dbo.Posts WITH (UPDLOCK, HOLDLOCK)
        WHERE Id = @QuestionId AND PostTypeId = 1;

        IF @found = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @QuestionId)
                SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
            ELSE
                SELECT CAST('NotFound' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
            COMMIT TRANSACTION;
            RETURN;
        END;

        IF @ownerUserId IS NULL OR @ownerUserId <= 0 OR @ownerUserId <> @UserId OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId AND Id > 0)
        BEGIN
            COMMIT TRANSACTION;
            SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
            RETURN;
        END;

        IF @AnswerId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Posts WITH (UPDLOCK, HOLDLOCK) WHERE Id = @AnswerId AND PostTypeId = 2 AND ParentId = @QuestionId)
        BEGIN
            COMMIT TRANSACTION;
            SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
            RETURN;
        END;

        IF ISNULL(@current, -2147483648) = ISNULL(@AnswerId, -2147483648)
        BEGIN
            COMMIT TRANSACTION;
            SELECT CAST('NoChange' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
            RETURN;
        END;

        UPDATE dbo.Posts
        SET AcceptedAnswerId = @AnswerId,
            LastActivityDate = @now
        WHERE Id = @QuestionId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT CAST('Applied' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
END;
GO
