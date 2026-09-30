-- Run in SQLCMD mode from the repository root against the intended database.
-- Does not change compatibility, base tables, indexes, or data.
:ON ERROR EXIT
IF CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) < 17
    THROW 50000, 'Stackish requires SQL Server 2025 or later.', 1;
IF (SELECT compatibility_level FROM sys.databases WHERE database_id = DB_ID()) < 170
    THROW 50000, 'Stackish requires database compatibility level 170 or later.', 1;
IF OBJECT_ID(N'dbo.Stackish_SplitTags', N'IF') IS NULL
    THROW 50000, 'Deploy dbo.Stackish_SplitTags before question procedures.', 1;
GO
:r sql/02-questions/Stackish_CreateQuestion.sql
:r sql/02-questions/Stackish_EditQuestion.sql
:r sql/02-questions/Stackish_RetagQuestion.sql
:r sql/02-questions/Stackish_RecordQuestionView.sql
