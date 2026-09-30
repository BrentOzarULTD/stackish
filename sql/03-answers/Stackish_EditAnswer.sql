SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_EditAnswer
    @AnswerId int,
    @EditorUserId int,
    @Body nvarchar(max),
    @EditSummary nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @blank nvarchar(4) = NCHAR(32) + NCHAR(9) + NCHAR(10) + NCHAR(13);
    IF @Body IS NULL OR TRIM(@blank FROM @Body) = N'' THROW 50321, 'Body is required and cannot be blank.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @EditorUserId AND Id > 0)
    BEGIN
        SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @AnswerId AS EntityId;
        RETURN;
    END;

    SET XACT_ABORT ON;
    DECLARE @oldBody nvarchar(max), @parentId int, @found bit = 0, @now datetime = GETUTCDATE(), @rev uniqueidentifier = NEWID();
    SELECT @parentId = ParentId
    FROM dbo.Posts
    WHERE Id = @AnswerId AND PostTypeId = 2;

    BEGIN TRY
        BEGIN TRANSACTION;
        IF @parentId IS NOT NULL
            SELECT @parentId = Id
            FROM dbo.Posts WITH (UPDLOCK, HOLDLOCK)
            WHERE Id = @parentId AND PostTypeId = 1;

        SELECT @oldBody = Body, @parentId = ParentId, @found = 1
        FROM dbo.Posts WITH (UPDLOCK, HOLDLOCK)
        WHERE Id = @AnswerId AND PostTypeId = 2;

        IF @found = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @AnswerId)
                SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @AnswerId AS EntityId;
            ELSE
                SELECT CAST('NotFound' AS varchar(20)) AS Outcome, @AnswerId AS EntityId;
            COMMIT TRANSACTION;
            RETURN;
        END;

        IF ISNULL(CONVERT(varbinary(max), @oldBody), 0x) = ISNULL(CONVERT(varbinary(max), @Body), 0x)
        BEGIN
            COMMIT TRANSACTION;
            SELECT CAST('NoChange' AS varchar(20)) AS Outcome, @AnswerId AS EntityId;
            RETURN;
        END;

        UPDATE dbo.Posts
        SET Body = @Body,
            LastEditDate = @now,
            LastActivityDate = @now,
            LastEditorUserId = @EditorUserId,
            LastEditorDisplayName = NULL
        WHERE Id = @AnswerId;

        UPDATE dbo.Posts
        SET LastActivityDate = @now
        WHERE Id = @parentId AND PostTypeId = 1;

        INSERT dbo.PostHistory (PostHistoryTypeId, PostId, RevisionGUID, CreationDate, UserId, UserDisplayName, Comment, Text)
        VALUES (5, @AnswerId, @rev, @now, @EditorUserId, NULL, @EditSummary, @Body);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT CAST('Applied' AS varchar(20)) AS Outcome, @AnswerId AS EntityId;
END;
GO
