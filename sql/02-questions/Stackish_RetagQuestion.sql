SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_RetagQuestion
    @QuestionId int,
    @EditorUserId int,
    @Tags nvarchar(max),
    @EditSummary nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @blank nvarchar(4) = NCHAR(32) + NCHAR(9) + NCHAR(10) + NCHAR(13);
    IF @Tags IS NULL OR TRIM(@blank FROM @Tags) = N'' THROW 50241, 'At least one tag is required.', 1;
    IF DATALENGTH(@Tags) / 2 > 150 THROW 50242, 'Tags cannot exceed 150 characters.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.Users WHERE Id = @EditorUserId AND Id > 0)
    BEGIN
        SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
        RETURN;
    END;

    DECLARE @rawTags TABLE (TagName nvarchar(150) COLLATE database_default NOT NULL, Position int IDENTITY(1,1));
    DECLARE @p int = 1, @close int, @token nvarchar(150), @len int = DATALENGTH(@Tags) / 2;
    WHILE @p <= @len
    BEGIN
        IF SUBSTRING(@Tags, @p, 1) <> N'<' THROW 50243, 'Tags must be bracket-delimited.', 1;
        SET @close = CHARINDEX(N'>', @Tags, @p + 1);
        IF @close = 0 THROW 50243, 'Tags must be bracket-delimited.', 1;
        SET @token = SUBSTRING(@Tags, @p + 1, @close - @p - 1);
        IF @token = N'' OR TRIM(@blank FROM @token) = N'' OR CHARINDEX(N'<', @token) > 0 OR CHARINDEX(N'>', @token) > 0
            THROW 50244, 'Tag tokens must be nonblank and cannot contain brackets.', 1;
        INSERT @rawTags (TagName) VALUES (@token);
        SET @p = @close + 1;
    END;
    IF (SELECT COUNT(*) FROM @rawTags) NOT BETWEEN 1 AND 5 THROW 50245, 'Questions require one to five tags.', 1;
    IF EXISTS (SELECT 1 FROM @rawTags GROUP BY TagName HAVING COUNT(*) > 1) THROW 50246, 'Duplicate tags are not allowed.', 1;

    DECLARE @new TABLE (TagName nvarchar(150) COLLATE database_default PRIMARY KEY);
    INSERT @new (TagName) SELECT TagName FROM dbo.Stackish_SplitTags(CONVERT(nvarchar(150), @Tags));
    IF (SELECT COUNT(*) FROM @new) <> (SELECT COUNT(*) FROM @rawTags) THROW 50247, 'Tag input is not valid.', 1;
    IF EXISTS
    (
        SELECT 1
        FROM @new n
        OUTER APPLY (SELECT COUNT(*) AS MatchCount FROM dbo.Tags t WHERE t.TagName = n.TagName) m
        WHERE m.MatchCount <> 1
    )
    BEGIN
        SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
        RETURN;
    END;

    DECLARE @normalized nvarchar(max);
    SELECT @normalized = STRING_AGG(CONVERT(nvarchar(max), N'<' + t.TagName + N'>'), N'') WITHIN GROUP (ORDER BY t.TagName)
    FROM @new n
    JOIN dbo.Tags t ON t.TagName = n.TagName;
    IF DATALENGTH(@normalized) / 2 > 150 THROW 50249, 'Normalized tags cannot exceed 150 characters.', 1;

    SET XACT_ABORT ON;
    DECLARE @oldTags nvarchar(150), @found bit = 0, @now datetime = GETUTCDATE(), @rev uniqueidentifier = NEWID(), @lockResult int;
    DECLARE @lockResource nvarchar(255) = CONCAT(N'Stackish_RetagQuestion:', @QuestionId);
    DECLARE @old TABLE (TagName nvarchar(150) COLLATE database_default PRIMARY KEY);
    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC @lockResult = sys.sp_getapplock @Resource = @lockResource,
            @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @lockResult < 0 THROW 50250, 'Could not acquire retag lock.', 1;

        SELECT @oldTags = Tags, @found = 1
        FROM dbo.Posts WITH (UPDLOCK, HOLDLOCK)
        WHERE Id = @QuestionId AND PostTypeId = 1;
        IF @found = 0
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @QuestionId)
                SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
            ELSE
                SELECT CAST('NotFound' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
            COMMIT TRANSACTION;
            RETURN;
        END;

        INSERT @old (TagName) SELECT TagName FROM dbo.Stackish_SplitTags(@oldTags);
        IF NOT EXISTS (SELECT TagName FROM @new EXCEPT SELECT TagName FROM @old)
           AND NOT EXISTS (SELECT TagName FROM @old EXCEPT SELECT TagName FROM @new)
        BEGIN
            COMMIT TRANSACTION;
            SELECT CAST('NoChange' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
            RETURN;
        END;

        UPDATE dbo.Posts
        SET Tags = CONVERT(nvarchar(150), @normalized),
            LastEditDate = @now,
            LastActivityDate = @now,
            LastEditorUserId = @EditorUserId,
            LastEditorDisplayName = NULL
        WHERE Id = @QuestionId;

        UPDATE t
        SET [Count] = CASE WHEN c.Delta > 0 THEN t.[Count] + 1
                           WHEN t.[Count] > 0 THEN t.[Count] - 1
                           ELSE 0
                      END
        FROM dbo.Tags t
        JOIN
        (
            SELECT TagName, -1 AS Delta FROM (SELECT TagName FROM @old EXCEPT SELECT TagName FROM @new) r
            UNION ALL
            SELECT TagName, 1 AS Delta FROM (SELECT TagName FROM @new EXCEPT SELECT TagName FROM @old) a
        ) c ON c.TagName = t.TagName;

        INSERT dbo.PostHistory (PostHistoryTypeId, PostId, RevisionGUID, CreationDate, UserId, UserDisplayName, Comment, Text)
        VALUES (6, @QuestionId, @rev, @now, @EditorUserId, NULL, @EditSummary, @normalized);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;

    SELECT CAST('Applied' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
END;
GO
