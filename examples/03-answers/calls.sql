-- Example calls for component 03. Replace fixture IDs with values from your disposable database.

DECLARE @write TABLE (Outcome varchar(20), EntityId int);

-- CreateAnswer normal call.
DELETE @write;
INSERT @write EXEC dbo.Stackish_CreateAnswer
    @QuestionId = 456,
    @UserId = 123,
    @Body = N'This is one way to solve it.';
SELECT * FROM @write;

-- CreateAnswer missing target example.
DELETE @write;
INSERT @write EXEC dbo.Stackish_CreateAnswer
    @QuestionId = 2147483647,
    @UserId = 123,
    @Body = N'This should not create an answer.';
SELECT * FROM @write;

-- EditAnswer normal call.
DELETE @write;
INSERT @write EXEC dbo.Stackish_EditAnswer
    @AnswerId = 789,
    @EditorUserId = 123,
    @Body = N'Updated answer text.',
    @EditSummary = N'Added details.';
SELECT * FROM @write;

-- EditAnswer missing target example.
DELETE @write;
INSERT @write EXEC dbo.Stackish_EditAnswer
    @AnswerId = 2147483647,
    @EditorUserId = 123,
    @Body = N'No row should be edited.';
SELECT * FROM @write;

-- SetAcceptedAnswer normal call.
DELETE @write;
INSERT @write EXEC dbo.Stackish_SetAcceptedAnswer
    @QuestionId = 456,
    @UserId = 123,
    @AnswerId = 789;
SELECT * FROM @write;

-- SetAcceptedAnswer missing target example.
DELETE @write;
INSERT @write EXEC dbo.Stackish_SetAcceptedAnswer
    @QuestionId = 2147483647,
    @UserId = 123,
    @AnswerId = NULL;
SELECT * FROM @write;
