-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Choice int=ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 100;

DECLARE @Text nvarchar(max)=CONCAT(N'Stackish edit ',CONVERT(nvarchar(36),NEWID()));
DECLARE @Body nvarchar(max)=@Text;
IF ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 5=0
 SET @Body=@Body+REPLICATE(CONVERT(nvarchar(max),N'<p>This example describes the inputs, observed output, and the expected result so another reader can reproduce the question.</p>'),128);
IF @Choice<10
 EXEC dbo.Stackish_UpdateUserProfile @UserId=@InputUserId,@DisplayName=N'Stackish workload user',@AboutMe=@Text;
ELSE IF @InputPostTypeId=2
 EXEC dbo.Stackish_EditAnswer @AnswerId=@InputPostId,@EditorUserId=@InputUserId,@Body=@Body,@EditSummary=N'Workload edit';
ELSE IF @Choice<55
 EXEC dbo.Stackish_EditQuestion @QuestionId=@InputPostId,@EditorUserId=@InputUserId,@Title=@Text,@Body=@Body,@EditSummary=N'Workload edit';
ELSE
BEGIN
 DECLARE @Tags nvarchar(max)=CASE WHEN (SELECT Tags FROM dbo.Posts WHERE Id=@InputPostId)=N'<'+@InputTag1+N'>'
 THEN N'<'+@InputTag2+N'>' ELSE N'<'+@InputTag1+N'>' END;
 EXEC dbo.Stackish_RetagQuestion @QuestionId=@InputPostId,@EditorUserId=@InputUserId,@Tags=@Tags,@EditSummary=N'Workload retag';
END;
