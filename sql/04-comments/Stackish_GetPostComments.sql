SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetPostComments
    @PostId int,
    @Offset int = 0,
    @PageSize int = 30
AS
BEGIN
    SET NOCOUNT ON;

    IF @Offset IS NULL OR @Offset < 0 THROW 50441, 'Offset must be zero or greater.', 1;
    IF @PageSize IS NULL OR @PageSize < 1 OR @PageSize > 100 THROW 50442, 'PageSize must be between 1 and 100.', 1;

    SELECT c.Id AS CommentId,
           c.PostId,
           c.Text,
           c.Score,
           c.CreationDate,
           NULLIF(c.UserId, 0) AS UserId,
           u.DisplayName
    FROM dbo.Comments c
    JOIN dbo.Posts p ON p.Id = c.PostId AND p.PostTypeId IN (1,2)
    LEFT JOIN dbo.Users u ON u.Id = c.UserId AND c.UserId > 0
    WHERE c.PostId = @PostId
      AND p.Id = @PostId
    ORDER BY c.CreationDate ASC, c.Id ASC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;
GO
