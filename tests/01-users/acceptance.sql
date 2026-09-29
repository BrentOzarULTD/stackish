-- Component 01 acceptance checks. MUTATES DATA inside a transaction that is always rolled back.
-- Run only on a disposable database, not inside a caller transaction. Identity values consumed
-- by the fixture rows are not returned by the rollback; do not reseed.
-- Concurrent counter increments are covered separately by tests/01-users/concurrency.sh.
SET NOCOUNT ON;
IF @@TRANCOUNT > 0 THROW 51000, 'Run outside an existing transaction.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.procedures WHERE name = N'Stackish_ListUsers')
    THROW 51000, 'Deploy sql/01-users/deploy.sql first.', 1;
IF EXISTS (SELECT 1 FROM dbo.Users WHERE Id IN (0, 2147483647))
    THROW 51000, 'Fixture assumes Users Id 0 and 2147483647 are unused.', 1;

DECLARE @w TABLE (Outcome varchar(20), EntityId int);
DECLARE @card TABLE (UserId int, DisplayName nvarchar(40), Reputation int, Location nvarchar(100),
                     CreationDate datetime, LastAccessDate datetime);
DECLARE @n41 nvarchar(max) = REPLICATE(CAST(N'n' AS nvarchar(max)), 41), @n5000 nvarchar(max) = REPLICATE(CAST(N'n' AS nvarchar(max)), 5000),
        @l100 nvarchar(max) = REPLICATE(CAST(N'l' AS nvarchar(max)), 100), @l101 nvarchar(max) = REPLICATE(CAST(N'l' AS nvarchar(max)), 101),
        @w200 nvarchar(max) = REPLICATE(CAST(N'w' AS nvarchar(max)), 200), @w201 nvarchar(max) = REPLICATE(CAST(N'w' AS nvarchar(max)), 201),
        @x100k nvarchar(max) = REPLICATE(CAST(N'x' AS nvarchar(max)), 100000),
        @ws nvarchar(max) = N'  ' + NCHAR(9) + NCHAR(13) + NCHAR(10);
DECLARE @errno int, @a int, @b int, @c int, @d int, @n int, @s varchar(20), @t nvarchar(max), @start datetime;

BEGIN TRY
    BEGIN TRAN;

    ------------------------------------------------------------------ CreateUser
    SET @start = GETUTCDATE();
    DELETE @w; INSERT @w EXEC dbo.Stackish_CreateUser
        @DisplayName = N'zzStk Zoë 名前 😀', @AboutMe = N'about', @Location = N'Reykjavík', @WebsiteUrl = N'https://example.test', @Age = 33;
    SELECT @a = EntityId FROM @w;
    IF (SELECT COUNT(*) FROM @w WHERE Outcome = 'Applied' AND EntityId > 0) <> 1
        THROW 51001, 'CreateUser should return one Applied row with the new identity.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @a AND DisplayName = N'zzStk Zoë 名前 😀' COLLATE Latin1_General_100_BIN2
                     AND AboutMe = N'about' AND Location = N'Reykjavík' AND WebsiteUrl = N'https://example.test' AND Age = 33
                     AND Reputation = 1 AND UpVotes = 0 AND DownVotes = 0 AND Views = 0
                     AND CreationDate = LastAccessDate AND CreationDate >= DATEADD(SECOND, -2, @start)
                     AND CreationDate <= DATEADD(SECOND, 2, GETUTCDATE())
                     AND EmailHash IS NULL AND AccountId IS NULL)
        THROW 51002, 'CreateUser initial values are wrong.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_CreateUser @DisplayName = N'zzStk Zoë 名前 😀';
    SELECT @b = EntityId FROM @w;
    IF @b = @a OR (SELECT COUNT(*) FROM dbo.Users WHERE DisplayName = N'zzStk Zoë 名前 😀') <> 2
        THROW 51003, 'Duplicate display names must create separate users.', 1;
    IF EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @b AND (AboutMe IS NOT NULL OR Location IS NOT NULL OR WebsiteUrl IS NOT NULL OR Age IS NOT NULL))
        THROW 51004, 'Omitted optional fields should be NULL.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_CreateUser @DisplayName = N'zzStk 40', @AboutMe = @x100k,
        @Location = @l100, @WebsiteUrl = @w200, @Age = 0;
    SELECT @c = EntityId FROM @w;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @c AND DATALENGTH(AboutMe) = 200000 AND Age = 0)
        THROW 51005, 'Boundary lengths and Age = 0 should be accepted; AboutMe is unbounded.', 1;

    -- Invalid input: every case must throw >= 50000 and create nothing.
    SELECT @n = COUNT(*) FROM dbo.Users WHERE Id > 0;
    DECLARE @i int = 1;
    WHILE @i <= 8
    BEGIN
        SET @errno = 0;
        BEGIN TRY
            IF @i = 1 EXEC dbo.Stackish_CreateUser @DisplayName = NULL;
            IF @i = 2 EXEC dbo.Stackish_CreateUser @DisplayName = N'';
            IF @i = 3 EXEC dbo.Stackish_CreateUser @DisplayName = @ws;
            IF @i = 4 EXEC dbo.Stackish_CreateUser @DisplayName = @n41;
            IF @i = 5 EXEC dbo.Stackish_CreateUser @DisplayName = N'ok', @Location = @l101;
            IF @i = 6 EXEC dbo.Stackish_CreateUser @DisplayName = N'ok', @WebsiteUrl = @w201;
            IF @i = 7 EXEC dbo.Stackish_CreateUser @DisplayName = N'ok', @Age = -1;
            IF @i = 8 EXEC dbo.Stackish_CreateUser @DisplayName = @n5000;
        END TRY
        BEGIN CATCH
            SET @errno = ERROR_NUMBER();
        END CATCH;
        IF @errno < 50000 THROW 51006, 'CreateUser accepted or mis-reported invalid input.', 1;
        SET @i += 1;
    END;
    IF (SELECT COUNT(*) FROM dbo.Users WHERE Id > 0) <> @n
        THROW 51007, 'Rejected CreateUser calls must not insert rows.', 1;

    ------------------------------------------------------------------ UpdateUserProfile
    -- Give the fixture user distinctive non-editable values to prove they survive updates.
    UPDATE dbo.Users SET Reputation = 777, UpVotes = 5, DownVotes = 6, Views = 42, AccountId = 9,
        EmailHash = N'abc', CreationDate = '20200101', LastAccessDate = '20210202' WHERE Id = @a;

    DELETE @w; INSERT @w EXEC dbo.Stackish_UpdateUserProfile @UserId = @a, @DisplayName = N'zzStk Zoë 名前 😀',
        @AboutMe = N'about', @Location = N'Reykjavík', @WebsiteUrl = N'https://example.test', @Age = 33;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange' AND EntityId = @a) OR (SELECT COUNT(*) FROM @w) <> 1
        THROW 51010, 'Identical profile should be NoChange.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_UpdateUserProfile @UserId = @a, @DisplayName = N'ZZSTK ZOË 名前 😀',
        @AboutMe = N'about', @Location = N'Reykjavík', @WebsiteUrl = N'https://example.test', @Age = 33;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @a)
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @a AND DisplayName = N'ZZSTK ZOË 名前 😀' COLLATE Latin1_General_100_BIN2)
        THROW 51011, 'A case-only change is a change.', 1;

    DELETE @w; INSERT @w EXEC dbo.Stackish_UpdateUserProfile @UserId = @a, @DisplayName = N'ZZSTK ZOË 名前 😀',
        @AboutMe = N'about ', @Location = N'Reykjavík', @WebsiteUrl = N'https://example.test', @Age = 33;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied')
       OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @a AND DATALENGTH(AboutMe) = 12)
        THROW 51012, 'A trailing-space-only change is a change.', 1;

    -- NULL clears every optional field; editable name is replaced.
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpdateUserProfile @UserId = @a, @DisplayName = N'zzStk Renamed';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @a)
        THROW 51013, 'Clearing optional fields should be Applied.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @a AND DisplayName = N'zzStk Renamed'
                     AND AboutMe IS NULL AND Location IS NULL AND WebsiteUrl IS NULL AND Age IS NULL)
        THROW 51014, 'Optional fields were not cleared.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @a AND Reputation = 777 AND UpVotes = 5 AND DownVotes = 6 AND Views = 42
                     AND AccountId = 9 AND EmailHash = N'abc' AND CreationDate = '20200101' AND LastAccessDate = '20210202')
        THROW 51015, 'UpdateUserProfile changed a non-editable field.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpdateUserProfile @UserId = @a, @DisplayName = N'zzStk Renamed';
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NoChange')
        THROW 51016, 'Repeating an all-NULL profile should be NoChange.', 1;
    DELETE @w; INSERT @w EXEC dbo.Stackish_UpdateUserProfile @UserId = @a, @DisplayName = N'zzStk Renamed', @Age = 0;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied') OR NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @a AND Age = 0)
        THROW 51017, 'Age NULL -> 0 is a change.', 1;

    -- Invalid update input, and no partial change.
    SET @i = 1;
    WHILE @i <= 5
    BEGIN
        SET @errno = 0;
        BEGIN TRY
            IF @i = 1 EXEC dbo.Stackish_UpdateUserProfile @UserId = @a, @DisplayName = N'   ';
            IF @i = 2 EXEC dbo.Stackish_UpdateUserProfile @UserId = @a, @DisplayName = @n41;
            IF @i = 3 EXEC dbo.Stackish_UpdateUserProfile @UserId = @a, @DisplayName = N'x', @Age = -5;
            IF @i = 4 EXEC dbo.Stackish_UpdateUserProfile @UserId = @a, @DisplayName = N'x', @Location = @l101;
            IF @i = 5 EXEC dbo.Stackish_UpdateUserProfile @UserId = NULL, @DisplayName = N'x';
        END TRY
        BEGIN CATCH
            SET @errno = ERROR_NUMBER();
        END CATCH;
        IF @errno < 50000 THROW 51018, 'UpdateUserProfile accepted invalid input.', 1;
        SET @i += 1;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @a AND DisplayName = N'zzStk Renamed' AND Age = 0)
        THROW 51019, 'A rejected update must not change the row.', 1;

    ------------------------------------------------------------------ Missing users (writes)
    SELECT @n = COUNT(*), @d = SUM(CAST(Views AS bigint)) FROM dbo.Users WHERE Id <= 0;
    DECLARE @missing TABLE (Id int);
    INSERT @missing VALUES (2147483647), (0), (-1), (-99);
    DECLARE @mid int;
    DECLARE mc CURSOR LOCAL FAST_FORWARD FOR SELECT Id FROM @missing;
    OPEN mc; FETCH NEXT FROM mc INTO @mid;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DELETE @w; INSERT @w EXEC dbo.Stackish_UpdateUserProfile @UserId = @mid, @DisplayName = N'nobody';
        IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @mid) OR (SELECT COUNT(*) FROM @w) <> 1
            THROW 51021, 'UpdateUserProfile should return NotFound with the requested id.', 1;
        DELETE @w; INSERT @w EXEC dbo.Stackish_RecordUserAccess @UserId = @mid;
        IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @mid) OR (SELECT COUNT(*) FROM @w) <> 1
            THROW 51022, 'RecordUserAccess should return NotFound with the requested id.', 1;
        DELETE @w; INSERT @w EXEC dbo.Stackish_RecordProfileView @UserId = @mid;
        IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'NotFound' AND EntityId = @mid) OR (SELECT COUNT(*) FROM @w) <> 1
            THROW 51023, 'RecordProfileView should return NotFound with the requested id.', 1;
        FETCH NEXT FROM mc INTO @mid;
    END;
    CLOSE mc; DEALLOCATE mc;
    IF (SELECT SUM(CAST(Views AS bigint)) FROM dbo.Users WHERE Id <= 0) <> @d
        THROW 51024, 'NotFound calls must not modify special users.', 1;

    ------------------------------------------------------------------ RecordUserAccess / RecordProfileView
    UPDATE dbo.Users SET LastAccessDate = '20210202', Views = 42 WHERE Id = @a;
    SET @start = GETUTCDATE();
    DELETE @w; INSERT @w EXEC dbo.Stackish_RecordUserAccess @UserId = @a;
    IF NOT EXISTS (SELECT 1 FROM @w WHERE Outcome = 'Applied' AND EntityId = @a) OR (SELECT COUNT(*) FROM @w) <> 1
        THROW 51030, 'RecordUserAccess should be Applied.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @a AND LastAccessDate BETWEEN DATEADD(SECOND,-2,@start) AND DATEADD(SECOND,2,GETUTCDATE())
                     AND Views = 42 AND Reputation = 777 AND DisplayName = N'zzStk Renamed')
        THROW 51031, 'RecordUserAccess must set LastAccessDate to now and touch nothing else.', 1;

    UPDATE dbo.Users SET LastAccessDate = '20210202' WHERE Id = @a;
    DELETE @w; INSERT @w EXEC dbo.Stackish_RecordProfileView @UserId = @a;
    INSERT @w EXEC dbo.Stackish_RecordProfileView @UserId = @a;
    INSERT @w EXEC dbo.Stackish_RecordProfileView @UserId = @a;
    IF (SELECT COUNT(*) FROM @w WHERE Outcome = 'Applied' AND EntityId = @a) <> 3
        THROW 51032, 'RecordProfileView should be Applied each time.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @a AND Views = 45 AND LastAccessDate = '20210202')
        THROW 51033, 'RecordProfileView must add exactly 1 per call and leave LastAccessDate alone.', 1;

    ------------------------------------------------------------------ GetUserCard
    DELETE @card; INSERT @card EXEC dbo.Stackish_GetUserCard @UserId = @a;
    IF NOT EXISTS (SELECT 1 FROM @card WHERE UserId = @a AND DisplayName = N'zzStk Renamed' AND Reputation = 777
                     AND Location IS NULL AND CreationDate = '20200101' AND LastAccessDate = '20210202') OR (SELECT COUNT(*) FROM @card) <> 1
        THROW 51040, 'GetUserCard returned the wrong row.', 1;
    DELETE @card; INSERT @card EXEC dbo.Stackish_GetUserCard @UserId = -1;
    IF (SELECT COUNT(*) FROM @card WHERE UserId = -1) <> 1 THROW 51041, 'Imported nonpositive user should be readable.', 1;
    DELETE @card; INSERT @card EXEC dbo.Stackish_GetUserCard @UserId = 2147483647;
    INSERT @card EXEC dbo.Stackish_GetUserCard @UserId = 0;
    INSERT @card EXEC dbo.Stackish_GetUserCard @UserId = NULL;
    IF EXISTS (SELECT 1 FROM @card) THROW 51042, 'Missing user should return an empty result.', 1;

    ------------------------------------------------------------------ ListUsers
    -- Fixture set with a private prefix so imported data cannot interfere.
    DECLARE @u TABLE (Tag varchar(10), Id int);
    INSERT dbo.Users (DisplayName, Reputation, CreationDate, LastAccessDate, UpVotes, DownVotes, Views, Location)
    OUTPUT CASE inserted.DisplayName WHEN N'zzLst beta' THEN 'beta' WHEN N'zzLst Alpha' THEN 'alpha' WHEN N'zzLst gamma' THEN 'gamma'
                                     WHEN N'zzLst%pct' THEN 'pct' WHEN N'zzLst_und' THEN 'und' WHEN N'zzLst[br' THEN 'br'
                                     WHEN N'zzLstXyz' THEN 'xyz' WHEN N'zzLst!bang' THEN 'bang' END, inserted.Id INTO @u
    VALUES (N'zzLst beta',  100, '20200101', '20200101', 0,0,0, N'B'),
           (N'zzLst Alpha', 100, '20200301', '20200301', 0,0,0, NULL),
           (N'zzLst gamma', 900, '20200201', '20200201', 0,0,0, N'G'),
           (N'zzLst%pct',     5, '20190101', '20190101', 0,0,0, NULL),
           (N'zzLst_und',     4, '20190102', '20190102', 0,0,0, NULL),
           (N'zzLst[br',      3, '20190103', '20190103', 0,0,0, NULL),
           (N'zzLstXyz',      2, '20190104', '20190104', 0,0,0, NULL),
           (N'zzLst!bang',    1, '20190105', '20190105', 0,0,0, NULL);
    DECLARE @beta int = (SELECT Id FROM @u WHERE Tag='beta'), @alpha int = (SELECT Id FROM @u WHERE Tag='alpha'), @gamma int = (SELECT Id FROM @u WHERE Tag='gamma');
    DECLARE @order TABLE (Pos int IDENTITY, UserId int, DisplayName nvarchar(40), Reputation int, Location nvarchar(100), CreationDate datetime, LastAccessDate datetime);

    -- reputation: 900 first, tie at 100 broken by Id ascending (beta was inserted before alpha).
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate)
        EXEC dbo.Stackish_ListUsers @NamePrefix = N'zzLst', @Sort = 'reputation';
    IF (SELECT COUNT(*) FROM @order) <> 8 THROW 51050, 'Prefix should match exactly the eight fixtures.', 1;
    IF (SELECT UserId FROM @order WHERE Pos = 1) <> @gamma OR (SELECT UserId FROM @order WHERE Pos = 2) <> @beta OR (SELECT UserId FROM @order WHERE Pos = 3) <> @alpha
       OR EXISTS (SELECT 1 FROM @order o1 JOIN @order o2 ON o2.Pos = o1.Pos + 1 WHERE o1.Reputation < o2.Reputation)
        THROW 51051, 'reputation sort: descending, Id ascending on ties.', 1;
    -- default sort is reputation and the default prefix works
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate) EXEC dbo.Stackish_ListUsers;
    IF (SELECT COUNT(*) FROM @order) <> 30 OR EXISTS (SELECT 1 FROM @order o1 JOIN @order o2 ON o2.Pos = o1.Pos + 1 WHERE o1.Reputation < o2.Reputation)
        THROW 51052, 'Defaults: 30 rows sorted by reputation.', 1;

    -- newest: CreationDate descending
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate)
        EXEC dbo.Stackish_ListUsers @NamePrefix = N'zzLst', @Sort = 'newest';
    IF (SELECT UserId FROM @order WHERE Pos = 1) <> @alpha OR (SELECT UserId FROM @order WHERE Pos = 2) <> @gamma OR (SELECT UserId FROM @order WHERE Pos = 3) <> @beta
       OR EXISTS (SELECT 1 FROM @order o1 JOIN @order o2 ON o2.Pos = o1.Pos + 1 WHERE o1.CreationDate < o2.CreationDate)
        THROW 51053, 'newest sort: CreationDate descending.', 1;

    -- name: DisplayName ascending (case-insensitive collation, so Alpha < beta < gamma)
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate)
        EXEC dbo.Stackish_ListUsers @NamePrefix = N'zzLst', @Sort = 'name';
    IF EXISTS (SELECT 1 FROM @order o1 JOIN @order o2 ON o2.Pos = o1.Pos + 1 WHERE o1.DisplayName > o2.DisplayName COLLATE DATABASE_DEFAULT)
       OR (SELECT Pos FROM @order WHERE UserId = @alpha) > (SELECT Pos FROM @order WHERE UserId = @beta)
       OR (SELECT Pos FROM @order WHERE UserId = @beta) > (SELECT Pos FROM @order WHERE UserId = @gamma)
        THROW 51054, 'name sort: DisplayName ascending.', 1;

    -- paging: offset 1, size 2 of the reputation order = beta, alpha
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate)
        EXEC dbo.Stackish_ListUsers @NamePrefix = N'zzLst', @Sort = 'reputation', @Offset = 1, @PageSize = 2;
    IF (SELECT COUNT(*) FROM @order) <> 2 OR (SELECT UserId FROM @order WHERE Pos = 1) <> @beta OR (SELECT UserId FROM @order WHERE Pos = 2) <> @alpha
        THROW 51055, 'Paging returned the wrong window.', 1;

    -- literal prefixes: %, _, [ and the escape character match only themselves
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate) EXEC dbo.Stackish_ListUsers @NamePrefix = N'zzLst%';
    IF (SELECT COUNT(*) FROM @order) <> 1 OR NOT EXISTS (SELECT 1 FROM @order WHERE DisplayName = N'zzLst%pct') THROW 51056, '% must be literal.', 1;
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate) EXEC dbo.Stackish_ListUsers @NamePrefix = N'zzLst_';
    IF (SELECT COUNT(*) FROM @order) <> 1 OR NOT EXISTS (SELECT 1 FROM @order WHERE DisplayName = N'zzLst_und') THROW 51057, '_ must be literal.', 1;
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate) EXEC dbo.Stackish_ListUsers @NamePrefix = N'zzLst[';
    IF (SELECT COUNT(*) FROM @order) <> 1 OR NOT EXISTS (SELECT 1 FROM @order WHERE DisplayName = N'zzLst[br') THROW 51058, '[ must be literal.', 1;
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate) EXEC dbo.Stackish_ListUsers @NamePrefix = N'zzLst!';
    IF (SELECT COUNT(*) FROM @order) <> 1 OR NOT EXISTS (SELECT 1 FROM @order WHERE DisplayName = N'zzLst!bang') THROW 51059, 'The escape character must be literal.', 1;
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate) EXEC dbo.Stackish_ListUsers @NamePrefix = N'ZZLST X';
    IF EXISTS (SELECT 1 FROM @order) THROW 51060, 'Nonmatching prefix should be empty.', 1;
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate) EXEC dbo.Stackish_ListUsers @NamePrefix = N'zzlstx';
    IF (SELECT COUNT(*) FROM @order) <> 1 THROW 51061, 'Prefix matching follows the database collation (case-insensitive here).', 1;
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate) EXEC dbo.Stackish_ListUsers @NamePrefix = N'';
    IF (SELECT COUNT(*) FROM @order) <> 30 THROW 51062, 'Empty prefix means no filter.', 1;
    DELETE @order; INSERT @order (UserId, DisplayName, Reputation, Location, CreationDate, LastAccessDate) EXEC dbo.Stackish_ListUsers @NamePrefix = N'zzStk Zoë 名';
    IF (SELECT COUNT(*) FROM @order) <> 1 THROW 51063, 'Unicode prefix should match the one remaining Unicode fixture (the other was renamed).', 1;

    -- invalid arguments
    SET @i = 1;
    WHILE @i <= 7
    BEGIN
        SET @errno = 0;
        BEGIN TRY
            IF @i = 1 EXEC dbo.Stackish_ListUsers @Sort = 'bogus';
            IF @i = 2 EXEC dbo.Stackish_ListUsers @Sort = NULL;
            IF @i = 3 EXEC dbo.Stackish_ListUsers @Offset = -1;
            IF @i = 4 EXEC dbo.Stackish_ListUsers @PageSize = 0;
            IF @i = 5 EXEC dbo.Stackish_ListUsers @PageSize = 101;
            IF @i = 6 EXEC dbo.Stackish_ListUsers @PageSize = NULL;
            IF @i = 7 EXEC dbo.Stackish_ListUsers @Offset = NULL;
        END TRY
        BEGIN CATCH
            SET @errno = ERROR_NUMBER();
        END CATCH;
        IF @errno < 50000 THROW 51064, 'ListUsers accepted invalid arguments.', 1;
        SET @i += 1;
    END;

    ROLLBACK;
    PRINT 'Users acceptance checks passed (fixture rows rolled back).';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH;
