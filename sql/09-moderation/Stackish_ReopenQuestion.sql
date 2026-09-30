SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_ReopenQuestion
    @QuestionId int,
    @UserId int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @now datetime, @outcome varchar(20), @type int, @closedDate datetime;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @type = PostTypeId, @closedDate = ClosedDate
        FROM dbo.Posts WITH (UPDLOCK)
        WHERE Id = @QuestionId;

        -- Take the time only once the row lock is held, so a call that waited behind another
        -- writer never stamps an older ClosedDate/LastActivityDate than that writer's.
        SET @now = GETUTCDATE();

        IF @type IS NULL
            SET @outcome = 'NotFound';
        ELSE IF @type <> 1
             OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId AND Id > 0)
            SET @outcome = 'Conflict';
        ELSE IF @closedDate IS NULL
            SET @outcome = 'NoChange';
        ELSE
        BEGIN
            -- Links (including duplicate links) are deliberately left alone.
            UPDATE dbo.Posts
            SET ClosedDate = NULL,
                LastActivityDate = @now
            WHERE Id = @QuestionId;

            INSERT dbo.PostHistory (PostHistoryTypeId, PostId, RevisionGUID, CreationDate, UserId, UserDisplayName, Comment, Text)
            VALUES (11, @QuestionId, NEWID(), @now, @UserId, NULL, NULL, NULL);

            SET @outcome = 'Applied';
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @outcome AS Outcome, @QuestionId AS EntityId;
END;
GO
