SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_EditComment
    @CommentId int,
    @UserId int,
    @Text nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @blank nvarchar(4) = NCHAR(32) + NCHAR(9) + NCHAR(10) + NCHAR(13);
    IF @Text IS NULL OR TRIM(@blank FROM @Text) = N'' THROW 50421, 'Comment text is required and cannot be blank.', 1;
    IF DATALENGTH(@Text) / 2 > 700 THROW 50422, 'Comment text cannot exceed 700 characters.', 1;

    DECLARE @existingUserId int, @oldText nvarchar(700), @found bit = 0;
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @existingUserId = UserId, @oldText = Text, @found = 1
        FROM dbo.Comments WITH (UPDLOCK, HOLDLOCK)
        WHERE Id = @CommentId;

        IF @found = 0
        BEGIN
            COMMIT TRANSACTION;
            SELECT CAST('NotFound' AS varchar(20)) AS Outcome, @CommentId AS EntityId;
            RETURN;
        END;
        IF @existingUserId IS NULL OR @existingUserId <= 0 OR @existingUserId <> @UserId
           OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId AND Id > 0)
        BEGIN
            COMMIT TRANSACTION;
            SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @CommentId AS EntityId;
            RETURN;
        END;
        IF ISNULL(CONVERT(varbinary(max), @oldText), 0x) = ISNULL(CONVERT(varbinary(max), CONVERT(nvarchar(700), @Text)), 0x)
        BEGIN
            COMMIT TRANSACTION;
            SELECT CAST('NoChange' AS varchar(20)) AS Outcome, @CommentId AS EntityId;
            RETURN;
        END;

        UPDATE dbo.Comments
        SET Text = CONVERT(nvarchar(700), @Text)
        WHERE Id = @CommentId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT CAST('Applied' AS varchar(20)) AS Outcome, @CommentId AS EntityId;
END;
GO
