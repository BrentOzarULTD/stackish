-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Choice int=ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 100;

IF @Choice<80 EXEC dbo.Stackish_ListQuestions @Sort='newest',@PageSize=30;
ELSE EXEC dbo.Stackish_ListQuestions @Sort='active',@PageSize=30;
