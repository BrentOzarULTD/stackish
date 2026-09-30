-- Example calls for component 02. Replace fixture IDs/tag names with values from your disposable database.

DECLARE @write TABLE (Outcome varchar(20), EntityId int);

-- CreateQuestion normal call.
DELETE @write;
INSERT @write EXEC dbo.Stackish_CreateQuestion
    @UserId = 123,
    @Title = N'How do I tune this query plan?',
    @Body = N'I have a reproducible query and plan details here.',
    @Tags = N'<sql-server><query-performance>';
SELECT * FROM @write;

-- CreateQuestion missing/invalid actor example.
DELETE @write;
INSERT @write EXEC dbo.Stackish_CreateQuestion
    @UserId = 2147483647,
    @Title = N'Missing actor example',
    @Body = N'This should not create a question.',
    @Tags = N'<sql-server>';
SELECT * FROM @write;

-- EditQuestion normal call.
DELETE @write;
INSERT @write EXEC dbo.Stackish_EditQuestion
    @QuestionId = 456,
    @EditorUserId = 123,
    @Title = N'How do I tune this query plan with a better index?',
    @Body = N'Updated body text.',
    @EditSummary = N'Clarified the problem.';
SELECT * FROM @write;

-- EditQuestion missing target example.
DELETE @write;
INSERT @write EXEC dbo.Stackish_EditQuestion
    @QuestionId = 2147483647,
    @EditorUserId = 123,
    @Title = N'Missing question',
    @Body = N'No row should be edited.';
SELECT * FROM @write;

-- RetagQuestion normal call.
DELETE @write;
INSERT @write EXEC dbo.Stackish_RetagQuestion
    @QuestionId = 456,
    @EditorUserId = 123,
    @Tags = N'<sql-server><execution-plan>',
    @EditSummary = N'Retagged for plan analysis.';
SELECT * FROM @write;

-- RetagQuestion missing target example.
DELETE @write;
INSERT @write EXEC dbo.Stackish_RetagQuestion
    @QuestionId = 2147483647,
    @EditorUserId = 123,
    @Tags = N'<sql-server>';
SELECT * FROM @write;

-- RecordQuestionView normal call.
DELETE @write;
INSERT @write EXEC dbo.Stackish_RecordQuestionView @QuestionId = 456;
SELECT * FROM @write;

-- RecordQuestionView missing target example.
DELETE @write;
INSERT @write EXEC dbo.Stackish_RecordQuestionView @QuestionId = 2147483647;
SELECT * FROM @write;
