SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_ListQuestions
    @Sort varchar(20) = 'newest', @Offset int = 0, @PageSize int = 30
AS
BEGIN
 SET NOCOUNT ON;
 IF @Offset IS NULL OR @Offset < 0 THROW 50601, 'Offset must be zero or greater.', 1;
 IF @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100 THROW 50602, 'PageSize must be between 1 and 100.', 1;
 IF @Sort IS NULL OR @Sort NOT IN ('newest','active','score','views') THROW 50603, 'Sort must be newest, active, score, or views.', 1;
 SELECT p.Id QuestionId,p.Title,p.Score,p.ViewCount,p.AnswerCount,p.CommentCount,p.Tags,p.CreationDate,p.LastActivityDate,p.ClosedDate,
        CASE WHEN a.Id IS NOT NULL THEN p.AcceptedAnswerId END AcceptedAnswerId, NULLIF(p.OwnerUserId,0) OwnerUserId,u.DisplayName OwnerDisplayName,u.Reputation OwnerReputation
 FROM dbo.Posts p LEFT JOIN dbo.Users u ON u.Id=p.OwnerUserId LEFT JOIN dbo.Posts a ON a.Id=p.AcceptedAnswerId AND a.PostTypeId=2 AND a.ParentId=p.Id
 WHERE p.PostTypeId=1
 ORDER BY CASE WHEN @Sort='newest' THEN p.CreationDate END DESC, CASE WHEN @Sort='active' THEN p.LastActivityDate END DESC,
          CASE WHEN @Sort='score' THEN p.Score END DESC, CASE WHEN @Sort='views' THEN p.ViewCount END DESC, p.Id DESC
 OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_SearchQuestions
 @Text nvarchar(200)=NULL,@TagName nvarchar(150)=NULL,@OwnerUserId int=NULL,@MinScore int=NULL,@HasAccepted bit=NULL,
 @FromDate datetime=NULL,@ToDate datetime=NULL,@SearchBody bit=0,@Offset int=0,@PageSize int=30
AS
BEGIN
 SET NOCOUNT ON;
 IF @Offset IS NULL OR @Offset<0 THROW 50611,'Offset must be zero or greater.',1;
 IF @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100 THROW 50612,'PageSize must be between 1 and 100.',1;
 IF @Text=N'' OR @TagName=N'' THROW 50613,'Text and TagName cannot be empty.',1;
 IF @ToDate IS NOT NULL AND @FromDate IS NOT NULL AND @ToDate<@FromDate THROW 50614,'ToDate must be on or after FromDate.',1;
 IF @SearchBody IS NULL SET @SearchBody=0;
 DECLARE @TextPattern nvarchar(410)=REPLACE(REPLACE(REPLACE(REPLACE(@Text,N'~',N'~~'),N'%',N'~%'),N'_',N'~_'),N'[',N'~[');
 SELECT p.Id QuestionId,p.Title,p.Score,p.ViewCount,p.AnswerCount,p.CommentCount,p.Tags,p.CreationDate,p.LastActivityDate,p.ClosedDate,
        CASE WHEN a.Id IS NOT NULL THEN p.AcceptedAnswerId END AcceptedAnswerId,NULLIF(p.OwnerUserId,0) OwnerUserId,u.DisplayName OwnerDisplayName,u.Reputation OwnerReputation
 FROM dbo.Posts p LEFT JOIN dbo.Users u ON u.Id=p.OwnerUserId LEFT JOIN dbo.Posts a ON a.Id=p.AcceptedAnswerId AND a.PostTypeId=2 AND a.ParentId=p.Id
 WHERE p.PostTypeId=1 AND (@Text IS NULL OR p.Title LIKE N'%' + @TextPattern + N'%' ESCAPE N'~' OR (@SearchBody=1 AND p.Body LIKE N'%' + @TextPattern + N'%' ESCAPE N'~'))
   AND (@TagName IS NULL OR CHARINDEX(N'<' + @TagName + N'>',COALESCE(p.Tags,N''))>0)
   AND (@OwnerUserId IS NULL OR p.OwnerUserId=@OwnerUserId) AND (@MinScore IS NULL OR p.Score>=@MinScore)
   AND (@HasAccepted IS NULL OR CASE WHEN a.Id IS NOT NULL THEN CONVERT(bit,1) ELSE CONVERT(bit,0) END=@HasAccepted)
   AND (@FromDate IS NULL OR p.CreationDate>=@FromDate) AND (@ToDate IS NULL OR p.CreationDate<@ToDate)
 ORDER BY p.Score DESC,p.Id DESC OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetQuestionsByTag @TagName nvarchar(150),@Sort varchar(20)='active',@Offset int=0,@PageSize int=30
AS
BEGIN
 SET NOCOUNT ON;
 IF @TagName IS NULL OR LEN(REPLACE(REPLACE(REPLACE(@TagName,N' ',N''),NCHAR(9),N''),NCHAR(13),N''))=0 THROW 50621,'TagName is required.',1;
 IF @Sort IS NULL OR @Sort NOT IN ('active','newest','score') THROW 50622,'Sort must be active, newest, or score.',1;
 IF @Offset IS NULL OR @Offset<0 OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100 THROW 50623,'Invalid paging.',1;
 SELECT p.Id QuestionId,p.Title,p.Score,p.ViewCount,p.AnswerCount,p.CommentCount,p.Tags,p.CreationDate,p.LastActivityDate,p.ClosedDate,CASE WHEN a.Id IS NOT NULL THEN p.AcceptedAnswerId END AcceptedAnswerId,NULLIF(p.OwnerUserId,0) OwnerUserId,u.DisplayName OwnerDisplayName,u.Reputation OwnerReputation
 FROM dbo.Posts p LEFT JOIN dbo.Users u ON u.Id=p.OwnerUserId LEFT JOIN dbo.Posts a ON a.Id=p.AcceptedAnswerId AND a.PostTypeId=2 AND a.ParentId=p.Id
 WHERE p.PostTypeId=1 AND CHARINDEX(N'<'+@TagName+N'>',COALESCE(p.Tags,N''))>0
 ORDER BY CASE WHEN @Sort='active' THEN p.LastActivityDate END DESC,CASE WHEN @Sort='newest' THEN p.CreationDate END DESC,CASE WHEN @Sort='score' THEN p.Score END DESC,p.Id DESC
 OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetUnansweredQuestions @TagName nvarchar(150)=NULL,@Mode varchar(20)='no_answers',@Offset int=0,@PageSize int=30
AS
BEGIN
 SET NOCOUNT ON;
 IF @Mode IS NULL OR @Mode NOT IN ('no_answers','no_solution') THROW 50631,'Mode must be no_answers or no_solution.',1;
 IF @TagName=N'' OR @Offset IS NULL OR @Offset<0 OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100 THROW 50632,'Invalid filter or paging.',1;
 SELECT p.Id QuestionId,p.Title,p.Score,p.ViewCount,p.AnswerCount,p.CommentCount,p.Tags,p.CreationDate,p.LastActivityDate,p.ClosedDate,CASE WHEN a.Id IS NOT NULL THEN p.AcceptedAnswerId END AcceptedAnswerId,NULLIF(p.OwnerUserId,0) OwnerUserId,u.DisplayName OwnerDisplayName,u.Reputation OwnerReputation
 FROM dbo.Posts p LEFT JOIN dbo.Users u ON u.Id=p.OwnerUserId LEFT JOIN dbo.Posts a ON a.Id=p.AcceptedAnswerId AND a.PostTypeId=2 AND a.ParentId=p.Id
 WHERE p.PostTypeId=1 AND p.ClosedDate IS NULL AND (@TagName IS NULL OR CHARINDEX(N'<'+@TagName+N'>',COALESCE(p.Tags,N''))>0)
   AND ((@Mode='no_answers' AND NOT EXISTS(SELECT 1 FROM dbo.Posts x WHERE x.PostTypeId=2 AND x.ParentId=p.Id)) OR (@Mode='no_solution' AND NOT EXISTS(SELECT 1 FROM dbo.Posts x WHERE x.PostTypeId=2 AND x.ParentId=p.Id AND x.Score>0) AND a.Id IS NULL))
 ORDER BY p.CreationDate DESC,p.Id DESC OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetRelatedQuestions @QuestionId int,@Offset int=0,@PageSize int=30
AS
BEGIN
 SET NOCOUNT ON;
 IF @Offset IS NULL OR @Offset<0 OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100 THROW 50641,'Invalid paging.',1;
 ;WITH Src AS (SELECT TagName FROM dbo.Stackish_SplitTags((SELECT Tags FROM dbo.Posts WHERE Id=@QuestionId AND PostTypeId=1))), Matches AS (SELECT p.Id,COUNT_BIG(*) SharedCount FROM dbo.Posts p JOIN Src q ON CHARINDEX(N'<'+q.TagName+N'>',COALESCE(p.Tags,N''))>0 WHERE p.PostTypeId=1 AND p.Id<>@QuestionId GROUP BY p.Id)
 SELECT p.Id QuestionId,p.Title,p.Score,p.ViewCount,p.AnswerCount,p.CommentCount,p.Tags,p.CreationDate,p.LastActivityDate,p.ClosedDate,CASE WHEN a.Id IS NOT NULL THEN p.AcceptedAnswerId END AcceptedAnswerId,NULLIF(p.OwnerUserId,0) OwnerUserId,u.DisplayName OwnerDisplayName,u.Reputation OwnerReputation
 FROM Matches m JOIN dbo.Posts p ON p.Id=m.Id LEFT JOIN dbo.Users u ON u.Id=p.OwnerUserId LEFT JOIN dbo.Posts a ON a.Id=p.AcceptedAnswerId AND a.PostTypeId=2 AND a.ParentId=p.Id
 ORDER BY m.SharedCount DESC,p.Score DESC,p.Id DESC OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
