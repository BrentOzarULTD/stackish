-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Choice int=ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 100;

IF @Choice<75 EXEC dbo.Stackish_RecordQuestionView @QuestionId=@InputQuestionId;
ELSE IF @Choice<90 EXEC dbo.Stackish_RecordProfileView @UserId=@InputUserId;
ELSE EXEC dbo.Stackish_RecordUserAccess @UserId=@InputUserId;
