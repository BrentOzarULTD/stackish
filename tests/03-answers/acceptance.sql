-- Component 03 acceptance checks. MUTATES DATA inside a transaction that is always rolled back.
-- Run only on an authorized disposable database after deploying component 03.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF @@TRANCOUNT <> 0 THROW 51300, 'Run outside an existing transaction.', 1;
IF OBJECT_ID(N'dbo.Stackish_CreateAnswer', N'P') IS NULL THROW 51300, 'Deploy component 03 first.', 1;

DECLARE @w TABLE (Outcome varchar(20), EntityId int);
DECLARE @missing int = 2147483647, @errno int;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @now datetime = GETUTCDATE(), @owner int, @answerer int, @other int, @q int, @closed int, @wrong int, @a int, @a2 int;
    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish answer owner', @now, @now, 100, 0, 0, 0),
               (N'Stackish answerer', @now, @now, 200, 0, 0, 0),
               (N'Stackish other', @now, @now, 300, 0, 0, 0);
    SET @other = CONVERT(int, SCOPE_IDENTITY());
    SET @answerer = @other - 1;
    SET @owner = @other - 2;

    INSERT dbo.Posts (Body, Title, Tags, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount)
        VALUES (N'q', N'q', N'<sql-server>', 1, @owner, @now, @now, 0, 0, 4, 0, 0);
    SET @q = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, Title, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount, ClosedDate)
        VALUES (N'closed', N'closed', 1, @owner, @now, @now, 0, 0, 0, 0, 0, @now);
    SET @closed = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, PostTypeId, CreationDate, LastActivityDate, Score, ViewCount)
        VALUES (N'wrong type', 4, @now, @now, 0, 0);
    SET @wrong = CONVERT(int, SCOPE_IDENTITY());

    DELETE @w; INSERT @w EXEC dbo.Stackish_CreateAnswer @q, @answerer, N'Answer Body';
    SELECT @a = EntityId FROM @w;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @a AND @a > 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @a AND PostTypeId = 2 AND ParentId = @q AND OwnerUserId = @answerer AND Body = N'Answer Body' COLLATE Latin1_General_100_BIN2
                      AND Score = 0 AND ViewCount = 0 AND CommentCount = 0 AND AnswerCount IS NULL AND FavoriteCount IS NULL)
       OR NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @q AND AnswerCount = 5)
       OR (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId = @a AND PostHistoryTypeId = 2) <> 1
        THROW 51301, 'CreateAnswer did not apply answer, parent count/activity, or history correctly.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_CreateAnswer @closed, @answerer, N'Nope';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @closed) THROW 51302, 'Closed question should reject new answer.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_CreateAnswer @a, @answerer, N'Nope';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @a) THROW 51303, 'Answers to answers should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_CreateAnswer @missing, @answerer, N'Nope';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51304, 'Missing parent should be NotFound.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_EditAnswer @a, @other, N'Answer Body';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @a) THROW 51305, 'No-op answer edit should be NoChange.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_EditAnswer @a, @other, N'answer body ', N'body edit';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @a)
       OR (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId = @a AND PostHistoryTypeId = 5) <> 1
       OR NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @a AND LastEditorUserId = @other)
        THROW 51306, 'EditAnswer did not update body/history/editor.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_EditAnswer @missing, @other, N'x';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51307, 'Missing answer edit should be NotFound.', 1;

    INSERT dbo.Posts (Body, PostTypeId, ParentId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, CommentCount)
        VALUES (N'Other answer', 2, @closed, @answerer, @now, @now, 0, 0, 0);
    SET @a2 = CONVERT(int, SCOPE_IDENTITY());
    DELETE @w; INSERT @w EXEC dbo.Stackish_SetAcceptedAnswer @q, @owner, @a;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @q)
       OR NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @q AND AcceptedAnswerId = @a)
        THROW 51308, 'SetAcceptedAnswer should set the pointer.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_SetAcceptedAnswer @q, @owner, @a;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @q) THROW 51309, 'Repeated acceptance should be NoChange.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_SetAcceptedAnswer @q, @other, @a;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51310, 'Only the question owner can accept.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_SetAcceptedAnswer @q, @owner, @a2;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q) THROW 51311, 'Mismatched answer parent should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_SetAcceptedAnswer @q, @owner, NULL;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @q)
       OR NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @q AND AcceptedAnswerId IS NULL)
        THROW 51312, 'NULL acceptance should clear the pointer.', 1;
    UPDATE dbo.Posts SET AcceptedAnswerId = 0 WHERE Id = @q;
    DELETE @w; INSERT @w EXEC dbo.Stackish_SetAcceptedAnswer @q, @owner, NULL;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @q) THROW 51313, 'Legacy zero acceptance should behave as clear.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Users WHERE Id IN (@owner, @answerer, @other) AND Reputation NOT IN (100,200,300))
       OR EXISTS (SELECT 1 FROM dbo.Votes WHERE PostId IN (@q, @a) AND VoteTypeId = 1)
        THROW 51314, 'Acceptance must not touch votes or reputation.', 1;

    DECLARE @i int = 1;
    WHILE @i <= 3
    BEGIN
        SET @errno = 0;
        BEGIN TRY
            IF @i = 1 EXEC dbo.Stackish_CreateAnswer @q, @answerer, N' ';
            IF @i = 2 EXEC dbo.Stackish_EditAnswer @a, @other, NULL;
            IF @i = 3 EXEC dbo.Stackish_SetAcceptedAnswer @q, @owner, 0;
        END TRY
        BEGIN CATCH
            SET @errno = ERROR_NUMBER();
        END CATCH;
        IF @errno < 50000 THROW 51315, 'Invalid answer input was accepted.', 1;
        SET @i += 1;
    END;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
IF @@TRANCOUNT <> 0 THROW 51399, 'Acceptance checks left an open transaction.', 1;
PRINT 'Component 03 acceptance checks passed; fixtures rolled back.';
