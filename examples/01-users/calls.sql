-- Component 01 call examples. The write calls CHANGE DATA (they create and edit a user):
-- run against a disposable database only. IDs are chosen at run time; nothing is hard-coded
-- except an ID no real user can have.
SET NOCOUNT ON;
DECLARE @missing int = -2147483648;     -- never a valid Users.Id on the import
DECLARE @new TABLE (Outcome varchar(20), EntityId int);
DECLARE @id int, @existing int = (SELECT TOP (1) Id FROM dbo.Users WHERE Id > 0 ORDER BY Reputation DESC, Id);

-- CreateUser: normal call, then note the returned EntityId.
INSERT @new EXEC dbo.Stackish_CreateUser @DisplayName = N'Example User',
    @AboutMe = N'Loves query plans.', @Location = N'Seattle, WA', @WebsiteUrl = N'https://example.com', @Age = 30;
SELECT @id = EntityId FROM @new;
SELECT Outcome, EntityId FROM @new;

-- UpdateUserProfile: normal call (Applied), the same call again (NoChange), and a missing target.
EXEC dbo.Stackish_UpdateUserProfile @UserId = @id, @DisplayName = N'Example User', @AboutMe = N'Now loves statistics.', @Location = NULL;
EXEC dbo.Stackish_UpdateUserProfile @UserId = @id, @DisplayName = N'Example User', @AboutMe = N'Now loves statistics.', @Location = NULL;
EXEC dbo.Stackish_UpdateUserProfile @UserId = @missing, @DisplayName = N'Nobody';

-- RecordUserAccess / RecordProfileView: normal and missing target.
EXEC dbo.Stackish_RecordUserAccess @UserId = @id;
EXEC dbo.Stackish_RecordUserAccess @UserId = @missing;
EXEC dbo.Stackish_RecordProfileView @UserId = @id;
EXEC dbo.Stackish_RecordProfileView @UserId = @missing;

-- GetUserCard: existing user, an imported special user (Id -1), and a missing user (empty set).
EXEC dbo.Stackish_GetUserCard @UserId = @id;
EXEC dbo.Stackish_GetUserCard @UserId = -1;
EXEC dbo.Stackish_GetUserCard @UserId = @missing;

-- ListUsers: each sort, a literal prefix, paging, and a prefix that matches nothing.
EXEC dbo.Stackish_ListUsers;
EXEC dbo.Stackish_ListUsers @Sort = 'newest', @PageSize = 10;
EXEC dbo.Stackish_ListUsers @NamePrefix = N'Jon', @Sort = 'name', @Offset = 0, @PageSize = 25;
EXEC dbo.Stackish_ListUsers @NamePrefix = N'100%_[sure]', @Sort = 'reputation';
