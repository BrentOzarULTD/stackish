SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_CreateAnswer
    @QuestionId int,
    @UserId int,
    @Body nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @blank nvarchar(4) = NCHAR(32) + NCHAR(9) + NCHAR(10) + NCHAR(13);
    IF @Body IS NULL OR TRIM(@blank FROM @Body) = N'' THROW 50301, 'Body is required and cannot be blank.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId AND Id > 0)
    BEGIN
        SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
        RETURN;
    END;

    SET XACT_ABORT ON;
    DECLARE @now datetime = GETUTCDATE(), @answerId int, @closed datetime, @found bit = 0, @rev uniqueidentifier = NEWID();
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @closed = ClosedDate, @found = 1
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
        IF @closed IS NOT NULL
        BEGIN
            COMMIT TRANSACTION;
            SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
            RETURN;
        END;

        INSERT dbo.Posts (AcceptedAnswerId, AnswerCount, Body, ClosedDate, CommentCount, CommunityOwnedDate,
                          CreationDate, FavoriteCount, LastActivityDate, LastEditDate, LastEditorDisplayName,
                          LastEditorUserId, OwnerUserId, ParentId, PostTypeId, Score, Tags, Title, ViewCount)
        VALUES (NULL, NULL, @Body, NULL, 0, NULL,
                @now, NULL, @now, NULL, NULL,
                NULL, @UserId, @QuestionId, 2, 0, NULL, NULL, 0);
        SET @answerId = CONVERT(int, SCOPE_IDENTITY());

        INSERT dbo.PostHistory (PostHistoryTypeId, PostId, RevisionGUID, CreationDate, UserId, UserDisplayName, Comment, Text)
        VALUES (2, @answerId, @rev, @now, @UserId, NULL, NULL, @Body);

        UPDATE dbo.Posts
        SET AnswerCount = ISNULL(AnswerCount, 0) + 1,
            LastActivityDate = @now
        WHERE Id = @QuestionId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT CAST('Applied' AS varchar(20)) AS Outcome, @answerId AS EntityId;
END;
GO
