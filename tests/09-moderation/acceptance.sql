-- Component 09 acceptance checks. MUTATES DATA inside a transaction that is always rolled back.
-- Run only on an authorized disposable database after deploying component 09 (and 03 for the
-- CreateAnswer interaction check).
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF @@TRANCOUNT <> 0 THROW 51900, 'Run outside an existing transaction.', 1;
IF OBJECT_ID(N'dbo.Stackish_CloseQuestion', N'P') IS NULL THROW 51900, 'Deploy component 09 first.', 1;
IF OBJECT_ID(N'dbo.Stackish_CreateAnswer', N'P') IS NULL THROW 51900, 'Deploy component 03 for the close/answer check.', 1;

DECLARE @w TABLE (Outcome varchar(20), EntityId int);
DECLARE @missing int = 2147483647, @errno int;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @now datetime = GETUTCDATE(), @old datetime = '2015-06-01', @actor int, @q int, @q2 int, @q3 int, @a int,
            @link int, @link2 int, @reverse int, @closedAt datetime, @historyBefore int;

    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish moderator', @now, @now, 1, 0, 0, 0);
    SET @actor = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, Title, Tags, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount)
        VALUES (N'q', N'q', N'<sql-server>', 1, @actor, @old, @old, 0, 0, 0, 0, 0);
    SET @q = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, Title, Tags, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount)
        VALUES (N'q2', N'q2', N'<sql-server>', 1, @actor, @old, @old, 0, 0, 0, 0, 0);
    SET @q2 = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, Title, Tags, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount)
        VALUES (N'q3', N'q3', N'<sql-server>', 1, @actor, @old, @old, 0, 0, 0, 0, 0);
    SET @q3 = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, PostTypeId, ParentId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, CommentCount)
        VALUES (N'a', 2, @q, @actor, @old, @old, 0, 0, 0);
    SET @a = CONVERT(int, SCOPE_IDENTITY());

    -- The dump has orphan PostLinks above the current Posts identity; clear any that collide
    -- with these fixture IDs (rolled back with everything else).
    DELETE dbo.PostLinks WHERE PostId IN (@q, @q2, @q3, @a) OR RelatedPostId IN (@q, @q2, @q3, @a);
    DELETE dbo.PostHistory WHERE PostId IN (@q, @q2, @q3, @a);

    -------------------------------------------------------------------------------------------
    -- Close: ClosedDate, activity and one type-10 history row with the reason.
    DELETE @w; INSERT @w EXEC dbo.Stackish_CloseQuestion @q, @actor, N'Needs more focus';
    SELECT @closedAt = ClosedDate FROM dbo.Posts WHERE Id = @q;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @q)
       OR @closedAt IS NULL OR @closedAt < DATEADD(minute, -5, @now)
       OR (SELECT LastActivityDate FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM @closedAt
        THROW 51901, 'CloseQuestion did not set ClosedDate/LastActivityDate.', 1;
    IF (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId = @q) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.PostHistory
                      WHERE PostId = @q AND PostHistoryTypeId = 10 AND UserId = @actor AND CreationDate = @closedAt
                        AND Comment = N'Needs more focus' COLLATE Latin1_General_100_BIN2 AND Text IS NULL
                        AND UserDisplayName IS NULL AND RevisionGUID IS NOT NULL)
        THROW 51902, 'CloseQuestion history row wrong.', 1;

    -- Closed questions reject new answers (component 03) but existing answers stay.
    DELETE @w; INSERT @w EXEC dbo.Stackish_CreateAnswer @q, @actor, N'Too late';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q)
       OR (SELECT COUNT(*) FROM dbo.Posts WHERE ParentId = @q) <> 1
        THROW 51903, 'CreateAnswer should reject a question closed by CloseQuestion.', 1;

    -- Repeat close (even with a different reason): NoChange, no second history row, date kept.
    DELETE @w; INSERT @w EXEC dbo.Stackish_CloseQuestion @q, @actor, N'Another reason';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @q)
       OR (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId = @q) <> 1
       OR (SELECT ClosedDate FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM @closedAt
        THROW 51904, 'Repeated close should be NoChange.', 1;

    -- Reopen: clears ClosedDate, one type-11 row, answers accepted again.
    UPDATE dbo.Posts SET LastActivityDate = @old WHERE Id = @q;
    DELETE @w; INSERT @w EXEC dbo.Stackish_ReopenQuestion @q, @actor;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @q)
       OR NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @q AND ClosedDate IS NULL AND LastActivityDate >= DATEADD(minute, -5, @now))
       OR (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId = @q AND PostHistoryTypeId = 11 AND UserId = @actor
                                                   AND Comment IS NULL AND Text IS NULL) <> 1
       OR (SELECT COUNT(DISTINCT RevisionGUID) FROM dbo.PostHistory WHERE PostId = @q) <> 2
        THROW 51905, 'ReopenQuestion did not reopen correctly.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_ReopenQuestion @q, @actor;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @q)
       OR (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId = @q) <> 2
        THROW 51906, 'Repeated reopen should be NoChange.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_CreateAnswer @q, @actor, N'Reopened answer';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied') THROW 51907, 'Reopened question should accept answers.', 1;

    -- Missing, wrong-type and invalid actor cases change nothing.
    SET @historyBefore = (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId IN (@q, @q2, @a));
    DELETE @w; INSERT @w EXEC dbo.Stackish_CloseQuestion @missing, @actor, N'x';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51910, 'Close missing target.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_ReopenQuestion @missing, @actor;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51911, 'Reopen missing target.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_CloseQuestion @a, @actor, N'x';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @a) THROW 51912, 'Closing an answer should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_ReopenQuestion @a, @actor;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @a) THROW 51913, 'Reopening an answer should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_CloseQuestion @q2, @missing, N'x';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q2) THROW 51914, 'Missing actor close should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_CloseQuestion @q2, -1, N'x';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q2) THROW 51915, 'Nonpositive actor close should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_CloseQuestion @q2, NULL, N'x';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q2) THROW 51916, 'NULL actor close should be Conflict.', 1;
    UPDATE dbo.Posts SET ClosedDate = @old WHERE Id = @q3;
    DELETE @w; INSERT @w EXEC dbo.Stackish_ReopenQuestion @q3, @missing;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q3) THROW 51917, 'Missing actor reopen should be Conflict.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Posts WHERE Id IN (@q2, @a) AND ClosedDate IS NOT NULL)
       OR (SELECT ClosedDate FROM dbo.Posts WHERE Id = @q3) IS DISTINCT FROM @old
       OR (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId IN (@q, @q2, @q3, @a)) <> @historyBefore
        THROW 51918, 'Rejected close/reopen calls changed state.', 1;
    UPDATE dbo.Posts SET ClosedDate = NULL WHERE Id = @q3;

    -------------------------------------------------------------------------------------------
    -- Links: add, repeat, reverse direction, other type, self, wrong type, missing.
    DELETE @w; INSERT @w EXEC dbo.Stackish_AddQuestionLink @q, @q2, @actor;   -- default type 1
    SELECT @link = EntityId FROM @w;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId > 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.PostLinks WHERE Id = @link AND PostId = @q AND RelatedPostId = @q2 AND LinkTypeId = 1
                                                    AND CreationDate >= DATEADD(minute, -5, @now))
        THROW 51920, 'AddQuestionLink did not insert the link.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_AddQuestionLink @q, @q2, @actor, 1;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @link)
       OR (SELECT COUNT(*) FROM dbo.PostLinks WHERE PostId = @q AND RelatedPostId = @q2) <> 1
        THROW 51921, 'Repeated link should be NoChange with the existing LinkId.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_AddQuestionLink @q2, @q, @actor, 1;
    SELECT @reverse = EntityId FROM @w;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId <> @link)
       OR NOT EXISTS (SELECT 1 FROM dbo.PostLinks WHERE Id = @reverse AND PostId = @q2 AND RelatedPostId = @q AND LinkTypeId = 1)
        THROW 51922, 'Reverse-direction link should be distinct.', 1;

    -- A duplicate link is not a closure.
    SET @historyBefore = (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId IN (@q, @q2));
    DELETE @w; INSERT @w EXEC dbo.Stackish_AddQuestionLink @q, @q2, @actor, 3;
    SELECT @link2 = EntityId FROM @w;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId NOT IN (@link, @reverse))
       OR NOT EXISTS (SELECT 1 FROM dbo.PostLinks WHERE Id = @link2 AND PostId = @q AND RelatedPostId = @q2 AND LinkTypeId = 3)
       OR EXISTS (SELECT 1 FROM dbo.Posts WHERE Id IN (@q, @q2) AND ClosedDate IS NOT NULL)
       OR (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId IN (@q, @q2)) <> @historyBefore
        THROW 51923, 'Duplicate link should be a separate triple and must not close.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_AddQuestionLink @q, @q, @actor, 1;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51924, 'Self-link should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_AddQuestionLink @q, @a, @actor, 1;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51925, 'Link to an answer should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_AddQuestionLink @a, @q, @actor, 1;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @a) THROW 51926, 'Link from an answer should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_AddQuestionLink @q, @q3, @missing, 1;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51927, 'Link by missing actor should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_AddQuestionLink @missing, @q, @actor, 1;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51928, 'Missing source should be NotFound.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_AddQuestionLink @q, @missing, @actor, 1;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51929, 'Missing related question should be NotFound.', 1;
    IF (SELECT COUNT(*) FROM dbo.PostLinks WHERE PostId IN (@q, @q2, @q3, @a) OR RelatedPostId IN (@q, @q2, @q3, @a)) <> 3
        THROW 51930, 'Rejected link calls changed PostLinks.', 1;

    -- Invalid link types throw before doing anything.
    DECLARE @i int = 1;
    WHILE @i <= 6
    BEGIN
        SET @errno = 0;
        BEGIN TRY
            IF @i = 1 EXEC dbo.Stackish_AddQuestionLink @q, @q3, @actor, 2;
            IF @i = 2 EXEC dbo.Stackish_AddQuestionLink @q, @q3, @actor, 0;
            IF @i = 3 EXEC dbo.Stackish_AddQuestionLink @q, @q3, @actor, NULL;
            IF @i = 4 EXEC dbo.Stackish_CloseQuestion @q3, @actor, NULL;
            IF @i = 5 EXEC dbo.Stackish_CloseQuestion @q3, @actor, N'  ';
            IF @i = 6 BEGIN DECLARE @ws nvarchar(max) = NCHAR(9) + NCHAR(13) + NCHAR(10) + N' '; EXEC dbo.Stackish_CloseQuestion @q3, @actor, @ws; END;
        END TRY
        BEGIN CATCH
            SET @errno = ERROR_NUMBER();
        END CATCH;
        IF @errno < 50000 THROW 51931, 'Invalid moderation input was accepted.', 1;
        SET @i += 1;
    END;
    IF EXISTS (SELECT 1 FROM dbo.PostLinks WHERE PostId = @q AND RelatedPostId = @q3)
       OR (SELECT ClosedDate FROM dbo.Posts WHERE Id = @q3) IS NOT NULL
        THROW 51932, 'Invalid input left changes.', 1;

    -- A long reason is kept whole (PostHistory.Comment is nvarchar(max)).
    DECLARE @long nvarchar(max) = REPLICATE(CONVERT(nvarchar(max), N'Ünïcode reason '), 1000);
    DELETE @w; INSERT @w EXEC dbo.Stackish_CloseQuestion @q3, @actor, @long;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @q3)
       OR NOT EXISTS (SELECT 1 FROM dbo.PostHistory WHERE PostId = @q3 AND PostHistoryTypeId = 10
                                                     AND Comment = @long COLLATE Latin1_General_100_BIN2 AND LEN(Comment) = LEN(@long))
        THROW 51933, 'Long Unicode close reason was not stored intact.', 1;

    -------------------------------------------------------------------------------------------
    -- Removal: exactly one LinkId; closure and history unchanged; reopen does not remove links.
    UPDATE dbo.Posts SET ClosedDate = @now WHERE Id = @q;
    SET @historyBefore = (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId IN (@q, @q2));
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemoveQuestionLink @link, @missing;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @link)
       OR NOT EXISTS (SELECT 1 FROM dbo.PostLinks WHERE Id = @link)
        THROW 51940, 'Removal by a missing actor should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemoveQuestionLink @link, @actor;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @link)
       OR EXISTS (SELECT 1 FROM dbo.PostLinks WHERE Id = @link)
       OR (SELECT COUNT(*) FROM dbo.PostLinks WHERE Id IN (@reverse, @link2)) <> 2
       OR (SELECT ClosedDate FROM dbo.Posts WHERE Id = @q) IS DISTINCT FROM @now
       OR (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId IN (@q, @q2)) <> @historyBefore
        THROW 51941, 'RemoveQuestionLink should delete exactly one link and nothing else.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemoveQuestionLink @link, @actor;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @link) THROW 51942, 'Removing a removed link should be NotFound.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RemoveQuestionLink @missing, @actor;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51943, 'Missing link should be NotFound.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_ReopenQuestion @q, @actor;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied')
       OR NOT EXISTS (SELECT 1 FROM dbo.PostLinks WHERE Id = @link2 AND LinkTypeId = 3)
        THROW 51944, 'Reopening must not remove duplicate links.', 1;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
IF @@TRANCOUNT <> 0 THROW 51999, 'Acceptance checks left an open transaction.', 1;
PRINT 'Component 09 acceptance checks passed; fixtures rolled back.';
