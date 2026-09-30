-- Example calls for component 09. Placeholder IDs: replace 456 and 457 (questions), 123 (acting
-- user) and 1001 (a LinkId returned by AddQuestionLink) with values from your disposable database.

DECLARE @write TABLE (Outcome varchar(20), EntityId int);

-- CloseQuestion normal call, then missing target.
DELETE @write; INSERT @write EXEC dbo.Stackish_CloseQuestion @QuestionId = 456, @UserId = 123, @Reason = N'Needs more focus'; SELECT * FROM @write;
DELETE @write; INSERT @write EXEC dbo.Stackish_CloseQuestion @QuestionId = 2147483647, @UserId = 123, @Reason = N'Needs more focus'; SELECT * FROM @write;

-- ReopenQuestion normal call, then missing target.
DELETE @write; INSERT @write EXEC dbo.Stackish_ReopenQuestion @QuestionId = 456, @UserId = 123; SELECT * FROM @write;
DELETE @write; INSERT @write EXEC dbo.Stackish_ReopenQuestion @QuestionId = 2147483647, @UserId = 123; SELECT * FROM @write;

-- AddQuestionLink normal calls (linked, then duplicate), then missing target.
DELETE @write; INSERT @write EXEC dbo.Stackish_AddQuestionLink @QuestionId = 456, @RelatedQuestionId = 457, @UserId = 123; SELECT * FROM @write;
DELETE @write; INSERT @write EXEC dbo.Stackish_AddQuestionLink @QuestionId = 456, @RelatedQuestionId = 457, @UserId = 123, @LinkTypeId = 3; SELECT * FROM @write;
DELETE @write; INSERT @write EXEC dbo.Stackish_AddQuestionLink @QuestionId = 456, @RelatedQuestionId = 2147483647, @UserId = 123; SELECT * FROM @write;

-- RemoveQuestionLink normal call (use an EntityId returned above), then missing target.
DELETE @write; INSERT @write EXEC dbo.Stackish_RemoveQuestionLink @LinkId = 1001, @UserId = 123; SELECT * FROM @write;
DELETE @write; INSERT @write EXEC dbo.Stackish_RemoveQuestionLink @LinkId = 2147483647, @UserId = 123; SELECT * FROM @write;
