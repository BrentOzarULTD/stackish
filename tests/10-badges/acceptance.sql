-- Component 10 acceptance checks. Inserts fixture Users/Badges inside a transaction that is
-- always rolled back. Run only on an authorized disposable database after deploying component 10.
-- The ListBadges calls scan all of Badges; expect several seconds each on the full dump.
SET NOCOUNT ON;
SET XACT_ABORT OFF;
IF @@TRANCOUNT <> 0 THROW 52000, 'Run outside an existing transaction.', 1;
IF OBJECT_ID(N'dbo.Stackish_ListBadges', N'P') IS NULL THROW 52000, 'Deploy component 10 first.', 1;

-- Result order is captured with an identity column. DELETE does not reset it, so checks only
-- use seq for relative order (ORDER BY seq, MIN(seq)), never as an absolute row number.
DECLARE @ub TABLE (seq int IDENTITY, BadgeId int, Name nvarchar(40), AwardedDate datetime);
DECLARE @lb TABLE (seq int IDENTITY, Name nvarchar(40), AwardCount bigint, RecipientCount bigint, FirstAwarded datetime);
DECLARE @br TABLE (seq int IDENTITY, BadgeId int, UserId int, DisplayName nvarchar(40), AwardedDate datetime);
DECLARE @errno int, @got nvarchar(max), @want nvarchar(max);

BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @now datetime = GETUTCDATE(), @u1 int, @u2 int, @ghost int,
            @n1 nvarchar(40) = N'Stackish Ünïcødé 徽章 ✓',
            @n2 nvarchar(40) = N'Stackish_x',
            @n3 nvarchar(40) = N'StackishAx',
            @d1 datetime = '2020-05-05T10:00:00', @d2 datetime = '2012-01-01', @d3 datetime = '2023-03-03';

    IF EXISTS (SELECT 1 FROM dbo.Badges WHERE Name LIKE N'Stackish%') THROW 52001, 'Fixture badge names already exist.', 1;

    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish badge user Ω', @now, @now, 1, 0, 0, 0);
    SET @u1 = CONVERT(int, SCOPE_IDENTITY());
    INSERT dbo.Users (DisplayName, CreationDate, LastAccessDate, Reputation, UpVotes, DownVotes, Views)
        VALUES (N'Stackish badge user 2', @now, @now, 1, 0, 0, 0);
    SET @u2 = CONVERT(int, SCOPE_IDENTITY());
    SET @ghost = @u2 + 1000000;
    IF EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @ghost) THROW 52002, 'Ghost user id unexpectedly exists.', 1;

    -- The dump has orphan Badges whose UserId is above the current Users identity, so new users
    -- can inherit awards. Clear them for the fixture IDs (rolled back with everything else).
    DELETE dbo.Badges WHERE UserId IN (@u1, @u2, @ghost);

    -- n1: u1 twice on the same timestamp (repeat award + tie), u1 once earlier, u2, and a
    -- recipient missing from Users. 5 awards, 3 distinct recipients.
    INSERT dbo.Badges (Name, UserId, Date) VALUES (@n1, @u1, @d1);
    INSERT dbo.Badges (Name, UserId, Date) VALUES (@n1, @u1, @d1);
    INSERT dbo.Badges (Name, UserId, Date) VALUES (@n1, @u1, @d2);
    INSERT dbo.Badges (Name, UserId, Date) VALUES (@n1, @u2, @d1);
    INSERT dbo.Badges (Name, UserId, Date) VALUES (@n1, @ghost, @d3);
    -- n2 and n3 tie on AwardCount so the Name tie-breaker decides their order.
    INSERT dbo.Badges (Name, UserId, Date) VALUES (@n2, @u1, @d1), (@n2, @u2, @d2), (@n3, @u2, @d2), (@n3, @u2, @d3);

    -------------------------------------------------------------------------------------------
    -- GetUserBadges: every award row, Date desc then BadgeId desc.
    DELETE @ub; INSERT @ub (BadgeId, Name, AwardedDate) EXEC dbo.Stackish_GetUserBadges @u1;
    SELECT @got = STRING_AGG(CONVERT(nvarchar(max), CONCAT(BadgeId, N':', Name, N':', CONVERT(char(19), AwardedDate, 126))), N'|')
                  WITHIN GROUP (ORDER BY seq) FROM @ub;
    SELECT @want = STRING_AGG(CONVERT(nvarchar(max), CONCAT(Id, N':', Name, N':', CONVERT(char(19), Date, 126))), N'|')
                   WITHIN GROUP (ORDER BY Date DESC, Id DESC)
    FROM dbo.Badges WHERE UserId = @u1;
    IF @got IS NULL OR @got COLLATE Latin1_General_100_BIN2 <> @want OR (SELECT COUNT(*) FROM @ub) <> 4
        THROW 52010, 'GetUserBadges returned the wrong rows or order.', 1;
    IF (SELECT COUNT(*) FROM @ub WHERE Name = @n1 COLLATE Latin1_General_100_BIN2 AND AwardedDate = @d1) <> 2
        THROW 52011, 'GetUserBadges collapsed a repeated award.', 1;

    DELETE @ub; INSERT @ub (BadgeId, Name, AwardedDate) EXEC dbo.Stackish_GetUserBadges @u1, 1, 2;
    SELECT @got = STRING_AGG(CONVERT(nvarchar(max), BadgeId), N',') WITHIN GROUP (ORDER BY seq) FROM @ub;
    SELECT @want = STRING_AGG(CONVERT(nvarchar(max), Id), N',') WITHIN GROUP (ORDER BY Date DESC, Id DESC)
    FROM (SELECT Id, Date FROM dbo.Badges WHERE UserId = @u1 ORDER BY Date DESC, Id DESC OFFSET 1 ROWS FETCH NEXT 2 ROWS ONLY) x;
    IF @got IS DISTINCT FROM @want THROW 52012, 'GetUserBadges paging wrong.', 1;

    DELETE @ub; INSERT @ub (BadgeId, Name, AwardedDate) EXEC dbo.Stackish_GetUserBadges @ghost;
    IF EXISTS (SELECT 1 FROM @ub) THROW 52013, 'GetUserBadges should be empty for a user missing from Users.', 1;
    DELETE @ub; INSERT @ub (BadgeId, Name, AwardedDate) EXEC dbo.Stackish_GetUserBadges 2147483647;
    IF EXISTS (SELECT 1 FROM @ub) THROW 52014, 'GetUserBadges should be empty for a missing user.', 1;
    DELETE @ub; INSERT @ub (BadgeId, Name, AwardedDate) EXEC dbo.Stackish_GetUserBadges NULL;
    IF EXISTS (SELECT 1 FROM @ub) THROW 52015, 'GetUserBadges should be empty for NULL.', 1;

    -------------------------------------------------------------------------------------------
    -- ListBadges: award count vs distinct recipients, missing users counted, Unicode name intact.
    DELETE @lb; INSERT @lb (Name, AwardCount, RecipientCount, FirstAwarded) EXEC dbo.Stackish_ListBadges N'Stackish Ü';
    IF (SELECT COUNT(*) FROM @lb) <> 1
       OR NOT EXISTS (SELECT 1 FROM @lb WHERE Name = @n1 COLLATE Latin1_General_100_BIN2
                                         AND AwardCount = 5 AND RecipientCount = 3 AND FirstAwarded = @d2)
        THROW 52020, 'ListBadges aggregate for the Unicode badge is wrong.', 1;

    -- Prefix is literal: '_' must not act as a wildcard, and a trailing space is significant.
    DELETE @lb; INSERT @lb (Name, AwardCount, RecipientCount, FirstAwarded) EXEC dbo.Stackish_ListBadges N'Stackish_';
    IF (SELECT COUNT(*) FROM @lb) <> 1
       OR NOT EXISTS (SELECT 1 FROM @lb WHERE Name = @n2 AND AwardCount = 2 AND RecipientCount = 2 AND FirstAwarded = @d2)
        THROW 52021, 'ListBadges treated _ as a wildcard.', 1;
    DELETE @lb; INSERT @lb (Name, AwardCount, RecipientCount, FirstAwarded) EXEC dbo.Stackish_ListBadges N'Stackish ';
    IF (SELECT COUNT(*) FROM @lb) <> 1 OR NOT EXISTS (SELECT 1 FROM @lb WHERE Name = @n1)
        THROW 52022, 'ListBadges ignored a trailing space in the prefix.', 1;
    DELETE @lb; INSERT @lb (Name, AwardCount, RecipientCount, FirstAwarded) EXEC dbo.Stackish_ListBadges N'%tackish';
    IF EXISTS (SELECT 1 FROM @lb WHERE Name LIKE N'Stackish%') THROW 52023, 'ListBadges treated % as a wildcard.', 1;
    DELETE @lb; INSERT @lb (Name, AwardCount, RecipientCount, FirstAwarded) EXEC dbo.Stackish_ListBadges N'[S]tackish';
    IF EXISTS (SELECT 1 FROM @lb) THROW 52024, 'ListBadges treated [ as a wildcard.', 1;

    -- Ordering: AwardCount desc, then Name asc (database collation) for the n2/n3 tie.
    DELETE @lb; INSERT @lb (Name, AwardCount, RecipientCount, FirstAwarded) EXEC dbo.Stackish_ListBadges N'Stackish';
    SELECT @got = STRING_AGG(CONVERT(nvarchar(max), CONCAT(Name, N'=', AwardCount, N'/', RecipientCount)), N'|')
                  WITHIN GROUP (ORDER BY seq) FROM @lb;
    SELECT @want = STRING_AGG(CONVERT(nvarchar(max), CONCAT(Name, N'=', c, N'/', r)), N'|') WITHIN GROUP (ORDER BY c DESC, Name ASC)
    FROM (VALUES (@n1, 5, 3), (@n2, 2, 2), (@n3, 2, 1)) v (Name, c, r);
    IF @got IS NULL OR @got COLLATE Latin1_General_100_BIN2 <> @want
        THROW 52025, 'ListBadges order or counts wrong.', 1;
    DELETE @lb; INSERT @lb (Name, AwardCount, RecipientCount, FirstAwarded) EXEC dbo.Stackish_ListBadges N'Stackish', 1, 1;
    IF (SELECT COUNT(*) FROM @lb) <> 1
       OR NOT EXISTS (SELECT 1 FROM @lb WHERE Name = (SELECT TOP (1) v.Name FROM (VALUES (@n2), (@n3)) v (Name) ORDER BY v.Name))
        THROW 52026, 'ListBadges paging wrong.', 1;
    DELETE @lb; INSERT @lb (Name, AwardCount, RecipientCount, FirstAwarded) EXEC dbo.Stackish_ListBadges N'Stackish-no-such-badge';
    IF EXISTS (SELECT 1 FROM @lb) THROW 52027, 'ListBadges should be empty for an unmatched prefix.', 1;

    -- NULL and empty prefixes both mean all badges; the top of the list must be sorted.
    DELETE @lb; INSERT @lb (Name, AwardCount, RecipientCount, FirstAwarded) EXEC dbo.Stackish_ListBadges NULL, 0, 10;
    IF (SELECT COUNT(*) FROM @lb) <> 10
       OR EXISTS (SELECT 1 FROM (SELECT AwardCount, LAG(AwardCount) OVER (ORDER BY seq) AS prev FROM @lb) x WHERE x.AwardCount > x.prev)
       OR EXISTS (SELECT 1 FROM @lb WHERE RecipientCount > AwardCount OR RecipientCount < 1)
        THROW 52028, 'ListBadges(NULL) should return a sorted full page.', 1;
    SELECT @want = STRING_AGG(Name, N'|') WITHIN GROUP (ORDER BY seq) FROM @lb;
    DELETE @lb; INSERT @lb (Name, AwardCount, RecipientCount, FirstAwarded) EXEC dbo.Stackish_ListBadges N'', 0, 10;
    SELECT @got = STRING_AGG(Name, N'|') WITHIN GROUP (ORDER BY seq) FROM @lb;
    IF @got IS NULL OR @got <> @want THROW 52029, 'Empty prefix should match NULL prefix.', 1;

    -------------------------------------------------------------------------------------------
    -- GetBadgeRecipients: one row per award, latest first, missing users kept with NULL names.
    DELETE @br; INSERT @br (BadgeId, UserId, DisplayName, AwardedDate) EXEC dbo.Stackish_GetBadgeRecipients @n1;
    SELECT @got = STRING_AGG(CONVERT(nvarchar(max), CONCAT(BadgeId, N':', UserId, N':', ISNULL(DisplayName, N'<null>'))), N'|')
                  WITHIN GROUP (ORDER BY seq) FROM @br;
    SELECT @want = STRING_AGG(CONVERT(nvarchar(max), CONCAT(b.Id, N':', b.UserId, N':', ISNULL(u.DisplayName, N'<null>'))), N'|')
                   WITHIN GROUP (ORDER BY b.Date DESC, b.Id DESC)
    FROM dbo.Badges b LEFT JOIN dbo.Users u ON u.Id = b.UserId
    WHERE b.Name = @n1 COLLATE Latin1_General_100_BIN2;
    IF @got IS NULL OR @got COLLATE Latin1_General_100_BIN2 <> @want OR (SELECT COUNT(*) FROM @br) <> 5
        THROW 52030, 'GetBadgeRecipients rows or order wrong.', 1;
    IF NOT EXISTS (SELECT 1 FROM @br b WHERE b.UserId = @ghost AND b.DisplayName IS NULL AND b.AwardedDate = @d3
                                         AND b.seq = (SELECT MIN(seq) FROM @br))
       OR NOT EXISTS (SELECT 1 FROM @br WHERE UserId = @u1 AND DisplayName = N'Stackish badge user Ω' COLLATE Latin1_General_100_BIN2)
        THROW 52031, 'GetBadgeRecipients lost a missing recipient or a Unicode display name.', 1;
    IF (SELECT COUNT(*) FROM @br WHERE UserId = @u1) <> 3 OR (SELECT COUNT(DISTINCT UserId) FROM @br) <> 3
        THROW 52032, 'GetBadgeRecipients should list repeated awards separately.', 1;

    DELETE @br; INSERT @br (BadgeId, UserId, DisplayName, AwardedDate) EXEC dbo.Stackish_GetBadgeRecipients @n1, 4, 30;
    IF (SELECT COUNT(*) FROM @br) <> 1 OR NOT EXISTS (SELECT 1 FROM @br WHERE UserId = @u1 AND AwardedDate = @d2)
        THROW 52033, 'GetBadgeRecipients paging wrong.', 1;
    DELETE @br; INSERT @br (BadgeId, UserId, DisplayName, AwardedDate) EXEC dbo.Stackish_GetBadgeRecipients N'Stackish-no-such-badge';
    IF EXISTS (SELECT 1 FROM @br) THROW 52034, 'GetBadgeRecipients should be empty for a missing badge.', 1;

    -------------------------------------------------------------------------------------------
    -- Invalid arguments raise >= 50000.
    DECLARE @i int = 1, @ws nvarchar(40) = NCHAR(9) + NCHAR(13) + NCHAR(10) + N' ';
    WHILE @i <= 10
    BEGIN
        SET @errno = 0;
        BEGIN TRY
            IF @i = 1 EXEC dbo.Stackish_GetUserBadges @u1, -1, 30;
            IF @i = 2 EXEC dbo.Stackish_GetUserBadges @u1, 0, 0;
            IF @i = 3 EXEC dbo.Stackish_GetUserBadges @u1, 0, 101;
            IF @i = 4 EXEC dbo.Stackish_ListBadges NULL, NULL, 30;
            IF @i = 5 EXEC dbo.Stackish_ListBadges NULL, 0, NULL;
            IF @i = 6 EXEC dbo.Stackish_GetBadgeRecipients NULL;
            IF @i = 7 EXEC dbo.Stackish_GetBadgeRecipients N'   ';
            IF @i = 8 EXEC dbo.Stackish_GetBadgeRecipients @n1, -5, 30;
            IF @i = 9 EXEC dbo.Stackish_GetBadgeRecipients @n1, 0, 1000;
            IF @i = 10 EXEC dbo.Stackish_GetBadgeRecipients @ws;
        END TRY
        BEGIN CATCH
            SET @errno = ERROR_NUMBER();
        END CATCH;
        IF @errno < 50000 THROW 52040, 'Invalid badge argument was accepted.', 1;
        SET @i += 1;
    END;

    -------------------------------------------------------------------------------------------
    -- Declared result shapes.
    IF (SELECT STRING_AGG(CONCAT(name, ' ', system_type_name), ', ') WITHIN GROUP (ORDER BY column_ordinal)
        FROM sys.dm_exec_describe_first_result_set(N'EXEC dbo.Stackish_GetUserBadges 1', NULL, 0))
       IS DISTINCT FROM 'BadgeId int, Name nvarchar(40), AwardedDate datetime'
       OR (SELECT STRING_AGG(CONCAT(name, ' ', system_type_name), ', ') WITHIN GROUP (ORDER BY column_ordinal)
           FROM sys.dm_exec_describe_first_result_set(N'EXEC dbo.Stackish_ListBadges', NULL, 0))
       IS DISTINCT FROM 'Name nvarchar(40), AwardCount bigint, RecipientCount bigint, FirstAwarded datetime'
       OR (SELECT STRING_AGG(CONCAT(name, ' ', system_type_name), ', ') WITHIN GROUP (ORDER BY column_ordinal)
           FROM sys.dm_exec_describe_first_result_set(N'EXEC dbo.Stackish_GetBadgeRecipients N''x''', NULL, 0))
       IS DISTINCT FROM 'BadgeId int, UserId int, DisplayName nvarchar(40), AwardedDate datetime'
        THROW 52050, 'Badge result shapes changed.', 1;

    IF @@TRANCOUNT <> 1 THROW 52051, 'A read procedure changed the transaction count.', 1;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
IF @@TRANCOUNT <> 0 THROW 52099, 'Acceptance checks left an open transaction.', 1;
PRINT 'Component 10 acceptance checks passed; fixtures rolled back.';
