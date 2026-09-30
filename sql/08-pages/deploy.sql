:ON ERROR EXIT
IF CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))<17 THROW 50000,'Stackish requires SQL Server 2025 or later.',1;
IF (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID())<170 THROW 50000,'Stackish requires compatibility level 170 or later.',1;
IF OBJECT_ID(N'dbo.Stackish_SplitTags',N'IF') IS NULL THROW 50899,'Stackish_SplitTags must be deployed first.',1;
GO
:r sql/08-pages/Stackish_Pages.sql
