-- Paste this entire batch into SQLQueryStress. Map only Input variables. No GO.
SET NOCOUNT ON;
DECLARE @Name nvarchar(max)=N'SQ '+LEFT(CONVERT(nvarchar(36),NEWID()),36);
EXEC dbo.Stackish_CreateUser @DisplayName=@Name,@AboutMe=N'Stackish workload';
