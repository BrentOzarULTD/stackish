SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.Stackish_GetPostVoteSummary
    @PostId int
AS
BEGIN
    SET NOCOUNT ON;

    -- Score is the stored (imported plus local delta) value. The recorded counts are just
    -- the rows present in Votes and are not expected to add up to Score.
    SELECT p.Id AS PostId,
           p.Score,
           v.RecordedUpVotes,
           v.RecordedDownVotes
    FROM dbo.Posts p
    CROSS APPLY (
        SELECT ISNULL(SUM(IIF(vt.VoteTypeId = 2, CAST(1 AS bigint), 0)), 0) AS RecordedUpVotes,
               ISNULL(SUM(IIF(vt.VoteTypeId = 3, CAST(1 AS bigint), 0)), 0) AS RecordedDownVotes
        FROM dbo.Votes vt
        WHERE vt.PostId = p.Id
          AND vt.VoteTypeId IN (2, 3)
    ) v
    WHERE p.Id = @PostId
      AND p.PostTypeId IN (1, 2);
END;
GO
