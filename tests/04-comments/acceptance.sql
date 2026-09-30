-- Component 04 acceptance checks. MUTATES DATA inside a transaction that is always rolled back.
-- Run only on an authorized disposable database after deploying component 04.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF @@TRANCOUNT <> 0 THROW 51400, 'Run outside an existing transaction.', 1;
IF OBJECT_ID(N'dbo.Stackish_AddComment', N'P') IS NULL THROW 51400, 'Deploy component 04 first.', 1;

DECLARE @w TABLE (Outcome varchar(20), EntityId int);
DECLARE @comments TABLE (CommentId int, PostId int, Text nvarchar(700), Score int, CreationDate datetime, UserId int, DisplayName nvarchar(40));
DECLARE @missing int = 2147483647, @errno int, @longText nvarchar(max) = REPLICATE(CAST(N'c' AS nvarchar(max)), 701);

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @now datetime = GETUTCDATE(), @u int, @other int, @q int, @a int, @wrong int, @c int, @c2 int, @orphan int;
    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish commenter', @now, @now, 1, 0, 0, 0),
               (N'Stackish other commenter', @now, @now, 1, 0, 0, 0);
    SET @other = CONVERT(int, SCOPE_IDENTITY());
    SET @u = @other - 1;
    INSERT dbo.Posts (Body, Title, Tags, PostTypeId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, CommentCount)
        VALUES (N'q', N'q', N'<sql-server>', 1, @u, @now, @now, 0, 0, 7);
    SET @q = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, PostTypeId, ParentId, OwnerUserId, CreationDate, LastActivityDate, Score, ViewCount, CommentCount)
        VALUES (N'a', 2, @q, @other, @now, @now, 0, 0, 3);
    SET @a = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, PostTypeId, CreationDate, LastActivityDate, Score, ViewCount)
        VALUES (N'wrong type', 4, @now, @now, 0, 0);
    SET @wrong = CONVERT(int, SCOPE_IDENTITY());

    DELETE @w; INSERT @w EXEC dbo.Stackish_AddComment @q, @u, N'question comment';
    SELECT @c = EntityId FROM @w;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @c AND @c > 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Comments WHERE Id = @c AND PostId = @q AND UserId = @u AND Text = N'question comment' COLLATE Latin1_General_100_BIN2 AND Score = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @q AND CommentCount = 8)
        THROW 51401, 'AddComment did not insert question comment or increment counter.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_AddComment @a, @u, N'answer comment';
    SELECT @c2 = EntityId FROM @w;
    IF NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @a AND CommentCount = 4) THROW 51402, 'Answer comment counter was not incremented.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_AddComment @wrong, @u, N'wrong type';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @wrong) THROW 51403, 'Wrong post type should reject comments.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_AddComment @missing, @u, N'missing';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51404, 'Missing post should be NotFound.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_EditComment @c, @other, N'foreign edit';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @c) THROW 51405, 'Foreign author edit should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_EditComment @c, @u, N'question comment';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @c) THROW 51406, 'No-op comment edit should be NoChange.', 1;
    UPDATE dbo.Comments SET Score = 42, CreationDate = '20200101' WHERE Id = @c;
    DELETE @w; INSERT @w EXEC dbo.Stackish_EditComment @c, @u, N'question comment edited';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @c)
       OR NOT EXISTS (SELECT 1 FROM dbo.Comments WHERE Id = @c AND Text = N'question comment edited' COLLATE Latin1_General_100_BIN2 AND Score = 42 AND CreationDate = '20200101')
        THROW 51407, 'EditComment should update text only.', 1;

    DELETE @comments; INSERT @comments EXEC dbo.Stackish_GetPostComments @q, 0, 30;
    IF NOT EXISTS (SELECT 1 FROM @comments WHERE CommentId = @c AND UserId = @u AND DisplayName = N'Stackish commenter')
        THROW 51408, 'GetPostComments did not return the expected comment shape.', 1;
    INSERT dbo.Comments (CreationDate, PostId, Score, Text, UserId) VALUES ('20200102', @q, 0, N'missing author', @missing);
    DELETE @comments; INSERT @comments EXEC dbo.Stackish_GetPostComments @q, 0, 30;
    IF NOT EXISTS (SELECT 1 FROM @comments WHERE Text = N'missing author' AND UserId = @missing AND DisplayName IS NULL)
        THROW 51409, 'Missing comment authors should not drop comments.', 1;
    DELETE @comments; INSERT @comments EXEC dbo.Stackish_GetPostComments @missing, 0, 30;
    IF EXISTS (SELECT 1 FROM @comments) THROW 51410, 'Missing posts should return an empty comment result.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_DeleteComment @c, @other;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @c) THROW 51411, 'Foreign author delete should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_DeleteComment @c, @u;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @c)
       OR EXISTS (SELECT 1 FROM dbo.Comments WHERE Id = @c)
       OR NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @q AND CommentCount = 7)
        THROW 51412, 'DeleteComment did not delete once and decrement counter.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_DeleteComment @c, @u;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @c) THROW 51413, 'Repeated delete should be NotFound.', 1;

    INSERT dbo.Comments (CreationDate, PostId, Score, Text, UserId) VALUES (@now, @missing, 0, N'orphan', @u);
    SET @orphan = CONVERT(int, SCOPE_IDENTITY());
    DELETE @w; INSERT @w EXEC dbo.Stackish_DeleteComment @orphan, @u;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @orphan)
       OR EXISTS (SELECT 1 FROM dbo.Comments WHERE Id = @orphan)
        THROW 51414, 'Owned orphan comment should still be deleted.', 1;

    DECLARE @i int = 1;
    WHILE @i <= 5
    BEGIN
        SET @errno = 0;
        BEGIN TRY
            IF @i = 1 EXEC dbo.Stackish_AddComment @q, @u, N' ';
            IF @i = 2 EXEC dbo.Stackish_AddComment @q, @u, @longText;
            IF @i = 3 EXEC dbo.Stackish_EditComment @c2, @u, NULL;
            IF @i = 4 EXEC dbo.Stackish_GetPostComments @q, -1, 30;
            IF @i = 5 EXEC dbo.Stackish_GetPostComments @q, 0, 101;
        END TRY
        BEGIN CATCH
            SET @errno = ERROR_NUMBER();
        END CATCH;
        IF @errno < 50000 THROW 51415, 'Invalid comment input was accepted.', 1;
        SET @i += 1;
    END;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
IF @@TRANCOUNT <> 0 THROW 51499, 'Acceptance checks left an open transaction.', 1;
PRINT 'Component 04 acceptance checks passed; fixtures rolled back.';
