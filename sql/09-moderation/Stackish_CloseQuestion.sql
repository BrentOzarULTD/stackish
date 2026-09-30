SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_CloseQuestion
    @QuestionId int,
    @UserId int,
    @Reason nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Reason IS NULL OR TRIM(NCHAR(32) + NCHAR(9) + NCHAR(10) + NCHAR(13) FROM @Reason) = N''
        THROW 50901, 'Close reason is required and cannot be blank.', 1;

    SET XACT_ABORT ON;
    DECLARE @now datetime, @outcome varchar(20), @type int, @closedDate datetime;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- CreateAnswer reads ClosedDate under UPDLOCK on this same row, so closing and
        -- answering serialize: an answer either commits before the close or sees it.
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
        ELSE IF @closedDate IS NOT NULL
            SET @outcome = 'NoChange';
        ELSE
        BEGIN
            UPDATE dbo.Posts
            SET ClosedDate = @now,
                LastActivityDate = @now
            WHERE Id = @QuestionId;

            INSERT dbo.PostHistory (PostHistoryTypeId, PostId, RevisionGUID, CreationDate, UserId, UserDisplayName, Comment, Text)
            VALUES (10, @QuestionId, NEWID(), @now, @UserId, NULL, @Reason, NULL);

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
