-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Choice int=ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 100;

IF @Choice<80 EXEC dbo.Stackish_RecordQuestionView @QuestionId=@InputQuestionId;
ELSE EXEC dbo.Stackish_RecordProfileView @UserId=@InputUserId;
