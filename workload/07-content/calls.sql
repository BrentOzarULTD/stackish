-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Choice int=ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 100;

DECLARE @Text nvarchar(max)=CONCAT(N'Stackish content ',CONVERT(nvarchar(36),NEWID()));
DECLARE @Body nvarchar(max)=@Text;
IF ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 5=0
 SET @Body=@Body+REPLICATE(CONVERT(nvarchar(max),N'<p>This example describes the inputs, observed output, and the expected result so another reader can reproduce the question.</p>'),128);
DECLARE @Tags nvarchar(max)=N'<'+@InputTagName+N'>';
IF @Choice<20 EXEC dbo.Stackish_CreateQuestion @UserId=@InputUserId,@Title=@Text,@Body=@Body,@Tags=@Tags;
ELSE IF @Choice<60 EXEC dbo.Stackish_CreateAnswer @QuestionId=@InputQuestionId,@UserId=@InputUserId,@Body=@Body;
ELSE EXEC dbo.Stackish_AddComment @PostId=@InputQuestionId,@UserId=@InputUserId,@Text=@Text;
