# Observed database schema

Read-only inspection of `StackOverflow`, 2026-09-29. SQL Server 2025 RTM-CU9; compatibility 170; `SQL_Latin1_General_CP1_CI_AS`; read committed snapshot OFF. These are observations, not installation requirements. Row counts are partition metadata estimates. The 2024-04 release database has not been inspected.

No foreign keys, check constraints, or user triggers were returned. No column defaults were returned. No full-text indexes exist. All core tables have an identity `Id` and clustered primary key. The custom reporting tables are excluded from Stackish. Do not call the existing `DropIndexes` procedure.

Column lengths below are characters for nvarchar, not the bytes reported by sys.columns.

## dbo.Badges

Approximately 27,313,649 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| Id | int | no | yes |
| Name | nvarchar(40) | no |  |
| UserId | int | no |  |
| Date | datetime | no |  |

Observed indexes:

- `PK_Badges__Id` (Id) — clustered PK
- `IX_Id` (Id)
- `IX_UserId` (UserId)
- `_dta_index_Badges_5_2105058535__K3_K2_K4` (UserId, Name, Date)

## dbo.Comments

Approximately 66,432,641 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| Id | int | no | yes |
| CreationDate | datetime | no |  |
| PostId | int | no |  |
| Score | int | yes |  |
| Text | nvarchar(700) | no |  |
| UserId | int | yes |  |

Observed indexes:

- `PK_Comments__Id` (Id) — clustered PK
- `IX_Id` (Id)
- `IX_PostId` (PostId)
- `IX_UserId` (UserId)
- `_dta_index_Comments_5_2137058649__K6_K2_K3` (UserId, CreationDate, PostId)

## dbo.LinkTypes

Approximately 2 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| Id | int | no | yes |
| Type | varchar(50) | no |  |

Observed indexes:

- `PK_LinkTypes__Id` (Id) — clustered PK

## dbo.PostHistory

Approximately 0 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| Id | int | no | yes |
| PostHistoryTypeId | int | no |  |
| PostId | int | no |  |
| RevisionGUID | uniqueidentifier | no |  |
| CreationDate | datetime | no |  |
| UserId | int | yes |  |
| UserDisplayName | nvarchar(40) | yes |  |
| Comment | nvarchar(max) | yes |  |
| Text | nvarchar(max) | yes |  |

Observed indexes:

- `PK_PostHistory__Id` (Id) — clustered PK

## dbo.PostHistoryTypes

Approximately 37 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| Id | int | no | yes |
| Type | nvarchar(50) | no |  |

Observed indexes:

- `PK_PostHistoryTypes__Id` (Id) — clustered PK

## dbo.PostLinks

Approximately 5,086,111 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| Id | int | no | yes |
| CreationDate | datetime | no |  |
| PostId | int | no |  |
| RelatedPostId | int | no |  |
| LinkTypeId | int | no |  |

Observed indexes:

- `PK_PostLinks__Id` (Id) — clustered PK
- `IX_LinkTypeId` (LinkTypeId)
- `IX_PostId` (PostId)
- `IX_RelatedPostId` (RelatedPostId)

## dbo.Posts

Approximately 40,700,647 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| Id | int | no | yes |
| AcceptedAnswerId | int | yes |  |
| AnswerCount | int | yes |  |
| Body | nvarchar(max) | no |  |
| ClosedDate | datetime | yes |  |
| CommentCount | int | yes |  |
| CommunityOwnedDate | datetime | yes |  |
| CreationDate | datetime | no |  |
| FavoriteCount | int | yes |  |
| LastActivityDate | datetime | no |  |
| LastEditDate | datetime | yes |  |
| LastEditorDisplayName | nvarchar(40) | yes |  |
| LastEditorUserId | int | yes |  |
| OwnerUserId | int | yes |  |
| ParentId | int | yes |  |
| PostTypeId | int | no |  |
| Score | int | no |  |
| Tags | nvarchar(150) | yes |  |
| Title | nvarchar(250) | yes |  |
| ViewCount | int | no |  |

Observed indexes:

- `PK_Posts__Id` (Id) — clustered PK
- `_dta_index_Posts_5_85575343__K2` (AcceptedAnswerId)
- `IX_AcceptedAnswerId` (AcceptedAnswerId)
- `_dta_index_Posts_5_85575343__K2_K14` (AcceptedAnswerId, OwnerUserId)
- `_dta_index_Posts_5_85575343__K8` (CreationDate)
- `IX_LastActivityDate_Includes` (LastActivityDate) INCLUDE (ViewCount)
- `IX_LastEditorUserId` (LastEditorUserId)
- `IX_OwnerUserId` (OwnerUserId)
- `_dta_index_Posts_5_85575343__K14_K16_K7_K1_K2_17` (OwnerUserId, PostTypeId, CommunityOwnedDate, Id, AcceptedAnswerId) INCLUDE (Score)
- `_dta_index_Posts_5_85575343__K14_K16_K1_K2` (OwnerUserId, PostTypeId, Id, AcceptedAnswerId)
- `IX_ParentId` (ParentId)
- `IX_PostTypeId` (PostTypeId)
- `_dta_index_Posts_5_85575343__K16_K7_K5_K14_17` (PostTypeId, CommunityOwnedDate, ClosedDate, OwnerUserId) INCLUDE (Score)
- `IX_ViewCount_Includes` (ViewCount) INCLUDE (LastActivityDate)

## dbo.PostTypes

Approximately 8 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| Id | int | no | yes |
| Type | nvarchar(50) | no |  |

Observed indexes:

- `PK_PostTypes__Id` (Id) — clustered PK
- `IX2` (Id)
- `IX4` (Id, Type)
- `IX1` (Type)
- `IX3` (Type, Id)
- `IX_Type` (Type, Id)

## dbo.Report_BadgePopularity

Approximately 4,949 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| BadgeName | varchar(40) | no |  |
| FirstAwarded | varchar(40) | yes |  |
| FirstAwardedToUser | varchar(40) | yes |  |
| TotalAwarded | varchar(40) | yes |  |

Observed indexes:

- `PK__Report_B__56DAA4B0FBA96FC0` (BadgeName) — clustered PK

## dbo.Report_UsersByQuestions

Approximately 8,917,507 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| UserId | int | no |  |
| DisplayName | varchar(40) | yes |  |
| CreationDate | date | yes |  |
| LastAccessDate | datetime2 | yes |  |
| Location | varchar(100) | yes |  |
| Questions | int | yes |  |
| Answers | int | yes |  |
| Comments | int | yes |  |

Observed indexes:

- `PK__Report_U__1788CC4CECCE7B25` (UserId) — clustered PK

## dbo.Tags

Approximately 52,445 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| Id | int | no | yes |
| TagName | nvarchar(150) | no |  |
| Count | int | no |  |
| ExcerptPostId | int | no |  |
| WikiPostId | int | no |  |

Observed indexes:

- `PK_Tags__Id` (Id) — clustered PK

## dbo.Users

Approximately 8,917,507 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| Id | int | no | yes |
| AboutMe | nvarchar(max) | yes |  |
| Age | int | yes |  |
| CreationDate | datetime | no |  |
| DisplayName | nvarchar(40) | no |  |
| DownVotes | int | no |  |
| EmailHash | nvarchar(40) | yes |  |
| LastAccessDate | datetime | no |  |
| Location | nvarchar(100) | yes |  |
| Reputation | int | no |  |
| UpVotes | int | no |  |
| Views | int | no |  |
| WebsiteUrl | nvarchar(200) | yes |  |
| AccountId | int | yes |  |

Observed indexes:

- `PK_Users_Id` (Id) — clustered PK
- `_dta_index_Users_5_149575571__K7_K10_K1_5` (EmailHash, Reputation, Id) INCLUDE (DisplayName)
- `IX_LastAccessDate` (LastAccessDate)
- `IX_LastAccessDate_DisplayName_Reputation` (LastAccessDate, DisplayName, Reputation)
- `<Name of Missing Index, sysname,>` (Reputation) INCLUDE (Views)
- `IX_Reputation_Includes` (Reputation) INCLUDE (Views)
- `IX_Views_Includes` (Views) INCLUDE (Reputation)

## dbo.Votes

Approximately 150,784,380 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| Id | int | no | yes |
| PostId | int | no |  |
| UserId | int | yes |  |
| BountyAmount | int | yes |  |
| VoteTypeId | int | no |  |
| CreationDate | datetime | no |  |

Observed indexes:

- `PK_Votes__Id` (Id) — clustered PK
- `IX_PostId_UserId` (PostId, UserId)
- `IX_UserId` (UserId)
- `_dta_index_Votes_5_181575685__K3_K2_K5` (UserId, PostId, VoteTypeId)
- `IX_VoteTypeId` (VoteTypeId)

## dbo.VoteTypes

Approximately 15 rows.

| Column | SQL type | Nullable | Identity |
|---|---|---|---|
| Id | int | no | yes |
| Name | varchar(50) | no |  |

Observed indexes:

- `PK_VoteType__Id` (Id) — clustered PK
