SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER FUNCTION dbo.Stackish_SplitTags (@Tags nvarchar(150))
RETURNS TABLE
AS
RETURN
(
    -- Only closed <token> fragments qualify. DISTINCT follows database collation.
    -- This deliberately does not validate a complete write request or its tag count.
    SELECT DISTINCT CONVERT(nvarchar(150), SUBSTRING(s.value, 2, 150)) AS TagName
    FROM STRING_SPLIT(@Tags, N'>', 1) AS s
    WHERE s.ordinal <= (DATALENGTH(@Tags) - DATALENGTH(REPLACE(@Tags, N'>', N''))) / 2
      AND LEFT(s.value, 1) = N'<'
      AND CHARINDEX(N'<', s.value, 2) = 0
      AND LEN(REPLACE(REPLACE(REPLACE(SUBSTRING(s.value, 2, 150), NCHAR(9), N''), NCHAR(10), N''), NCHAR(13), N'')) > 0
);
GO
