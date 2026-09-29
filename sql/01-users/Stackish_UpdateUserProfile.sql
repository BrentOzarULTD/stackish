SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_UpdateUserProfile
    @UserId int,
    @DisplayName nvarchar(max),
    @AboutMe nvarchar(max) = NULL,
    @Location nvarchar(max) = NULL,
    @WebsiteUrl nvarchar(max) = NULL,
    @Age int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @blank nvarchar(4) = NCHAR(32) + NCHAR(9) + NCHAR(10) + NCHAR(13);

    IF @UserId IS NULL
        THROW 50111, 'UserId is required.', 1;
    IF @DisplayName IS NULL OR TRIM(@blank FROM @DisplayName) = N''
        THROW 50101, 'DisplayName is required and cannot be blank.', 1;
    IF DATALENGTH(@DisplayName) / 2 > 40
        THROW 50102, 'DisplayName cannot exceed 40 characters.', 1;
    IF DATALENGTH(@Location) / 2 > 100
        THROW 50103, 'Location cannot exceed 100 characters.', 1;
    IF DATALENGTH(@WebsiteUrl) / 2 > 200
        THROW 50104, 'WebsiteUrl cannot exceed 200 characters.', 1;
    IF @Age < 0
        THROW 50105, 'Age cannot be negative.', 1;

    -- Imported special users (Id <= 0) are readable but not editable.
    IF @UserId <= 0
    BEGIN
        SELECT CAST('NotFound' AS varchar(20)) AS Outcome, @UserId AS EntityId;
        RETURN;
    END;

    -- The row is only touched when something really differs. The comparison is on raw bytes:
    -- the database collation is case-insensitive and ignores trailing spaces, so a plain <>
    -- would call 'bob' -> 'Bob' or 'a' -> 'a ' a no-op. EXCEPT also treats NULL = NULL.
    UPDATE u
       SET DisplayName = @DisplayName,
           AboutMe     = @AboutMe,
           Location    = @Location,
           WebsiteUrl  = @WebsiteUrl,
           Age         = @Age
      FROM dbo.Users AS u
     WHERE u.Id = @UserId
       AND EXISTS (SELECT CAST(u.DisplayName AS varbinary(max)), CAST(u.AboutMe AS varbinary(max)),
                          CAST(u.Location AS varbinary(max)), CAST(u.WebsiteUrl AS varbinary(max)), u.Age
                   EXCEPT
                   SELECT CAST(@DisplayName AS varbinary(max)), CAST(@AboutMe AS varbinary(max)),
                          CAST(@Location AS varbinary(max)), CAST(@WebsiteUrl AS varbinary(max)), @Age);

    IF @@ROWCOUNT = 1
        SELECT CAST('Applied' AS varchar(20)) AS Outcome, @UserId AS EntityId;
    ELSE IF EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId)
        SELECT CAST('NoChange' AS varchar(20)) AS Outcome, @UserId AS EntityId;
    ELSE
        SELECT CAST('NotFound' AS varchar(20)) AS Outcome, @UserId AS EntityId;
END;
GO
