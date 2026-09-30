SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_AddComment
    @PostId int,
    @UserId int,
    @Text nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @blank nvarchar(4) = NCHAR(32) + NCHAR(9) + NCHAR(10) + NCHAR(13);
    IF @Text IS NULL OR TRIM(@blank FROM @Text) = N'' THROW 50401, 'Comment text is required and cannot be blank.', 1;
    IF DATALENGTH(@Text) / 2 > 700 THROW 50402, 'Comment text cannot exceed 700 characters.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId AND Id > 0)
    BEGIN
        SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @PostId AS EntityId;
        RETURN;
    END;

    DECLARE @now datetime = GETUTCDATE(), @commentId int;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF NOT EXISTS (SELECT 1 FROM dbo.Posts WITH (UPDLOCK, HOLDLOCK) WHERE Id = @PostId AND PostTypeId IN (1,2))
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @PostId)
                SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @PostId AS EntityId;
            ELSE
                SELECT CAST('NotFound' AS varchar(20)) AS Outcome, @PostId AS EntityId;
            COMMIT TRANSACTION;
            RETURN;
        END;

        INSERT dbo.Comments (CreationDate, PostId, Score, Text, UserId)
        VALUES (@now, @PostId, 0, CONVERT(nvarchar(700), @Text), @UserId);
        SET @commentId = CONVERT(int, SCOPE_IDENTITY());

        UPDATE dbo.Posts
        SET CommentCount = ISNULL(CommentCount, 0) + 1
        WHERE Id = @PostId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT CAST('Applied' AS varchar(20)) AS Outcome, @commentId AS EntityId;
END;
GO
