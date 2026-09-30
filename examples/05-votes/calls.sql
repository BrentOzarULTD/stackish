-- Example calls for component 05. Placeholder IDs: replace 456 (question), 789 (answer) and
-- 123 (voting user, not the post owner) with values from your disposable database.
-- Every write call below changes Votes, Posts.Score and Users counters when it applies.

DECLARE @write TABLE (Outcome varchar(20), EntityId int);

-- UpvoteQuestion normal call, then missing target.
DELETE @write; INSERT @write EXEC dbo.Stackish_UpvoteQuestion @QuestionId = 456, @UserId = 123; SELECT * FROM @write;
DELETE @write; INSERT @write EXEC dbo.Stackish_UpvoteQuestion @QuestionId = 2147483647, @UserId = 123; SELECT * FROM @write;

-- RemovePostVote normal call (removes the upvote above), then missing target.
DELETE @write; INSERT @write EXEC dbo.Stackish_RemovePostVote @PostId = 456, @UserId = 123; SELECT * FROM @write;
DELETE @write; INSERT @write EXEC dbo.Stackish_RemovePostVote @PostId = 2147483647, @UserId = 123; SELECT * FROM @write;

-- DownvoteQuestion normal call, then missing target.
DELETE @write; INSERT @write EXEC dbo.Stackish_DownvoteQuestion @QuestionId = 456, @UserId = 123; SELECT * FROM @write;
DELETE @write; INSERT @write EXEC dbo.Stackish_DownvoteQuestion @QuestionId = 2147483647, @UserId = 123; SELECT * FROM @write;

-- UpvoteAnswer normal call, then missing target.
DELETE @write; INSERT @write EXEC dbo.Stackish_UpvoteAnswer @AnswerId = 789, @UserId = 123; SELECT * FROM @write;
DELETE @write; INSERT @write EXEC dbo.Stackish_UpvoteAnswer @AnswerId = 2147483647, @UserId = 123; SELECT * FROM @write;

-- DownvoteAnswer on the same answer is Conflict until the upvote is removed.
DELETE @write; INSERT @write EXEC dbo.Stackish_DownvoteAnswer @AnswerId = 789, @UserId = 123; SELECT * FROM @write;
DELETE @write; INSERT @write EXEC dbo.Stackish_RemovePostVote @PostId = 789, @UserId = 123; SELECT * FROM @write;
DELETE @write; INSERT @write EXEC dbo.Stackish_DownvoteAnswer @AnswerId = 789, @UserId = 123; SELECT * FROM @write;
DELETE @write; INSERT @write EXEC dbo.Stackish_DownvoteAnswer @AnswerId = 2147483647, @UserId = 123; SELECT * FROM @write;

-- GetPostVoteSummary normal call, then missing target (empty result set).
EXEC dbo.Stackish_GetPostVoteSummary @PostId = 456;
EXEC dbo.Stackish_GetPostVoteSummary @PostId = 2147483647;
