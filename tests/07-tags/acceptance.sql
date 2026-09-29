-- Run only on an authorized disposable copy, after deploying step 1.
-- Fixtures are rolled back on success or failure. Identity allocations are NOT rolled back.
SET NOCOUNT ON;
IF @@TRANCOUNT <> 0 THROW 51000, 'Run these checks without an existing transaction.', 1;
SET XACT_ABORT ON;

-- Parser checks have no data dependencies.
IF EXISTS (SELECT 1 FROM dbo.Stackish_SplitTags(N'<' + NCHAR(9) + NCHAR(10) + NCHAR(13) + N' >'))
    THROW 51000, 'Whitespace-only tokens must be discarded.', 1;
IF EXISTS (SELECT 1 FROM dbo.Stackish_SplitTags(NULL)) OR EXISTS (SELECT 1 FROM dbo.Stackish_SplitTags(N''))
    THROW 51000, 'NULL and empty tag strings must produce no rows.', 1;
DECLARE @parsed TABLE (TagName nvarchar(150));
INSERT @parsed SELECT TagName FROM dbo.Stackish_SplitTags(N'<java><javascript><c++><c#><.net><日本語><java>');
IF (SELECT COUNT(*) FROM @parsed) <> 6
    THROW 51000, 'Parser lost or duplicated valid tags.', 1;
IF EXISTS (SELECT v.TagName FROM (VALUES(N'java'),(N'javascript'),(N'c++'),(N'c#'),(N'.net'),(N'日本語')) v(TagName)
           EXCEPT SELECT TagName FROM @parsed)
    THROW 51000, 'Parser changed a tag token.', 1;
IF EXISTS (SELECT 1 FROM dbo.Stackish_SplitTags(N'noise><><good><bad<nested><unfinished') WHERE TagName <> N'good')
   OR NOT EXISTS (SELECT 1 FROM dbo.Stackish_SplitTags(N'noise><><good><bad<nested><unfinished') WHERE TagName = N'good')
    THROW 51000, 'Parser should keep only closed nonempty fragments beginning with one opening bracket.', 1;
IF (SELECT COUNT(*) FROM dbo.Stackish_SplitTags(N'<java><JAVA>')) <> 1
    THROW 51000, 'Expected the research database case-insensitive collation for deduplication.', 1;
DECLARE @longToken nvarchar(150) = N'<' + REPLICATE(N'x', 148) + N'>';
IF NOT EXISTS (SELECT 1 FROM dbo.Stackish_SplitTags(@longToken) WHERE DATALENGTH(TagName) = 296)
    THROW 51000, 'Parser failed the 150-character input boundary.', 1;

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @root nvarchar(80) = N'stackish-test-' + CONVERT(nvarchar(36), NEWID());
    DECLARE @tag nvarchar(150) = @root + N'-main', @neighbor nvarchar(150) = @root + N'-main-extra';
    DECLARE @now datetime = GETUTCDATE(), @u1 int, @u2 int, @u3 int;
    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish fixture one', @now, @now, 1, 0, 0, 0);
    SET @u1 = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish fixture two', @now, @now, 1, 0, 0, 0);
    SET @u2 = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish fixture three', @now, @now, 1, 0, 0, 0);
    SET @u3 = CONVERT(int, SCOPE_IDENTITY());

    DECLARE @excerpt int, @wiki int, @q int, @other int;
    INSERT dbo.Posts (Body, PostTypeId, CreationDate, LastActivityDate, Score, ViewCount)
        VALUES (N'Unicode excerpt 日本語', 4, @now, @now, 0, 0);
    SET @excerpt = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, PostTypeId, CreationDate, LastActivityDate, Score, ViewCount)
        VALUES (N'Fixture wiki', 5, @now, @now, 0, 0);
    SET @wiki = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, Title, Tags, PostTypeId, CreationDate, LastActivityDate, Score, ViewCount, OwnerUserId)
        VALUES (N'Question', N'Fixture question', N'<' + @tag + N'>', 1, @now, @now, 0, 0, @u1);
    SET @q = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, Title, Tags, PostTypeId, CreationDate, LastActivityDate, Score, ViewCount, OwnerUserId)
        VALUES (N'Neighbor', N'Fixture neighbor', N'<' + @neighbor + N'>', 1, @now, @now, 0, 0, @u1);
    SET @other = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Posts (Body, PostTypeId, ParentId, OwnerUserId, Score, CreationDate, LastActivityDate, ViewCount)
        VALUES (N'a',2,@q,@u1,2000000000,@now,@now,0), (N'b',2,@q,@u1,2000000000,@now,@now,0),
               (N'c',2,@q,@u2,10,@now,@now,0), (N'd',2,@q,@u2,10,@now,@now,0),
               (N'e',2,@q,@u3,10,@now,@now,0), (N'f',2,@q,@u3,10,@now,@now,0),
               (N'no owner',2,@q,NULL,100,@now,@now,0), (N'zero owner',2,@q,0,100,@now,@now,0),
               (N'system owner',2,@q,-1,100,@now,@now,0),
               (N'wrong type',4,@q,@u3,100,@now,@now,0),
               (N'neighbor answer',2,@other,@u3,1000,@now,@now,0);
    DECLARE @missingId int = 2147483647;
    IF EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @missingId) OR EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @missingId)
        THROW 51000, 'Fixture missing-ID assumption does not hold on this database.', 1;
    INSERT dbo.Posts (Body, PostTypeId, ParentId, OwnerUserId, Score, CreationDate, LastActivityDate, ViewCount)
        VALUES (N'missing owner',2,@q,@missingId,100,@now,@now,0);

    INSERT dbo.Tags (TagName, [Count], ExcerptPostId, WikiPostId)
        VALUES (@tag,123,@excerpt,@wiki), (@neighbor,123,0,0),
               (@root + N'-wrong',123,@q,@excerpt), (@root + N'-missing',123,@missingId,@missingId),
               (@root + N'-%literal',123,0,0), (@root + N'-_literal',123,0,0),
               (@root + N'-[literal',123,0,0), (@root + N'-~literal',123,0,0),
               (@root + N'-日本語',123,0,0);

    DECLARE @list TABLE (Position int IDENTITY, TagId int, TagName nvarchar(150), QuestionCount int, Excerpt nvarchar(max));
    INSERT @list (TagId,TagName,QuestionCount,Excerpt)
        EXEC dbo.Stackish_ListTags @NamePrefix=@root, @Sort='popular', @PageSize=100;
    IF (SELECT COUNT(*) FROM @list) <> 9 OR EXISTS (SELECT 1 FROM @list WHERE QuestionCount <> 123)
        THROW 51000, 'ListTags should return every fixture and its stored count.', 1;
    IF EXISTS (SELECT 1 FROM @list a JOIN @list b ON b.Position=a.Position+1 WHERE a.TagId>b.TagId)
        THROW 51000, 'Popular ties must sort by TagId ascending.', 1;
    IF NOT EXISTS (SELECT 1 FROM @list WHERE TagName=@tag AND Excerpt=N'Unicode excerpt 日本語')
       OR EXISTS (SELECT 1 FROM @list WHERE TagName<>@tag AND Excerpt IS NOT NULL)
        THROW 51000, 'ListTags did not preserve missing/type-mismatched wiki references.', 1;
    DELETE @list;
    INSERT @list (TagId,TagName,QuestionCount,Excerpt)
        EXEC dbo.Stackish_ListTags @NamePrefix=@root, @Sort='name', @PageSize=100;
    IF EXISTS (SELECT 1 FROM @list a JOIN @list b ON b.Position=a.Position+1 WHERE a.TagName>b.TagName)
        THROW 51000, 'Name ordering is incorrect.', 1;
    DELETE @list;
    INSERT @list (TagId,TagName,QuestionCount,Excerpt)
        EXEC dbo.Stackish_ListTags @NamePrefix=@root, @Sort='newest', @PageSize=100;
    IF EXISTS (SELECT 1 FROM @list a JOIN @list b ON b.Position=a.Position+1 WHERE a.TagId<b.TagId)
        THROW 51000, 'Newest ordering is incorrect.', 1;
    DECLARE @expectedSecond int = (SELECT TagId FROM @list ORDER BY Position OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY);
    DELETE @list;
    INSERT @list (TagId,TagName,QuestionCount,Excerpt)
        EXEC dbo.Stackish_ListTags @NamePrefix=@root, @Sort='newest', @Offset=1, @PageSize=1;
    IF (SELECT COUNT(*) FROM @list)<>1 OR NOT EXISTS (SELECT 1 FROM @list WHERE TagId=@expectedSecond)
        THROW 51000, 'ListTags pagination is incorrect.', 1;

    DECLARE @prefix nvarchar(150), @suffix nvarchar(10);
    DECLARE prefixes CURSOR LOCAL FAST_FORWARD FOR SELECT s FROM (VALUES(N'%'),(N'_'),(N'['),(N'~'),(N'日本')) v(s);
    OPEN prefixes;
    FETCH NEXT FROM prefixes INTO @suffix;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @prefix=@root+N'-'+@suffix;
        DELETE @list;
        INSERT @list (TagId,TagName,QuestionCount,Excerpt) EXEC dbo.Stackish_ListTags @NamePrefix=@prefix;
        IF (SELECT COUNT(*) FROM @list)<>1
            THROW 51000, 'Literal or Unicode prefix matching is incorrect.', 1;
        FETCH NEXT FROM prefixes INTO @suffix;
    END;
    CLOSE prefixes;
    DEALLOCATE prefixes;

    DECLARE @detail TABLE (TagId int, TagName nvarchar(150), QuestionCount int, Excerpt nvarchar(max), WikiBody nvarchar(max));
    INSERT @detail EXEC dbo.Stackish_GetTagDetail @TagName=@tag;
    IF (SELECT COUNT(*) FROM @detail)<>1 OR NOT EXISTS (SELECT 1 FROM @detail WHERE QuestionCount=123 AND Excerpt=N'Unicode excerpt 日本語' AND WikiBody=N'Fixture wiki')
        THROW 51000, 'GetTagDetail returned incorrect catalog/wiki data.', 1;
    DELETE @detail;
    INSERT @detail EXEC dbo.Stackish_GetTagDetail @TagName=@neighbor;
    SET @prefix=@root+N'-wrong';
    INSERT @detail EXEC dbo.Stackish_GetTagDetail @TagName=@prefix;
    SET @prefix=@root+N'-missing';
    INSERT @detail EXEC dbo.Stackish_GetTagDetail @TagName=@prefix;
    IF (SELECT COUNT(*) FROM @detail)<>3 OR EXISTS (SELECT 1 FROM @detail WHERE Excerpt IS NOT NULL OR WikiBody IS NOT NULL)
        THROW 51000, 'Zero, dangling and wrong-type wiki pointers must retain tags with NULL bodies.', 1;

    DECLARE @leaders TABLE (Position int IDENTITY, UserId int, DisplayName nvarchar(40), AnswerCount bigint, TotalScore bigint);
    -- Duplicate catalog entries must not multiply the leaderboard.
    INSERT dbo.Tags (TagName,[Count],ExcerptPostId,WikiPostId) VALUES (@tag,999,0,0);
    INSERT @leaders (UserId,DisplayName,AnswerCount,TotalScore)
        EXEC dbo.Stackish_GetTagTopUsers @TagName=@tag;
    IF (SELECT COUNT(*) FROM @leaders)<>3
       OR NOT EXISTS (SELECT 1 FROM @leaders WHERE Position=1 AND UserId=@u1 AND AnswerCount=2 AND TotalScore=4000000000)
       OR NOT EXISTS (SELECT 1 FROM @leaders WHERE Position=2 AND UserId=@u2 AND AnswerCount=2 AND TotalScore=20)
       OR NOT EXISTS (SELECT 1 FROM @leaders WHERE Position=3 AND UserId=@u3 AND AnswerCount=2 AND TotalScore=20)
        THROW 51000, 'Leaderboard membership, bigint aggregate, exclusions or tie ordering is incorrect.', 1;
    DELETE @leaders;
    INSERT @leaders (UserId,DisplayName,AnswerCount,TotalScore)
        EXEC dbo.Stackish_GetTagTopUsers @TagName=@tag, @Offset=1, @PageSize=1;
    IF (SELECT COUNT(*) FROM @leaders)<>1 OR NOT EXISTS (SELECT 1 FROM @leaders WHERE UserId=@u2)
        THROW 51000, 'Leaderboard pagination is incorrect.', 1;

    SET @prefix=@root+N'-absent';
    DELETE @list; DELETE @detail; DELETE @leaders;
    INSERT @list (TagId,TagName,QuestionCount,Excerpt) EXEC dbo.Stackish_ListTags @NamePrefix=@prefix;
    INSERT @detail EXEC dbo.Stackish_GetTagDetail @TagName=@prefix;
    INSERT @leaders (UserId,DisplayName,AnswerCount,TotalScore) EXEC dbo.Stackish_GetTagTopUsers @TagName=@prefix;
    IF EXISTS (SELECT 1 FROM @list) OR EXISTS (SELECT 1 FROM @detail) OR EXISTS (SELECT 1 FROM @leaders)
        THROW 51000, 'Unknown tags/prefixes should produce empty results.', 1;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- Invalid calls are checked outside the fixture transaction because THROW + XACT_ABORT
-- can doom a caller's transaction even when the procedure itself only reads data.
DECLARE @badCalls TABLE (SqlText nvarchar(max), ExpectedError int);
INSERT @badCalls VALUES
(N'EXEC dbo.Stackish_ListTags @Offset=-1',50001),
(N'EXEC dbo.Stackish_ListTags @Offset=NULL',50001),
(N'EXEC dbo.Stackish_ListTags @PageSize=0',50001),
(N'EXEC dbo.Stackish_ListTags @PageSize=101',50001),
(N'EXEC dbo.Stackish_ListTags @PageSize=NULL',50001),
(N'EXEC dbo.Stackish_ListTags @Sort=''invalid''',50002),
(N'EXEC dbo.Stackish_ListTags @Sort=NULL',50002),
(N'EXEC dbo.Stackish_GetTagDetail @TagName=NULL',50003),
(N'DECLARE @blank nvarchar(150)=NCHAR(9)+NCHAR(10)+NCHAR(13); EXEC dbo.Stackish_GetTagDetail @TagName=@blank',50003),
(N'DECLARE @blank nvarchar(150)=NCHAR(9); EXEC dbo.Stackish_GetTagTopUsers @TagName=@blank',50003),
(N'EXEC dbo.Stackish_GetTagDetail @TagName=N''   ''',50003),
(N'EXEC dbo.Stackish_GetTagTopUsers @TagName=N''''',50003),
(N'EXEC dbo.Stackish_GetTagTopUsers @TagName=N''sql'', @Offset=-1',50001),
(N'EXEC dbo.Stackish_GetTagTopUsers @TagName=N''sql'', @PageSize=101',50001);
DECLARE @sql nvarchar(max), @expected int, @actual int;
DECLARE bad_calls CURSOR LOCAL FAST_FORWARD FOR SELECT SqlText,ExpectedError FROM @badCalls;
OPEN bad_calls;
FETCH NEXT FROM bad_calls INTO @sql,@expected;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @actual=NULL;
    BEGIN TRY
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @actual=ERROR_NUMBER();
    END CATCH;
    IF @actual IS NULL OR @actual<>@expected THROW 51000, 'Invalid input did not raise the expected error.', 1;
    FETCH NEXT FROM bad_calls INTO @sql,@expected;
END;
CLOSE bad_calls;
DEALLOCATE bad_calls;
IF @@TRANCOUNT<>0 THROW 51000, 'Acceptance checks left an open transaction.', 1;
PRINT 'Step 1 acceptance checks passed; fixtures rolled back.';
