SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_CreateQuestion
    @UserId int,
    @Title nvarchar(max),
    @Body nvarchar(max),
    @Tags nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @blank nvarchar(4) = NCHAR(32) + NCHAR(9) + NCHAR(10) + NCHAR(13);
    IF @Title IS NULL OR TRIM(@blank FROM @Title) = N'' THROW 50201, 'Title is required and cannot be blank.', 1;
    IF DATALENGTH(@Title) / 2 > 250 THROW 50202, 'Title cannot exceed 250 characters.', 1;
    IF @Body IS NULL OR TRIM(@blank FROM @Body) = N'' THROW 50203, 'Body is required and cannot be blank.', 1;
    IF @Tags IS NULL OR TRIM(@blank FROM @Tags) = N'' THROW 50204, 'At least one tag is required.', 1;
    IF DATALENGTH(@Tags) / 2 > 150 THROW 50205, 'Tags cannot exceed 150 characters.', 1;

    DECLARE @rawTags TABLE (TagName nvarchar(150) COLLATE database_default NOT NULL, Position int IDENTITY(1,1));
    DECLARE @p int = 1, @close int, @token nvarchar(150), @len int = LEN(@Tags);
    WHILE @p <= @len
    BEGIN
        IF SUBSTRING(@Tags, @p, 1) <> N'<' THROW 50206, 'Tags must be bracket-delimited.', 1;
        SET @close = CHARINDEX(N'>', @Tags, @p + 1);
        IF @close = 0 THROW 50206, 'Tags must be bracket-delimited.', 1;
        SET @token = SUBSTRING(@Tags, @p + 1, @close - @p - 1);
        IF @token = N'' OR TRIM(@blank FROM @token) = N'' OR CHARINDEX(N'<', @token) > 0 OR CHARINDEX(N'>', @token) > 0
            THROW 50207, 'Tag tokens must be nonblank and cannot contain brackets.', 1;
        INSERT @rawTags (TagName) VALUES (@token);
        SET @p = @close + 1;
    END;
    IF (SELECT COUNT(*) FROM @rawTags) NOT BETWEEN 1 AND 5 THROW 50208, 'Questions require one to five tags.', 1;
    IF EXISTS (SELECT 1 FROM @rawTags GROUP BY TagName HAVING COUNT(*) > 1) THROW 50209, 'Duplicate tags are not allowed.', 1;

    DECLARE @parsed TABLE (TagName nvarchar(150) COLLATE database_default PRIMARY KEY);
    INSERT @parsed (TagName) SELECT TagName FROM dbo.Stackish_SplitTags(CONVERT(nvarchar(150), @Tags));
    IF (SELECT COUNT(*) FROM @parsed) <> (SELECT COUNT(*) FROM @rawTags) THROW 50210, 'Tag input is not valid.', 1;
    IF EXISTS
    (
        SELECT 1
        FROM @parsed p
        OUTER APPLY (SELECT COUNT(*) AS MatchCount FROM dbo.Tags t WHERE t.TagName = p.TagName) m
        WHERE m.MatchCount <> 1
    )
    BEGIN
        SELECT CAST('Conflict' AS varchar(20)) AS Outcome, CAST(0 AS int) AS EntityId;
        RETURN;
    END;

    DECLARE @normalized nvarchar(150);
    SELECT @normalized = STRING_AGG(CONVERT(nvarchar(max), N'<' + t.TagName + N'>'), N'') WITHIN GROUP (ORDER BY t.TagName)
    FROM @parsed p
    JOIN dbo.Tags t ON t.TagName = p.TagName;
    IF DATALENGTH(@normalized) / 2 > 150 THROW 50212, 'Normalized tags cannot exceed 150 characters.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @UserId AND Id > 0)
    BEGIN
        SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @UserId AS EntityId;
        RETURN;
    END;

    DECLARE @now datetime = GETUTCDATE(), @postId int, @rev uniqueidentifier = NEWID();
    BEGIN TRY
        BEGIN TRANSACTION;
        INSERT dbo.Posts (AcceptedAnswerId, AnswerCount, Body, ClosedDate, CommentCount, CommunityOwnedDate,
                          CreationDate, FavoriteCount, LastActivityDate, LastEditDate, LastEditorDisplayName,
                          LastEditorUserId, OwnerUserId, ParentId, PostTypeId, Score, Tags, Title, ViewCount)
        VALUES (NULL, 0, @Body, NULL, 0, NULL,
                @now, 0, @now, NULL, NULL,
                NULL, @UserId, NULL, 1, 0, @normalized, CONVERT(nvarchar(250), @Title), 0);
        SET @postId = CONVERT(int, SCOPE_IDENTITY());

        INSERT dbo.PostHistory (PostHistoryTypeId, PostId, RevisionGUID, CreationDate, UserId, UserDisplayName, Comment, Text)
        VALUES (1, @postId, @rev, @now, @UserId, NULL, NULL, @Title),
               (2, @postId, @rev, @now, @UserId, NULL, NULL, @Body),
               (3, @postId, @rev, @now, @UserId, NULL, NULL, @normalized);

        UPDATE t SET [Count] = t.[Count] + 1
        FROM dbo.Tags t
        JOIN @parsed p ON p.TagName = t.TagName;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT CAST('Applied' AS varchar(20)) AS Outcome, @postId AS EntityId;
END;
GO
