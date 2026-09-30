-- The original plan is exactly 42 procedures + 1 inline TVF. Extras are reported, never dropped.
DECLARE @Expected table(Name sysname, Kind char(2));
INSERT @Expected VALUES
(N'Stackish_AddComment','P'),
(N'Stackish_AddQuestionLink','P'),
(N'Stackish_CloseQuestion','P'),
(N'Stackish_CreateAnswer','P'),
(N'Stackish_CreateQuestion','P'),
(N'Stackish_CreateUser','P'),
(N'Stackish_DeleteComment','P'),
(N'Stackish_DownvoteAnswer','P'),
(N'Stackish_DownvoteQuestion','P'),
(N'Stackish_EditAnswer','P'),
(N'Stackish_EditComment','P'),
(N'Stackish_EditQuestion','P'),
(N'Stackish_GetBadgeRecipients','P'),
(N'Stackish_GetPostComments','P'),
(N'Stackish_GetPostHistory','P'),
(N'Stackish_GetPostVoteSummary','P'),
(N'Stackish_GetQuestionPage','P'),
(N'Stackish_GetQuestionsByTag','P'),
(N'Stackish_GetRelatedQuestions','P'),
(N'Stackish_GetTagDetail','P'),
(N'Stackish_GetTagTopUsers','P'),
(N'Stackish_GetUnansweredQuestions','P'),
(N'Stackish_GetUserBadges','P'),
(N'Stackish_GetUserCard','P'),
(N'Stackish_GetUserPosts','P'),
(N'Stackish_GetUserProfile','P'),
(N'Stackish_ListBadges','P'),
(N'Stackish_ListQuestions','P'),
(N'Stackish_ListTags','P'),
(N'Stackish_ListUsers','P'),
(N'Stackish_RecordProfileView','P'),
(N'Stackish_RecordQuestionView','P'),
(N'Stackish_RecordUserAccess','P'),
(N'Stackish_RemovePostVote','P'),
(N'Stackish_RemoveQuestionLink','P'),
(N'Stackish_ReopenQuestion','P'),
(N'Stackish_RetagQuestion','P'),
(N'Stackish_SearchQuestions','P'),
(N'Stackish_SetAcceptedAnswer','P'),
(N'Stackish_SplitTags','IF'),
(N'Stackish_UpdateUserProfile','P'),
(N'Stackish_UpvoteAnswer','P'),
(N'Stackish_UpvoteQuestion','P');
IF EXISTS(SELECT Name,Kind FROM @Expected EXCEPT SELECT name COLLATE database_default AS name,type COLLATE database_default AS type FROM sys.objects WHERE schema_id=SCHEMA_ID('dbo'))
 OR EXISTS(SELECT name COLLATE database_default AS name,type COLLATE database_default AS type FROM sys.objects WHERE schema_id=SCHEMA_ID('dbo') AND name LIKE N'Stackish[_]%' EXCEPT SELECT Name,Kind FROM @Expected)
BEGIN
 SELECT COALESCE(e.Name,o.name) AS ObjectName,e.Kind AS ExpectedKind,o.type AS ActualKind
 FROM @Expected e FULL JOIN (SELECT name COLLATE database_default AS name,type COLLATE database_default AS type FROM sys.objects WHERE schema_id=SCHEMA_ID('dbo') AND name LIKE N'Stackish[_]%') o ON o.name=e.Name
 WHERE e.Name IS NULL OR o.name IS NULL OR e.Kind<>o.type;
 THROW 51004, 'Stackish inventory differs from 43 documented objects; inspect missing/extra objects.', 1;
END;
PRINT 'Stackish inventory verified: 42 procedures and 1 inline table-valued function.';
GO
