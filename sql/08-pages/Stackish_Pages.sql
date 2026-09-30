SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetQuestionPage @QuestionId int,@AnswerSort varchar(20)='score',@AnswerOffset int=0,@AnswerPageSize int=30,@CommentLimit int=10
AS
BEGIN
 SET NOCOUNT ON;
 IF @AnswerSort IS NULL OR @AnswerSort NOT IN ('score','newest') OR @AnswerOffset IS NULL OR @AnswerOffset<0 OR @AnswerPageSize IS NULL OR @AnswerPageSize NOT BETWEEN 1 AND 100 OR @CommentLimit IS NULL OR @CommentLimit NOT BETWEEN 0 AND 100 THROW 50801,'Invalid question-page arguments.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Posts WHERE Id=@QuestionId AND PostTypeId=1)
 BEGIN
  SELECT TOP(0) CONVERT(int,NULL) QuestionId,CONVERT(nvarchar(250),NULL) Title,CONVERT(int,NULL) Score,CONVERT(int,NULL) ViewCount,CONVERT(int,NULL) AnswerCount,CONVERT(int,NULL) CommentCount,CONVERT(nvarchar(150),NULL) Tags,CONVERT(datetime,NULL) CreationDate,CONVERT(datetime,NULL) LastActivityDate,CONVERT(datetime,NULL) ClosedDate,CONVERT(int,NULL) AcceptedAnswerId,CONVERT(int,NULL) OwnerUserId,CONVERT(nvarchar(40),NULL) OwnerDisplayName,CONVERT(int,NULL) OwnerReputation,CONVERT(nvarchar(max),NULL) Body,CONVERT(int,NULL) FavoriteCount,CONVERT(datetime,NULL) LastEditDate,CONVERT(int,NULL) LastEditorUserId;
  SELECT TOP(0) CONVERT(int,NULL) AnswerId,CONVERT(int,NULL) QuestionId,CONVERT(nvarchar(max),NULL) Body,CONVERT(int,NULL) Score,CONVERT(int,NULL) CommentCount,CONVERT(datetime,NULL) CreationDate,CONVERT(datetime,NULL) LastActivityDate,CONVERT(datetime,NULL) LastEditDate,CONVERT(int,NULL) OwnerUserId,CONVERT(nvarchar(40),NULL) OwnerDisplayName,CONVERT(int,NULL) OwnerReputation,CONVERT(bit,NULL) IsAccepted;
  SELECT TOP(0) CONVERT(int,NULL) CommentId,CONVERT(int,NULL) PostId,CONVERT(nvarchar(700),NULL) Text,CONVERT(int,NULL) Score,CONVERT(datetime,NULL) CreationDate,CONVERT(int,NULL) UserId,CONVERT(nvarchar(40),NULL) DisplayName;
  SELECT TOP(0) CONVERT(int,NULL) LinkId,CONVERT(int,NULL) QuestionId,CONVERT(int,NULL) RelatedQuestionId,CONVERT(int,NULL) LinkTypeId,CONVERT(datetime,NULL) CreationDate,CONVERT(nvarchar(250),NULL) TargetTitle;
  SELECT TOP(0) CONVERT(nvarchar(150),NULL) TagName; RETURN;
 END;
 SELECT p.Id AS QuestionId,p.Title,p.Score,p.ViewCount,p.AnswerCount,p.CommentCount,p.Tags,p.CreationDate,p.LastActivityDate,p.ClosedDate,CASE WHEN aa.Id IS NOT NULL THEN p.AcceptedAnswerId END AS AcceptedAnswerId,NULLIF(p.OwnerUserId,0) AS OwnerUserId,u.DisplayName AS OwnerDisplayName,u.Reputation AS OwnerReputation,p.Body,p.FavoriteCount,p.LastEditDate,NULLIF(p.LastEditorUserId,0) AS LastEditorUserId
 FROM dbo.Posts p LEFT JOIN dbo.Users u ON u.Id=p.OwnerUserId LEFT JOIN dbo.Posts aa ON aa.Id=p.AcceptedAnswerId AND aa.PostTypeId=2 AND aa.ParentId=p.Id WHERE p.Id=@QuestionId;
 DECLARE @Answers table (AnswerId int PRIMARY KEY);
 INSERT @Answers SELECT p.Id FROM dbo.Posts p WHERE p.PostTypeId=2 AND p.ParentId=@QuestionId ORDER BY CASE WHEN @AnswerSort='score' THEN p.Score END DESC,CASE WHEN @AnswerSort='newest' THEN p.CreationDate END DESC,p.Id DESC OFFSET @AnswerOffset ROWS FETCH NEXT @AnswerPageSize ROWS ONLY;
 SELECT p.Id AS AnswerId,p.ParentId AS QuestionId,p.Body,p.Score,p.CommentCount,p.CreationDate,p.LastActivityDate,p.LastEditDate,NULLIF(p.OwnerUserId,0) AS OwnerUserId,u.DisplayName AS OwnerDisplayName,u.Reputation AS OwnerReputation,CONVERT(bit,CASE WHEN q.AcceptedAnswerId=p.Id THEN 1 ELSE 0 END) AS IsAccepted
 FROM @Answers x JOIN dbo.Posts p ON p.Id=x.AnswerId LEFT JOIN dbo.Users u ON u.Id=p.OwnerUserId JOIN dbo.Posts q ON q.Id=@QuestionId ORDER BY CASE WHEN @AnswerSort='score' THEN p.Score END DESC,CASE WHEN @AnswerSort='newest' THEN p.CreationDate END DESC,p.Id DESC;
 ;WITH C AS (SELECT c1.* FROM dbo.Comments c1 WHERE c1.PostId=@QuestionId UNION ALL SELECT c2.* FROM @Answers a JOIN dbo.Comments c2 ON c2.PostId=a.AnswerId), Ranked AS (SELECT C.*,ROW_NUMBER() OVER(PARTITION BY C.PostId ORDER BY C.CreationDate,C.Id) rn FROM C) SELECT c.Id AS CommentId,c.PostId,c.Text,c.Score,c.CreationDate,NULLIF(c.UserId,0) AS UserId,u.DisplayName FROM Ranked c LEFT JOIN dbo.Users u ON u.Id=c.UserId WHERE c.rn<=@CommentLimit ORDER BY c.PostId,c.CreationDate,c.Id;
 SELECT TOP(100) l.Id AS LinkId,l.PostId AS QuestionId,l.RelatedPostId AS RelatedQuestionId,l.LinkTypeId,l.CreationDate,t.Title AS TargetTitle FROM dbo.PostLinks l LEFT JOIN dbo.Posts t ON t.Id=l.RelatedPostId AND t.PostTypeId=1 WHERE l.PostId=@QuestionId AND l.LinkTypeId IN(1,3) ORDER BY l.CreationDate DESC,l.Id DESC;
 SELECT TagName FROM dbo.Stackish_SplitTags((SELECT Tags FROM dbo.Posts WHERE Id=@QuestionId)) ORDER BY TagName;
END;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetUserProfile @UserId int,@TopCount int=10
AS
BEGIN
 SET NOCOUNT ON; IF @TopCount IS NULL OR @TopCount NOT BETWEEN 1 AND 100 THROW 50811,'TopCount must be between 1 and 100.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Users WHERE Id=@UserId)
 BEGIN
  SELECT TOP(0) CONVERT(int,NULL) UserId,CONVERT(nvarchar(40),NULL) DisplayName,CONVERT(int,NULL) Reputation,CONVERT(nvarchar(100),NULL) Location,CONVERT(datetime,NULL) CreationDate,CONVERT(datetime,NULL) LastAccessDate,CONVERT(nvarchar(max),NULL) AboutMe,CONVERT(nvarchar(200),NULL) WebsiteUrl,CONVERT(int,NULL) Age,CONVERT(int,NULL) Views,CONVERT(int,NULL) UpVotes,CONVERT(int,NULL) DownVotes;
  SELECT TOP(0) CONVERT(int,NULL) UserId,CONVERT(bigint,NULL) QuestionCount,CONVERT(bigint,NULL) AnswerCount,CONVERT(bigint,NULL) CommentCount,CONVERT(bigint,NULL) BadgeCount;
  SELECT TOP(0) CONVERT(int,NULL) PostId,CONVERT(int,NULL) PostTypeId,CONVERT(int,NULL) QuestionId,CONVERT(nvarchar(250),NULL) Title,CONVERT(int,NULL) Score,CONVERT(datetime,NULL) CreationDate,CONVERT(datetime,NULL) LastActivityDate,CONVERT(bit,NULL) IsAccepted;
  SELECT TOP(0) CONVERT(nvarchar(150),NULL) TagName,CONVERT(bigint,NULL) PostCount,CONVERT(bigint,NULL) TotalScore;
  SELECT TOP(0) CONVERT(nvarchar(40),NULL) Name,CONVERT(bigint,NULL) AwardCount,CONVERT(datetime,NULL) MostRecentAward; RETURN;
 END;
 SELECT Id AS UserId,DisplayName,Reputation,Location,CreationDate,LastAccessDate,AboutMe,WebsiteUrl,Age,Views,UpVotes,DownVotes FROM dbo.Users WHERE Id=@UserId;
 SELECT u.Id AS UserId,CONVERT(bigint,(SELECT COUNT_BIG(*) FROM dbo.Posts p WHERE p.OwnerUserId=u.Id AND p.PostTypeId=1)) AS QuestionCount,CONVERT(bigint,(SELECT COUNT_BIG(*) FROM dbo.Posts p WHERE p.OwnerUserId=u.Id AND p.PostTypeId=2)) AS AnswerCount,CONVERT(bigint,(SELECT COUNT_BIG(*) FROM dbo.Comments c WHERE c.UserId=u.Id)) AS CommentCount,CONVERT(bigint,(SELECT COUNT_BIG(*) FROM dbo.Badges b WHERE b.UserId=u.Id)) AS BadgeCount FROM dbo.Users u WHERE u.Id=@UserId;
 SELECT TOP(@TopCount) p.Id AS PostId, p.PostTypeId,CASE WHEN p.PostTypeId=1 THEN p.Id ELSE p.ParentId END AS QuestionId,q.Title,p.Score,p.CreationDate,p.LastActivityDate,CONVERT(bit,CASE WHEN p.PostTypeId=2 AND q.AcceptedAnswerId=p.Id THEN 1 ELSE 0 END) AS IsAccepted FROM dbo.Posts p LEFT JOIN dbo.Posts q ON q.Id=CASE WHEN p.PostTypeId=1 THEN p.Id ELSE p.ParentId END AND q.PostTypeId=1 WHERE p.OwnerUserId=@UserId AND p.PostTypeId IN(1,2) ORDER BY p.Score DESC,p.Id DESC;
 ;WITH Owned AS (SELECT p.Id,p.Score,p.Tags FROM dbo.Posts p WHERE p.OwnerUserId=@UserId AND p.PostTypeId=1 UNION ALL SELECT p.Id,p.Score,q.Tags FROM dbo.Posts p JOIN dbo.Posts q ON q.Id=p.ParentId AND q.PostTypeId=1 WHERE p.OwnerUserId=@UserId AND p.PostTypeId=2), T AS (SELECT s.TagName,o.Id,o.Score FROM Owned o CROSS APPLY dbo.Stackish_SplitTags(o.Tags) s) SELECT TOP(@TopCount) TagName,COUNT_BIG(DISTINCT Id) AS PostCount,SUM(CONVERT(bigint,Score)) AS TotalScore FROM T GROUP BY TagName ORDER BY SUM(CONVERT(bigint,Score)) DESC,TagName;
 SELECT TOP(@TopCount) Name,COUNT_BIG(*) AS AwardCount,MAX(Date) AS MostRecentAward FROM dbo.Badges WHERE UserId=@UserId GROUP BY Name ORDER BY COUNT_BIG(*) DESC,Name;
END;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetUserPosts @UserId int,@PostTypeId int=NULL,@Sort varchar(20)='score',@Offset int=0,@PageSize int=30
AS
BEGIN
 SET NOCOUNT ON; IF @PostTypeId IS NOT NULL AND @PostTypeId NOT IN(1,2) THROW 50821,'PostTypeId must be 1 or 2.',1; IF @Sort IS NULL OR @Sort NOT IN('score','newest') OR @Offset IS NULL OR @Offset<0 OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100 THROW 50822,'Invalid post paging.',1;
 SELECT p.Id AS PostId,p.PostTypeId,CASE WHEN p.PostTypeId=1 THEN p.Id ELSE p.ParentId END AS QuestionId,q.Title,p.Score,p.CreationDate,p.LastActivityDate,CONVERT(bit,CASE WHEN p.PostTypeId=2 AND q.AcceptedAnswerId=p.Id THEN 1 ELSE 0 END) AS IsAccepted FROM dbo.Posts p LEFT JOIN dbo.Posts q ON q.Id=CASE WHEN p.PostTypeId=1 THEN p.Id ELSE p.ParentId END AND q.PostTypeId=1 WHERE p.OwnerUserId=@UserId AND EXISTS(SELECT 1 FROM dbo.Users u WHERE u.Id=@UserId) AND p.PostTypeId IN(1,2) AND (@PostTypeId IS NULL OR p.PostTypeId=@PostTypeId) ORDER BY CASE WHEN @Sort='score' THEN p.Score END DESC,CASE WHEN @Sort='newest' THEN p.CreationDate END DESC,p.Id DESC OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetPostHistory @PostId int,@Offset int=0,@PageSize int=30
AS
BEGIN
 SET NOCOUNT ON; IF @Offset IS NULL OR @Offset<0 OR @PageSize IS NULL OR @PageSize NOT BETWEEN 1 AND 100 THROW 50831,'Invalid history paging.',1;
 SELECT h.Id,h.PostHistoryTypeId,h.RevisionGUID,h.CreationDate,NULLIF(h.UserId,0) AS UserId,h.UserDisplayName,h.Comment,h.Text FROM dbo.PostHistory h WHERE h.PostId=@PostId AND EXISTS(SELECT 1 FROM dbo.Posts p WHERE p.Id=@PostId) ORDER BY h.CreationDate DESC,h.Id DESC OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
