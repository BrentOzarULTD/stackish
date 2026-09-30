-- Component 02 acceptance checks. MUTATES DATA inside a transaction that is always rolled back.
-- Run only on an authorized disposable database after deploying tags and component 02.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF @@TRANCOUNT <> 0 THROW 51200, 'Run outside an existing transaction.', 1;
IF OBJECT_ID(N'dbo.Stackish_CreateQuestion', N'P') IS NULL THROW 51200, 'Deploy component 02 first.', 1;

DECLARE @w TABLE (Outcome varchar(20), EntityId int);
DECLARE @bad int, @errno int, @missing int = 2147483647;
DECLARE @longTitle nvarchar(max) = REPLICATE(CAST(N't' AS nvarchar(max)), 251);
DECLARE @longTags nvarchar(max) = N'<' + REPLICATE(CAST(N'x' AS nvarchar(max)), 149) + N'>';

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @now datetime = GETUTCDATE(), @u int, @editor int, @wrong int, @q int;
    DECLARE @root nvarchar(80) = N'stackish-q-' + CONVERT(nvarchar(36), NEWID());
    DECLARE @tagA nvarchar(150) = @root + N'-a', @tagB nvarchar(150) = @root + N'-b', @tagC nvarchar(150) = @root + N'-c';
    DECLARE @tagsAB nvarchar(max) = N'<' + @tagB + N'><' + @tagA + N'>';
    DECLARE @tagsAC nvarchar(max) = N'<' + @tagC + N'><' + @tagA + N'>';
    DECLARE @tagsA nvarchar(max) = N'<' + @tagA + N'>';
    DECLARE @dupTags nvarchar(max) = N'<' + @tagA + N'><' + @tagA + N'>';
    DECLARE @missingTag nvarchar(max) = N'<' + @root + N'-missing>';
    DECLARE @nestedTags nvarchar(max) = N'<' + @tagA + N'><bad<nested>';

    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish question owner', @now, @now, 1, 0, 0, 0),
               (N'Stackish question editor', @now, @now, 1, 0, 0, 0);
    SET @editor = CONVERT(int, SCOPE_IDENTITY());
    SET @u = @editor - 1;

    INSERT dbo.Posts (Body, PostTypeId, CreationDate, LastActivityDate, Score, ViewCount)
        VALUES (N'wrong type', 2, @now, @now, 0, 0);
    SET @wrong = CONVERT(int, SCOPE_IDENTITY());

    INSERT dbo.Tags (TagName, [Count], ExcerptPostId, WikiPostId)
        VALUES (@tagA, 10, 0, 0), (@tagB, 20, 0, 0), (@tagC, 30, 0, 0);

    DELETE @w;
    INSERT @w EXEC dbo.Stackish_CreateQuestion @u, N'Case Sensitive Title', N'Case Sensitive Body', @Tags = @tagsAB;
    SELECT @q = EntityId FROM @w;
    IF (SELECT COUNT(*) FROM @w WHERE Outcome = 'Applied' AND EntityId = @q AND @q > 0) <> 1 THROW 51201, 'CreateQuestion did not return Applied/new id.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @q AND PostTypeId = 1 AND OwnerUserId = @u AND Title = N'Case Sensitive Title' COLLATE Latin1_General_100_BIN2
                   AND Body = N'Case Sensitive Body' COLLATE Latin1_General_100_BIN2 AND Tags = N'<' + @tagA + N'><' + @tagB + N'>'
                   AND Score = 0 AND ViewCount = 0 AND AnswerCount = 0 AND CommentCount = 0 AND FavoriteCount = 0
                   AND ParentId IS NULL AND AcceptedAnswerId IS NULL AND ClosedDate IS NULL)
        THROW 51202, 'CreateQuestion stored incorrect post values.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Tags WHERE TagName = @tagA AND [Count] = 11)
       OR NOT EXISTS (SELECT 1 FROM dbo.Tags WHERE TagName = @tagB AND [Count] = 21)
       OR NOT EXISTS (SELECT 1 FROM dbo.Tags WHERE TagName = @tagC AND [Count] = 30)
        THROW 51203, 'CreateQuestion did not apply tag-count deltas.', 1;
    IF (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId = @q AND PostHistoryTypeId IN (1,2,3)) <> 3
       OR (SELECT COUNT(DISTINCT RevisionGUID) FROM dbo.PostHistory WHERE PostId = @q AND PostHistoryTypeId IN (1,2,3)) <> 1
        THROW 51204, 'CreateQuestion did not write initial history.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_EditQuestion @q, @editor, N'Case Sensitive Title', N'Case Sensitive Body';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @q) OR (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId = @q AND PostHistoryTypeId IN (4,5)) <> 0
        THROW 51205, 'No-op question edit should not write history.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_EditQuestion @q, @editor, N'case sensitive title', N'Case Sensitive Body ', N'case/trailing-space edit';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @q) THROW 51206, 'Changed question edit should be Applied.', 1;
    IF (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId = @q AND PostHistoryTypeId IN (4,5)) <> 2
       OR (SELECT COUNT(DISTINCT RevisionGUID) FROM dbo.PostHistory WHERE PostId = @q AND PostHistoryTypeId IN (4,5)) <> 1
        THROW 51207, 'EditQuestion should write history only for changed fields with one revision.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_RetagQuestion @q, @editor, @tagsAB;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @q) THROW 51208, 'Equivalent retag should be NoChange.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RetagQuestion @q, @editor, @tagsAC, N'swap tags';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @q) THROW 51209, 'Retag should be Applied.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @q AND Tags = N'<' + @tagA + N'><' + @tagC + N'>')
       OR NOT EXISTS (SELECT 1 FROM dbo.Tags WHERE TagName = @tagA AND [Count] = 11)
       OR NOT EXISTS (SELECT 1 FROM dbo.Tags WHERE TagName = @tagB AND [Count] = 20)
       OR NOT EXISTS (SELECT 1 FROM dbo.Tags WHERE TagName = @tagC AND [Count] = 31)
       OR (SELECT COUNT(*) FROM dbo.PostHistory WHERE PostId = @q AND PostHistoryTypeId = 6) <> 1
        THROW 51210, 'RetagQuestion did not apply post/history/tag deltas correctly.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RetagQuestion @q, @editor, @missingTag;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @q)
       OR NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @q AND Tags = N'<' + @tagA + N'><' + @tagC + N'>')
        THROW 51218, 'Unknown retag should be Conflict without changing the post.', 1;

    UPDATE dbo.Posts SET ViewCount = 5 WHERE Id = @q;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RecordQuestionView @q;
    INSERT @w EXEC dbo.Stackish_RecordQuestionView @q;
    IF (SELECT COUNT(*) FROM @w WHERE Outcome = 'Applied' AND EntityId = @q) <> 2
       OR NOT EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @q AND ViewCount = 7)
        THROW 51211, 'RecordQuestionView should increment exactly once per call.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_EditQuestion @missing, @editor, N'x', N'y';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @missing) THROW 51212, 'Missing question edit should be NotFound.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RecordQuestionView @wrong;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = @wrong) THROW 51213, 'Wrong post type should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_CreateQuestion @missing, N'x', N'y', @tagsA;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict') THROW 51214, 'Missing actor should be Conflict.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_CreateQuestion @u, N't', N'b', @missingTag;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Conflict' AND EntityId = 0) THROW 51215, 'Unknown tags should be Conflict.', 1;

    SELECT @bad = COUNT(*) FROM dbo.Posts;
    DECLARE @i int = 1;
    WHILE @i <= 6
    BEGIN
        SET @errno = 0;
        BEGIN TRY
            IF @i = 1 EXEC dbo.Stackish_CreateQuestion @u, NULL, N'b', @tagsA;
            IF @i = 2 EXEC dbo.Stackish_CreateQuestion @u, @longTitle, N'b', @tagsA;
            IF @i = 3 EXEC dbo.Stackish_CreateQuestion @u, N't', N' ', @tagsA;
            IF @i = 4 EXEC dbo.Stackish_CreateQuestion @u, N't', N'b', @dupTags;
            IF @i = 5 EXEC dbo.Stackish_CreateQuestion @u, N't', N'b', @nestedTags;
            IF @i = 6 EXEC dbo.Stackish_CreateQuestion @u, N't', N'b', @longTags;
        END TRY
        BEGIN CATCH
            SET @errno = ERROR_NUMBER();
        END CATCH;
        IF @errno < 50000 THROW 51216, 'Invalid CreateQuestion input was accepted.', 1;
        SET @i += 1;
    END;
    IF (SELECT COUNT(*) FROM dbo.Posts) <> @bad THROW 51217, 'Rejected CreateQuestion call inserted data.', 1;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
IF @@TRANCOUNT <> 0 THROW 51299, 'Acceptance checks left an open transaction.', 1;
PRINT 'Component 02 acceptance checks passed; fixtures rolled back.';
