SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_RemovePostVote
    @PostId int,
    @UserId int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @outcome varchar(20), @type int, @owner int, @matches int, @voteId int, @voteTypeId int;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Same post-row lock as the vote procedures, so a removal cannot interleave
        -- with another removal or a new vote on this post.
        SELECT @type = PostTypeId, @owner = OwnerUserId
        FROM dbo.Posts WITH (UPDLOCK)
        WHERE Id = @PostId;

        IF @type IS NULL
            SET @outcome = 'NotFound';
        ELSE IF @type NOT IN (1, 2)
             OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId AND Id > 0)
            SET @outcome = 'Conflict';
        ELSE
        BEGIN
            SELECT @matches = COUNT(*), @voteId = MIN(Id), @voteTypeId = MIN(VoteTypeId)
            FROM dbo.Votes
            WHERE PostId = @PostId
              AND UserId = @UserId
              AND VoteTypeId IN (2, 3);

            IF @matches = 0
                SET @outcome = 'NoChange';
            ELSE IF @matches > 1
                SET @outcome = 'Conflict';   -- pre-existing duplicates: report, don't repair
            ELSE
            BEGIN
                DELETE dbo.Votes WHERE Id = @voteId;

                UPDATE dbo.Posts
                SET Score = Score - IIF(@voteTypeId = 2, 1, -1)
                WHERE Id = @PostId;

                -- Counters never go below zero; reputation keeps its floor of 1, so a
                -- vote applied near the floor is not exactly reversible.
                UPDATE dbo.Users
                SET UpVotes = IIF(Id = @UserId AND @voteTypeId = 2, GREATEST(0, UpVotes - 1), UpVotes),
                    DownVotes = IIF(Id = @UserId AND @voteTypeId = 3, GREATEST(0, DownVotes - 1), DownVotes),
                    Reputation = IIF(Id = @owner, GREATEST(1, Reputation + IIF(@voteTypeId = 2, -10, 2)), Reputation)
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

    SELECT @outcome AS Outcome, @PostId AS EntityId;
END;
GO
