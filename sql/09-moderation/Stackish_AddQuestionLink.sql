SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_AddQuestionLink
    @QuestionId int,
    @RelatedQuestionId int,
    @UserId int,
    @LinkTypeId int = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @LinkTypeId IS NULL OR @LinkTypeId NOT IN (1, 3)
        THROW 50902, 'LinkTypeId must be 1 (linked) or 3 (duplicate).', 1;

    SET XACT_ABORT ON;
    DECLARE @now datetime = GETUTCDATE(), @outcome varchar(20), @entityId int,
            @sourceType int, @targetType int, @linkId int;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- PostLinks has no uniqueness constraint. U-locking the source question row makes
        -- concurrent adds from the same question take turns at the existence check below.
        SELECT @sourceType = PostTypeId
        FROM dbo.Posts WITH (UPDLOCK)
        WHERE Id = @QuestionId;

        SELECT @targetType = PostTypeId
        FROM dbo.Posts
        WHERE Id = @RelatedQuestionId;

        IF @sourceType IS NULL
            SELECT @outcome = 'NotFound', @entityId = @QuestionId;
        ELSE IF @targetType IS NULL
            SELECT @outcome = 'NotFound', @entityId = @RelatedQuestionId;
        ELSE IF @sourceType <> 1
             OR @targetType <> 1
             OR @QuestionId = @RelatedQuestionId
             OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId AND Id > 0)
            SELECT @outcome = 'Conflict', @entityId = @QuestionId;
        ELSE
        BEGIN
            SELECT TOP (1) @linkId = Id
            FROM dbo.PostLinks
            WHERE PostId = @QuestionId
              AND RelatedPostId = @RelatedQuestionId
              AND LinkTypeId = @LinkTypeId
            ORDER BY Id;

            IF @linkId IS NOT NULL
                SET @outcome = 'NoChange';
            ELSE
            BEGIN
                -- A duplicate link is only a link: it does not close the question.
                INSERT dbo.PostLinks (CreationDate, PostId, RelatedPostId, LinkTypeId)
                VALUES (@now, @QuestionId, @RelatedQuestionId, @LinkTypeId);
                SET @linkId = CONVERT(int, SCOPE_IDENTITY());
                SET @outcome = 'Applied';
            END;
            SET @entityId = @linkId;
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT @outcome AS Outcome, @entityId AS EntityId;
END;
GO
