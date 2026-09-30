-- Component 05 acceptance checks. MUTATES DATA inside a transaction that is always rolled back.
-- Run only on an authorized disposable database after deploying component 05.
-- Scalar assertions use IS DISTINCT FROM so a NULL actual value fails instead of slipping past.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF @@TRANCOUNT <> 0 THROW 51500, 'Run outside an existing transaction.', 1;
IF OBJECT_ID(N'dbo.Stackish_UpvoteQuestion', N'P') IS NULL THROW 51500, 'Deploy component 05 first.', 1;

DECLARE @w TABLE (Outcome varchar(20), EntityId int);
DECLARE @s TABLE (PostId int, Score int, RecordedUpVotes bigint, RecordedDownVotes bigint);
DECLARE @missing int = 2147483647;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @now datetime = GETUTCDATE(), @owner int, @voter int, @lowOwner int, @other int,
            @q int, @a int, @lowQ int, @ghostQ int, @nullQ int, @wiki int, @dupQ int, @mixQ int, @ghostUser int;

    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish vote owner', @now, @now, 100, 0, 0, 0);
    SET @owner = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish voter', @now, @now, 50, 7, 3, 0);
    SET @voter = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish low rep owner', @now, @now, 2, 0, 0, 0);
    SET @lowOwner = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish other voter', @now, @now, 500, 0, 0, 0);
    SET @other = CONVERT(int, SCOPE_IDENTITY());
    SET @ghostUser = @other + 1000000;   -- positive ID with no Users row
    IF EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @ghostUser) THROW 51501, 'Ghost user id unexpectedly exists.', 1;

    -- Imported-looking score of 42 that does not match any vote rows.
    INSERT dbo.Posts (Body, Title, Tags, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount)
        VALUES (N'q', N'q', N'<sql-server>', 1, @owner, @now, @now, 42, 0, 1, 0, 0);
    SET @q = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, PostTypeId, ParentId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, CommentCount)
        VALUES (N'a', 2, @q, @owner, @now, @now, 5, 0, 0);
    SET @a = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, Title, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount)
        VALUES (N'low', N'low', 1, @lowOwner, @now, @now, 0, 0);
    SET @lowQ = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, Title, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount)
        VALUES (N'ghost owner', N'ghost owner', 1, @ghostUser, @now, @now, 0, 0);
    SET @ghostQ = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, Title, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount)
        VALUES (N'null owner', N'null owner', 1, NULL, @now, @now, 0, 0);
    SET @nullQ = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount)
        VALUES (N'wiki', 5, @owner, @now, @now, 0, 0);
    SET @wiki = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, Title, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount)
        VALUES (N'dup', N'dup', 1, @owner, @now, @now, 10, 0);
    SET @dupQ = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, Title, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount)
        VALUES (N'mix', N'mix', 1, @owner, @now, @now, 10, 0);
    SET @mixQ = CONVERT(int, SCOPE_IDENTITY());

    -- The dump contains orphan Votes whose PostId/UserId are above the current identity values,
    -- so fresh fixture IDs can inherit them. Clear them inside this rolled-back transaction.
    DELETE dbo.Votes
    WHERE PostId IN (@q, @a, @lowQ, @ghostQ, @nullQ, @wiki, @dupQ, @mixQ)
       OR UserId IN (@owner, @voter, @lowOwner, @other);

    -- Historical anonymous votes on the main question: two NULL-user ups, one zero-user down.
    INSERT dbo.Votes (PostId, UserId, BountyAmount, VoteTypeId, CreationDate)
        VALUES (@q, NULL, NULL, 2, '2010-01-01'), (@q, NULL, NULL, 2, '2010-01-02'), (@q, 0, NULL, 3, '2010-01-03');
    -- Pre-existing duplicate attributed votes that the procedures must not repair.
    INSERT dbo.Votes (PostId, UserId, BountyAmount, VoteTypeId, CreationDate)
        VALUES (@dupQ, @voter, NULL, 2, '2011-01-01'), (@dupQ, @voter, NULL, 2, '2011-01-02'),
               (@mixQ, @voter, NULL, 2, '2011-01-01'), (@mixQ, @voter, NULL, 3, '2011-01-02');

    -------------------------------------------------------------------------------------------
    -- Summary before any Stackish vote: stored score is independent of recorded rows.
    DELETE @s; INSERT @s EXEC dbo.Stackish_GetPostVoteSummary @q;
    IF (SELECT COUNT(*) FROM @s) <> 1
       OR NOT EXISTS (SELECT 1 FROM @s WHERE PostId = @q AND Score = 42 AND RecordedUpVotes = 2 AND RecordedDownVotes = 1)
        THROW 51502, 'GetPostVoteSummary did not report stored score and recorded counts.', 1;
    DELETE @s; INSERT @s EXEC dbo.Stackish_GetPostVoteSummary @nullQ;
    IF NOT EXISTS (SELECT 1 FROM @s WHERE PostId = @nullQ AND Score = 0 AND RecordedUpVotes = 0 AND RecordedDownVotes = 0)
        THROW 51503, 'GetPostVoteSummary should return zeros for an existing post without votes.', 1;
    DELETE @s; INSERT @s EXEC dbo.Stackish_GetPostVoteSummary @missing;
    IF EXISTS (SELECT 1 FROM @s) THROW 51504, 'GetPostVoteSummary should be empty for a missing post.', 1;
    DELETE @s; INSERT @s EXEC dbo.Stackish_GetPostVoteSummary @wiki;
    IF EXISTS (SELECT 1 FROM @s) THROW 51505, 'GetPostVoteSummary should be empty for a non-question/answer post.', 1;
    DELETE @s; INSERT @s EXEC dbo.Stackish_GetPostVoteSummary NULL;
    IF EXISTS (SELECT 1 FROM @s) THROW 51506, 'GetPostVoteSummary should be empty for NULL.', 1;

    -------------------------------------------------------------------------------------------
    -- Upvote question: vote row, score, owner reputation, actor counter.
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @q, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @q) THROW 51510, 'UpvoteQuestion should apply.', 1;
    IF (SELECT Score FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM 43 THROW 51511, 'UpvoteQuestion score delta wrong.', 1;
    IF (SELECT Reputation FROM dbo.Users WHERE Id = @owner) IS DISTINCT FROM 110 THROW 51512, 'UpvoteQuestion owner reputation wrong.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @voter AND UpVotes = 8 AND DownVotes = 3 AND Reputation = 50)
        THROW 51513, 'UpvoteQuestion actor counters wrong.', 1;
    IF (SELECT COUNT(*) FROM dbo.Votes WHERE PostId = @q AND UserId = @voter AND VoteTypeId = 2 AND BountyAmount IS NULL
                                        AND CreationDate >= DATEADD(minute, -5, @now)) <> 1
       OR (SELECT COUNT(*) FROM dbo.Votes WHERE PostId = @q) <> 4
        THROW 51514, 'UpvoteQuestion vote row wrong.', 1;
    IF (SELECT LastActivityDate FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM @now THROW 51515, 'Voting must not bump LastActivityDate.', 1;

    -- Same vote again: NoChange, nothing moves.
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @q, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @q) THROW 51516, 'Repeated upvote should be NoChange.', 1;
    -- Opposite vote while the upvote exists: Conflict, nothing moves.
    DELETE @w; INSERT @w EXEC dbo.Stackish_DownvoteQuestion @q, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51517, 'Opposite vote should be Conflict.', 1;
    IF (SELECT Score FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM 43
       OR (SELECT Reputation FROM dbo.Users WHERE Id = @owner) IS DISTINCT FROM 110
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @voter AND UpVotes = 8 AND DownVotes = 3)
       OR (SELECT COUNT(*) FROM dbo.Votes WHERE PostId = @q) <> 4
        THROW 51518, 'NoChange/Conflict vote calls changed state.', 1;

    DELETE @s; INSERT @s EXEC dbo.Stackish_GetPostVoteSummary @q;
    IF NOT EXISTS (SELECT 1 FROM @s WHERE PostId = @q AND Score = 43 AND RecordedUpVotes = 3 AND RecordedDownVotes = 1)
        THROW 51519, 'Summary after upvote wrong.', 1;

    -- Remove: deletes only the actor's row and reverses every delta.
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @q, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @q) THROW 51520, 'RemovePostVote should apply.', 1;
    IF (SELECT Score FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM 42
       OR (SELECT Reputation FROM dbo.Users WHERE Id = @owner) IS DISTINCT FROM 100
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @voter AND UpVotes = 7 AND DownVotes = 3 AND Reputation = 50)
        THROW 51521, 'RemovePostVote did not reverse deltas.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Votes WHERE PostId = @q AND UserId = @voter)
       OR (SELECT COUNT(*) FROM dbo.Votes WHERE PostId = @q AND (UserId IS NULL OR UserId = 0)) <> 3
        THROW 51522, 'RemovePostVote removed the wrong rows.', 1;

    -- Remove again, and removal by someone whose only "votes" here are anonymous history: NoChange.
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @q, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @q) THROW 51523, 'Second removal should be NoChange.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @q, @other;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @q) THROW 51524, 'Anonymous votes must not be removable as the caller''s.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @q, 0;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51525, 'UserId 0 cannot claim anonymous votes.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @q, NULL;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51526, 'NULL actor cannot claim anonymous votes.', 1;
    IF (SELECT COUNT(*) FROM dbo.Votes WHERE PostId = @q) <> 3 OR (SELECT Score FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM 42
        THROW 51527, 'Anonymous votes were changed.', 1;

    -- Downvote question after removal: -1 score, -2 reputation, DownVotes +1.
    DELETE @w; INSERT @w EXEC dbo.Stackish_DownvoteQuestion @q, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @q)
       OR (SELECT Score FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM 41
       OR (SELECT Reputation FROM dbo.Users WHERE Id = @owner) IS DISTINCT FROM 98
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @voter AND UpVotes = 7 AND DownVotes = 4 AND Reputation = 50)
       OR (SELECT COUNT(*) FROM dbo.Votes WHERE PostId = @q AND UserId = @voter AND VoteTypeId = 3) <> 1
        THROW 51530, 'DownvoteQuestion deltas wrong.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @q, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51531, 'Upvote over a downvote should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @q, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @q)
       OR (SELECT Score FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM 42
       OR (SELECT Reputation FROM dbo.Users WHERE Id = @owner) IS DISTINCT FROM 100
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @voter AND UpVotes = 7 AND DownVotes = 3)
        THROW 51532, 'Removing a downvote did not reverse deltas.', 1;

    -------------------------------------------------------------------------------------------
    -- Answers: deltas land on the answer and its owner; the parent question is untouched.
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteAnswer @a, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @a)
       OR (SELECT Score FROM dbo.Posts WHERE Id = @a) IS DISTINCT FROM 6
       OR (SELECT Score FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM 42
       OR (SELECT Reputation FROM dbo.Users WHERE Id = @owner) IS DISTINCT FROM 110
        THROW 51540, 'UpvoteAnswer deltas wrong.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_DownvoteAnswer @a, @other;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @a)
       OR (SELECT Score FROM dbo.Posts WHERE Id = @a) IS DISTINCT FROM 5
       OR (SELECT Reputation FROM dbo.Users WHERE Id = @owner) IS DISTINCT FROM 108
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @other AND DownVotes = 1 AND UpVotes = 0 AND Reputation = 500)
        THROW 51541, 'DownvoteAnswer deltas wrong.', 1;
    DELETE @s; INSERT @s EXEC dbo.Stackish_GetPostVoteSummary @a;
    IF NOT EXISTS (SELECT 1 FROM @s WHERE PostId = @a AND Score = 5 AND RecordedUpVotes = 1 AND RecordedDownVotes = 1)
        THROW 51542, 'Answer summary wrong.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @a, @other;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @a)
       OR (SELECT Score FROM dbo.Posts WHERE Id = @a) IS DISTINCT FROM 6
       OR (SELECT Reputation FROM dbo.Users WHERE Id = @owner) IS DISTINCT FROM 110
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @other AND DownVotes = 0)
        THROW 51543, 'Removing an answer downvote wrong.', 1;

    -------------------------------------------------------------------------------------------
    -- Wrong post type, self-vote, invalid actors, missing targets.
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @a, @other;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @a) THROW 51550, 'UpvoteQuestion on an answer should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_DownvoteAnswer @q, @other;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51551, 'DownvoteAnswer on a question should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @wiki, @other;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @wiki) THROW 51552, 'RemovePostVote on a wiki post should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @q, @owner;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51553, 'Self-vote should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_DownvoteAnswer @a, @owner;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @a) THROW 51554, 'Answer self-vote should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @q, @ghostUser;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51555, 'Missing actor should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @q, NULL;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51556, 'NULL actor should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @q, -1;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51557, 'Nonpositive actor should be Conflict.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @missing, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51558, 'UpvoteQuestion missing target.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_DownvoteQuestion @missing, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51559, 'DownvoteQuestion missing target.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteAnswer @missing, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51560, 'UpvoteAnswer missing target.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_DownvoteAnswer @missing, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51561, 'DownvoteAnswer missing target.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @missing, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51562, 'RemovePostVote missing target.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion NULL, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId IS NULL) THROW 51563, 'NULL target should be NotFound.', 1;

    IF (SELECT Score FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM 42
       OR (SELECT Score FROM dbo.Posts WHERE Id = @a) IS DISTINCT FROM 6
       OR (SELECT Reputation FROM dbo.Users WHERE Id = @owner) IS DISTINCT FROM 110
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @voter AND UpVotes = 8 AND DownVotes = 3 AND Reputation = 50)
       OR (SELECT COUNT(*) FROM dbo.Votes WHERE PostId IN (@q, @a, @wiki)) <> 4
        THROW 51564, 'Rejected vote calls changed state.', 1;

    -------------------------------------------------------------------------------------------
    -- Missing and NULL owners: the vote and score apply; no reputation moves anywhere.
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @ghostQ, @other;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @ghostQ)
       OR (SELECT Score FROM dbo.Posts WHERE Id = @ghostQ) IS DISTINCT FROM 1
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @other AND UpVotes = 1 AND Reputation = 500)
       OR EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @ghostUser)
        THROW 51570, 'Vote on a dangling-owner question wrong.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_DownvoteQuestion @nullQ, @other;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @nullQ)
       OR (SELECT Score FROM dbo.Posts WHERE Id = @nullQ) IS DISTINCT FROM -1
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @other AND DownVotes = 1 AND Reputation = 500)
        THROW 51571, 'Vote on a NULL-owner question wrong.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @ghostQ, @other;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @ghostQ)
       OR (SELECT Score FROM dbo.Posts WHERE Id = @ghostQ) IS DISTINCT FROM 0
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @other AND UpVotes = 0 AND Reputation = 500)
        THROW 51572, 'Removing a vote on a dangling-owner question wrong.', 1;

    -------------------------------------------------------------------------------------------
    -- Reputation floor of 1, and its documented irreversibility.
    DELETE @w; INSERT @w EXEC dbo.Stackish_DownvoteQuestion @lowQ, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @lowQ)
       OR (SELECT Reputation FROM dbo.Users WHERE Id = @lowOwner) IS DISTINCT FROM 1
        THROW 51580, 'Downvote should clip owner reputation at 1.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @lowQ, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @lowQ)
       OR (SELECT Reputation FROM dbo.Users WHERE Id = @lowOwner) IS DISTINCT FROM 3
        THROW 51581, 'Removing a clipped downvote should add 2 to the floored value.', 1;
    UPDATE dbo.Users SET Reputation = 5 WHERE Id = @lowOwner;
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @lowQ, @voter;
    UPDATE dbo.Users SET Reputation = 4 WHERE Id = @lowOwner;   -- as if other activity lowered it
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @lowQ, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @lowQ)
       OR (SELECT Reputation FROM dbo.Users WHERE Id = @lowOwner) IS DISTINCT FROM 1
        THROW 51582, 'Removing an upvote should clip owner reputation at 1.', 1;
    -- Actor counters never underflow even if imported totals are already zero.
    UPDATE dbo.Users SET UpVotes = 0 WHERE Id = @other;
    INSERT dbo.Votes (PostId, UserId, BountyAmount, VoteTypeId, CreationDate) VALUES (@lowQ, @other, NULL, 2, @now);
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @lowQ, @other;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @lowQ)
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @other AND UpVotes = 0)
        THROW 51583, 'Actor UpVotes should not go below zero.', 1;

    -------------------------------------------------------------------------------------------
    -- Pre-existing duplicate attributed votes are reported, never repaired.
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @dupQ, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @dupQ) THROW 51590, 'Removing duplicate votes should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @dupQ, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @dupQ) THROW 51591, 'Upvote over duplicate upvotes should be NoChange.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_DownvoteQuestion @dupQ, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @dupQ) THROW 51592, 'Downvote over duplicate upvotes should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpvoteQuestion @mixQ, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @mixQ) THROW 51593, 'Upvote over mixed votes should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @mixQ, @voter;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @mixQ) THROW 51594, 'Removing mixed votes should be Conflict.', 1;
    IF (SELECT COUNT(*) FROM dbo.Votes WHERE PostId IN (@dupQ, @mixQ) AND UserId = @voter) <> 4
       OR (SELECT Score FROM dbo.Posts WHERE Id = @dupQ) IS DISTINCT FROM 10
       OR (SELECT Score FROM dbo.Posts WHERE Id = @mixQ) IS DISTINCT FROM 10
        THROW 51595, 'Duplicate vote rows or scores were changed.', 1;

    -------------------------------------------------------------------------------------------
    -- An imported vote the owner cast on their own post can't be created here, but removing it
    -- still applies the inverse owner reputation delta like any other removal.
    DECLARE @ownerRep int = (SELECT Reputation FROM dbo.Users WHERE Id = @owner);
    INSERT dbo.Votes (PostId, UserId, BountyAmount, VoteTypeId, CreationDate) VALUES (@q, @owner, NULL, 2, '2012-01-01');
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemovePostVote @q, @owner;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @q)
       OR (SELECT Score FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM 41
       OR (SELECT Reputation FROM dbo.Users WHERE Id = @owner) IS DISTINCT FROM @ownerRep - 10
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @owner AND UpVotes = 0)
       OR EXISTS (SELECT 1 FROM dbo.Votes WHERE PostId = @q AND UserId = @owner)
        THROW 51597, 'Removing an imported self-vote should reverse the owner reputation delta.', 1;

    -------------------------------------------------------------------------------------------
    -- Result shape metadata for the read.
    IF NOT EXISTS (
        SELECT 1
        FROM sys.dm_exec_describe_first_result_set(N'EXEC dbo.Stackish_GetPostVoteSummary 1', NULL, 0)
        HAVING STRING_AGG(CONCAT(name, ' ', system_type_name), ', ') WITHIN GROUP (ORDER BY column_ordinal)
               = 'PostId int, Score int, RecordedUpVotes bigint, RecordedDownVotes bigint')
        THROW 51596, 'GetPostVoteSummary result shape changed.', 1;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
IF @@TRANCOUNT <> 0 THROW 51599, 'Acceptance checks left an open transaction.', 1;
PRINT 'Component 05 acceptance checks passed; fixtures rolled back.';
