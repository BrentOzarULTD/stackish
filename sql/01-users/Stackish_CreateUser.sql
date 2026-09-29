SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_CreateUser
    @DisplayName nvarchar(max),
    @AboutMe nvarchar(max) = NULL,
    @Location nvarchar(max) = NULL,
    @WebsiteUrl nvarchar(max) = NULL,
    @Age int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate against the full input; nvarchar(max) is only converted to the column size afterwards.
    -- DATALENGTH/2 counts UTF-16 code units, which is how nvarchar(n) limits are measured.
    DECLARE @blank nvarchar(4) = NCHAR(32) + NCHAR(9) + NCHAR(10) + NCHAR(13);

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

    DECLARE @now datetime = GETUTCDATE();

    -- One INSERT is atomic on its own; the identity value comes from the insert.
    INSERT dbo.Users
        (DisplayName, AboutMe, Location, WebsiteUrl, Age,
         Reputation, UpVotes, DownVotes, Views,
         CreationDate, LastAccessDate, EmailHash, AccountId)
    VALUES
        (@DisplayName, @AboutMe, @Location, @WebsiteUrl, @Age,
         1, 0, 0, 0,
         @now, @now, NULL, NULL);

    SELECT CAST('Applied' AS varchar(20)) AS Outcome,
           CAST(SCOPE_IDENTITY() AS int) AS EntityId;
END;
GO
