SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_RecordQuestionView
    @QuestionId int
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Posts
    SET ViewCount = ISNULL(ViewCount, 0) + 1
    WHERE Id = @QuestionId AND PostTypeId = 1;

    IF @@ROWCOUNT = 1
        SELECT CAST('Applied' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
    ELSE IF EXISTS (SELECT 1 FROM dbo.Posts WHERE Id = @QuestionId)
        SELECT CAST('Conflict' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
    ELSE
        SELECT CAST('NotFound' AS varchar(20)) AS Outcome, @QuestionId AS EntityId;
END;
GO
