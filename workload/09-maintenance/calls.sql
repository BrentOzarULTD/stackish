-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Choice int=ABS(CONVERT(bigint,CHECKSUM(NEWID()))) % 100;

IF @Choice<45
BEGIN
 DECLARE @AnswerId int=CASE WHEN (SELECT AcceptedAnswerId FROM dbo.Posts WHERE Id=@InputQuestionId)=@InputAnswerId THEN NULL ELSE @InputAnswerId END;
 EXEC dbo.Stackish_SetAcceptedAnswer @QuestionId=@InputQuestionId,@UserId=@InputUserId,@AnswerId=@AnswerId;
END;
ELSE IF @Choice<75
BEGIN
 IF (SELECT ClosedDate FROM dbo.Posts WHERE Id=@InputQuestionId) IS NULL
  EXEC dbo.Stackish_CloseQuestion @QuestionId=@InputQuestionId,@UserId=@InputUserId,@Reason=N'Workload close';
 ELSE EXEC dbo.Stackish_ReopenQuestion @QuestionId=@InputQuestionId,@UserId=@InputUserId;
END;
ELSE
BEGIN
 DECLARE @LinkId int=(SELECT MIN(Id) FROM dbo.PostLinks WHERE PostId=@InputQuestionId AND RelatedPostId=@InputRelatedQuestionId AND LinkTypeId=1);
 IF @LinkId IS NULL EXEC dbo.Stackish_AddQuestionLink @QuestionId=@InputQuestionId,@RelatedQuestionId=@InputRelatedQuestionId,@UserId=@InputUserId,@LinkTypeId=1;
 ELSE EXEC dbo.Stackish_RemoveQuestionLink @LinkId=@LinkId,@UserId=@InputUserId;
END;
