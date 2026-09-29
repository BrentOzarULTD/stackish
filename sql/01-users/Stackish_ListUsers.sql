SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_ListUsers
    @NamePrefix nvarchar(40) = NULL,
    @Sort varchar(20) = 'reputation',
    @Offset int = 0,
    @PageSize int = 30
AS
BEGIN
    SET NOCOUNT ON;

    IF @Offset IS NULL OR @Offset < 0 OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100
        THROW 50121, 'Offset must be nonnegative and PageSize must be between 1 and 100.', 1;
    IF @Sort IS NULL OR @Sort NOT IN ('reputation', 'newest', 'name')
        THROW 50122, 'User sort must be reputation, newest, or name.', 1;

    -- Literal prefix: escape the LIKE metacharacters and the escape character itself.
    -- NULL or empty means no filter. Matching follows the database collation.
    DECLARE @pattern nvarchar(200) = NULL;
    IF @NamePrefix IS NOT NULL AND DATALENGTH(@NamePrefix) > 0
        SET @pattern = REPLACE(REPLACE(REPLACE(REPLACE(@NamePrefix, N'!', N'!!'), N'%', N'!%'), N'_', N'!_'), N'[', N'![') + N'%';

    -- One statement per sort so each gets its own plan; Id makes every ordering deterministic.
    IF @Sort = 'reputation'
        SELECT u.Id AS UserId, u.DisplayName, u.Reputation, u.Location, u.CreationDate, u.LastAccessDate
          FROM dbo.Users AS u
         WHERE @pattern IS NULL OR u.DisplayName LIKE @pattern ESCAPE N'!'
         ORDER BY u.Reputation DESC, u.Id ASC
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
    ELSE IF @Sort = 'newest'
        SELECT u.Id AS UserId, u.DisplayName, u.Reputation, u.Location, u.CreationDate, u.LastAccessDate
          FROM dbo.Users AS u
         WHERE @pattern IS NULL OR u.DisplayName LIKE @pattern ESCAPE N'!'
         ORDER BY u.CreationDate DESC, u.Id DESC
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
    ELSE
        SELECT u.Id AS UserId, u.DisplayName, u.Reputation, u.Location, u.CreationDate, u.LastAccessDate
          FROM dbo.Users AS u
         WHERE @pattern IS NULL OR u.DisplayName LIKE @pattern ESCAPE N'!'
         ORDER BY u.DisplayName ASC, u.Id ASC
        OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
