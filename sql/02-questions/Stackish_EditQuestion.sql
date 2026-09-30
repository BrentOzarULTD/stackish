SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_EditQuestion
    @QuestionId int,
    @EditorUserId int,
    @Title nvarchar(max),
    @Body nvarchar(max),
    @EditSummary nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @blank nvarchar(4) = NCHAR(32) + NCHAR(9) + NCHAR(10) + NCHAR(13);
    IF @Title IS NULL OR TRIM(@blank FROM @Title) = N'' THROW 50221, 'Title is required and cannot be blank.', 1;
    IF DATALENGTH(@Title) / 2 > 250 THROW 50222, 'Title cannot exceed 250 characters.', 1;
    IF @Body IS NULL OR TRIM(@blank FROM @Body) = N'' THROW 50223, 'Body is required and cannot be blank.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @EditorUserId AND Id > 0)
    BEGIN
        SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
        RETURN;
    END;

    DECLARE @oldTitle nvarchar(250), @oldBody nvarchar(max), @found bit = 0, @changed bit = 0, @now datetime = GETUTCDATE(), @rev uniqueidentifier = NEWID();
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @oldTitle = Title, @oldBody = Body, @found = 1
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

        IF ISNULL(CONVERT(varbinary(max), @oldTitle), 0x) = ISNULL(CONVERT(varbinary(max), CONVERT(nvarchar(250), @Title)), 0x)
           AND ISNULL(CONVERT(varbinary(max), @oldBody), 0x) = ISNULL(CONVERT(varbinary(max), @Body), 0x)
        BEGIN
            COMMIT TRANSACTION;
            SELECT CAST('NoChange' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
            RETURN;
        END;

        UPDATE dbo.Posts
        SET Title = CONVERT(nvarchar(250), @Title),
            Body = @Body,
            LastEditDate = @now,
            LastActivityDate = @now,
            LastEditorUserId = @EditorUserId,
            LastEditorDisplayName = NULL
        WHERE Id = @QuestionId;

        IF ISNULL(CONVERT(varbinary(max), @oldTitle), 0x) <> ISNULL(CONVERT(varbinary(max), CONVERT(nvarchar(250), @Title)), 0x)
        BEGIN
            INSERT dbo.PostHistory (PostHistoryTypeId, PostId, RevisionGUID, CreationDate, UserId, UserDisplayName, Comment, Text)
            VALUES (4, @QuestionId, @rev, @now, @EditorUserId, NULL, @EditSummary, @Title);
            SET @changed = 1;
        END;
        IF ISNULL(CONVERT(varbinary(max), @oldBody), 0x) <> ISNULL(CONVERT(varbinary(max), @Body), 0x)
        BEGIN
            INSERT dbo.PostHistory (PostHistoryTypeId, PostId, RevisionGUID, CreationDate, UserId, UserDisplayName, Comment, Text)
            VALUES (5, @QuestionId, @rev, @now, @EditorUserId, NULL, @EditSummary, @Body);
            SET @changed = 1;
        END;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT CAST('Applied' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
END;
GO
