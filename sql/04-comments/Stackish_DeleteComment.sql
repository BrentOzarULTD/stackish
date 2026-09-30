SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_DeleteComment
    @CommentId int,
    @UserId int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @postId int, @existingUserId int, @found bit = 0;
    BEGIN TRY
        BEGIN TRANSACTION;
        SELECT @postId = PostId, @existingUserId = UserId, @found = 1
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

        DELETE dbo.Comments WHERE Id = @CommentId;

        UPDATE dbo.Posts
        SET CommentCount = CASE WHEN ISNULL(CommentCount, 0) > 0 THEN ISNULL(CommentCount, 0) - 1 ELSE 0 END
        WHERE Id = @postId AND PostTypeId IN (1,2);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT CAST('Applied' AS varchar(20)) AS Outcome, @CommentId AS EntityId;
END;
GO
