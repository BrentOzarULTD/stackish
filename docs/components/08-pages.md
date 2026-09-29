# Page reads and activity

## Scope and ownership

Base tables: Read Users, Posts, Comments, PostHistory, Badges, PostLinks.
Dependencies: 07 parser for profile top tags. Result shapes agree with other components; no mandatory procedure calls.

Own future files under `sql/08-pages/` and `examples/08-pages/`; do not edit other components. Deliver working code for this assignment, examples, and a short implementation/validation note. This brief authorizes file preparation, not deployment to the research server.

## Procedure contracts

| Name (after Stackish_) | Parameters | Output | Behavior |
|---|---|---|---|
| `GetQuestionPage` | `@QuestionId int, @AnswerSort varchar(20)='score', @AnswerOffset int=0, @AnswerPageSize int=30, @CommentLimit int=10` | MULTI | Five result sets defined below. Does not record a view. |
| `GetUserProfile` | `@UserId int, @TopCount int=10` | MULTI | Five result sets defined below. Does not record a profile view or access. |
| `GetUserPosts` | `@UserId int, @PostTypeId int=NULL, @Sort varchar(20)='score', PAGE` | UserPost | Only questions/answers; optional PostTypeId=1 or 2. Score or newest descending, then Id descending. |
| `GetPostHistory` | `@PostId int, PAGE` | Id int, PostHistoryTypeId int, RevisionGUID uniqueidentifier, CreationDate datetime, UserId int, UserDisplayName nvarchar(40), Comment nvarchar(max), Text nvarchar(max) | Order CreationDate desc, Id desc. Return stored history only, no reconstruction. Missing post returns empty. |

## Page result sets

GetQuestionPage returns, in order:

1. QuestionDetail, at most one row.
2. AnswerDetail for the requested answer page. Sort score descending or newest CreationDate descending, then Id descending. Acceptance is an IsAccepted flag; it does not override the requested sort.
3. Comment rows for the question and only answers returned in result 2. At most CommentLimit per post, oldest first; order PostId, CreationDate, CommentId.
4. LinkedQuestion rows for outgoing type-1/3 links, at most 100, newest link first. Missing target rows remain with NULL TargetTitle.
5. TagToken rows for the question, alphabetical.

Answer paging follows ordinary page bounds; CommentLimit is 0..100 (default 10). Missing/wrong-type question yields five typed empty sets. The bounded comments and links are page previews; GetPostComments supplies comment paging. Reads need not be a transactionally consistent snapshot across result sets.

GetUserProfile returns, in order:

1. UserProfileDetail, at most one row.
2. UserStats, one row for an existing user: actual question/answer/comment counts and badge award count.
3. UserPost, top TopCount by Score desc then Id desc (questions and answers only).
4. UserTag, top TopCount by TotalScore desc then TagName asc; tags on owned questions plus parent tags on owned answers, one contribution per post/tag.
5. UserBadgeSummary, top TopCount grouped by name, AwardCount desc then Name asc.

TopCount is 1..100 (default 10). Missing user yields five typed empty sets. Aggregate unrelated child tables separately to avoid join multiplication. No reach metric, cross-network accounts, reputation timeline, or badge classes.

## Acceptance checks

Check all five result sets for a missing page target, anonymous/missing users, empty history, tag wiki exclusion, pagination ties, missing accepted child, comments limited per selected post, and source rows not multiplied by joins. Confirm every page read leaves counters unchanged.

Also apply common input, missing-ID, no-op and unexpected-error rules. Writes must be all-or-nothing. Provide a normal call and missing-target example per procedure, plus the component-specific checks above. Run mutations only on an explicitly authorized disposable database; report unrun checks honestly.
