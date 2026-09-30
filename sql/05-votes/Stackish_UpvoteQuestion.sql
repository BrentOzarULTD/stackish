SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_UpvoteQuestion
    @QuestionId int,
    @UserId int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- The four vote entry points share this body; only these constants differ.
    DECLARE @postTypeId int = 1, @voteTypeId int = 2, @scoreDelta int = 1, @repDelta int = 10;
    DECLARE @now datetime = GETUTCDATE(), @outcome varchar(20), @type int, @owner int, @same int, @opposite int;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Every vote change on a post starts by U-locking the post row, so identical
        -- concurrent calls line up here instead of both passing the duplicate check.
        SELECT @type = PostTypeId, @owner = OwnerUserId
        FROM dbo.Posts WITH (UPDLOCK)
        WHERE Id = @QuestionId;

        IF @type IS NULL
            SET @outcome = 'NotFound';
        ELSE IF @type <> @postTypeId
             OR @owner = @UserId
             OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId AND Id > 0)
            SET @outcome = 'Conflict';
        ELSE
        BEGIN
            -- Only votes attributed to this actor count; anonymous imported votes never match.
            SELECT @same = ISNULL(SUM(IIF(VoteTypeId = @voteTypeId, 1, 0)), 0),
                   @opposite = ISNULL(SUM(IIF(VoteTypeId <> @voteTypeId, 1, 0)), 0)
            FROM dbo.Votes
            WHERE PostId = @QuestionId
              AND UserId = @UserId
              AND VoteTypeId IN (2, 3);

            IF @opposite > 0
                SET @outcome = 'Conflict';
            ELSE IF @same > 0
                SET @outcome = 'NoChange';
            ELSE
            BEGIN
                INSERT dbo.Votes (PostId, UserId, BountyAmount, VoteTypeId, CreationDate)
                VALUES (@QuestionId, @UserId, NULL, @voteTypeId, @now);

                UPDATE dbo.Posts
                SET Score = Score + @scoreDelta
                WHERE Id = @QuestionId;

                -- One statement for actor and owner keeps the Users lock order stable.
                -- A missing owner simply matches no row.
                UPDATE dbo.Users
                SET UpVotes = UpVotes + IIF(Id = @UserId, 1, 0),
                    Reputation = IIF(Id = @owner, GREATEST(1, Reputation + @repDelta), Reputation)
                WHERE Id IN (@UserId, @owner);

                SET @outcome = 'Applied';
            END;
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
