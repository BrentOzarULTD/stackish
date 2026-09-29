-- Run in SQLCMD mode from the repository root against the intended database.
-- Does not change compatibility, base tables, indexes, or data.
:ON ERROR EXIT
IF CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) < 17
    THROW 50000, 'Stackish requires SQL Server 2025 or later.', 1;
IF (SELECT compatibility_level FROM sys.databases WHERE database_id = DB_ID()) < 170
    THROW 50000, 'Stackish requires database compatibility level 170 or later.', 1;
GO
:r sql/01-users/Stackish_CreateUser.sql
:r sql/01-users/Stackish_UpdateUserProfile.sql
:r sql/01-users/Stackish_RecordUserAccess.sql
:r sql/01-users/Stackish_RecordProfileView.sql
:r sql/01-users/Stackish_GetUserCard.sql
:r sql/01-users/Stackish_ListUsers.sql
