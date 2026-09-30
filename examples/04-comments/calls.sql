-- Example calls for component 04. Replace fixture IDs with values from your disposable database.

DECLARE @write TABLE (Outcome varchar(20), EntityId int);

-- AddComment normal call.
DELETE @write;
INSERT @write EXEC dbo.Stackish_AddComment
    @PostId = 456,
    @UserId = 123,
    @Text = N'Can you include the execution plan?';
SELECT * FROM @write;

-- AddComment missing target example.
DELETE @write;
INSERT @write EXEC dbo.Stackish_AddComment
    @PostId = 2147483647,
    @UserId = 123,
    @Text = N'This should not create a comment.';
SELECT * FROM @write;

-- EditComment normal call.
DELETE @write;
INSERT @write EXEC dbo.Stackish_EditComment
    @CommentId = 789,
    @UserId = 123,
    @Text = N'Can you include the actual execution plan?';
SELECT * FROM @write;

-- EditComment missing target example.
DELETE @write;
INSERT @write EXEC dbo.Stackish_EditComment
    @CommentId = 2147483647,
    @UserId = 123,
    @Text = N'No row should be edited.';
SELECT * FROM @write;

-- DeleteComment normal call.
DELETE @write;
INSERT @write EXEC dbo.Stackish_DeleteComment
    @CommentId = 789,
    @UserId = 123;
SELECT * FROM @write;

-- DeleteComment missing target example.
DELETE @write;
INSERT @write EXEC dbo.Stackish_DeleteComment
    @CommentId = 2147483647,
    @UserId = 123;
SELECT * FROM @write;

-- GetPostComments normal and missing-target calls. Missing posts return an empty result set.
EXEC dbo.Stackish_GetPostComments @PostId = 456, @Offset = 0, @PageSize = 30;
EXEC dbo.Stackish_GetPostComments @PostId = 2147483647, @Offset = 0, @PageSize = 30;
