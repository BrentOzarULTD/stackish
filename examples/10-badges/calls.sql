-- Example calls for component 10 (read-only). Placeholder: replace 22656 with a user ID from
-- your database. ListBadges and GetBadgeRecipients scan Badges; expect seconds, not milliseconds.

-- GetUserBadges normal call, then missing user (empty result set).
EXEC dbo.Stackish_GetUserBadges @UserId = 22656, @Offset = 0, @PageSize = 30;
EXEC dbo.Stackish_GetUserBadges @UserId = 2147483647;

-- ListBadges: all badges, a prefix, and a prefix with no match (empty result set).
EXEC dbo.Stackish_ListBadges;
EXEC dbo.Stackish_ListBadges @NamePrefix = N'Nec', @Offset = 0, @PageSize = 10;
EXEC dbo.Stackish_ListBadges @NamePrefix = N'No such badge prefix';

-- GetBadgeRecipients normal call, then missing badge (empty result set).
EXEC dbo.Stackish_GetBadgeRecipients @BadgeName = N'Necromancer', @Offset = 0, @PageSize = 30;
EXEC dbo.Stackish_GetBadgeRecipients @BadgeName = N'No such badge';
