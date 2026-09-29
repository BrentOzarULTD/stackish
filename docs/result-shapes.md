# Shared result shapes

These ordered columns are the contract for the shorthand names used in component briefs. All nullable source values stay nullable; author fields can be NULL after a left join. `Id` keeps its base-table identity value; do not renumber results. Derived counts and sums are bigint, with zero for empty groups. Read procedures return only the specified sets, not an extra status set.

| Shape | Ordered columns |
|---|---|
| UserCard | UserId int, DisplayName nvarchar(40), Reputation int, Location nvarchar(100), CreationDate datetime, LastAccessDate datetime |
| QuestionSummary | QuestionId int, Title nvarchar(250), Score int, ViewCount int, AnswerCount int, CommentCount int, Tags nvarchar(150), CreationDate datetime, LastActivityDate datetime, ClosedDate datetime, AcceptedAnswerId int, OwnerUserId int, OwnerDisplayName nvarchar(40), OwnerReputation int |
| QuestionDetail | All QuestionSummary columns, then Body nvarchar(max), FavoriteCount int, LastEditDate datetime, LastEditorUserId int |
| AnswerDetail | AnswerId int, QuestionId int, Body nvarchar(max), Score int, CommentCount int, CreationDate datetime, LastActivityDate datetime, LastEditDate datetime, OwnerUserId int, OwnerDisplayName nvarchar(40), OwnerReputation int, IsAccepted bit |
| Comment | CommentId int, PostId int, Text nvarchar(700), Score int, CreationDate datetime, UserId int, DisplayName nvarchar(40) |
| UserPost | PostId int, PostTypeId int, QuestionId int, Title nvarchar(250), Score int, CreationDate datetime, LastActivityDate datetime, IsAccepted bit |
| LinkedQuestion | LinkId int, QuestionId int, RelatedQuestionId int, LinkTypeId int, CreationDate datetime, TargetTitle nvarchar(250) |
| TagToken | TagName nvarchar(150) |
| UserProfileDetail | All UserCard columns, then AboutMe nvarchar(max), WebsiteUrl nvarchar(200), Age int, Views int, UpVotes int, DownVotes int |
| UserStats | UserId int, QuestionCount bigint, AnswerCount bigint, CommentCount bigint, BadgeCount bigint |
| UserTag | TagName nvarchar(150), PostCount bigint, TotalScore bigint |
| UserBadgeSummary | Name nvarchar(40), AwardCount bigint, MostRecentAward datetime |

QuestionSummary.AnswerCount and CommentCount are stored counters, not reconciled counts. AcceptedAnswerId is returned only when it resolves to a type-2 child of the question; otherwise NULL. This normalization is output-only. OwnerUserId/UserId optional references normalize 0 to NULL; preserve a positive dangling ID and return NULL for its missing joined author fields.

For UserPost, QuestionId is the question's own Id for type 1, or ParentId for type 2. Title is the question title, including for an answer. If an answer's question is missing, preserve the answer with its ParentId and NULL Title. IsAccepted is true only for answers referenced by their valid parent; questions always return false. An answer's Tags are derived from its parent only where a feature needs tags; never assume answer rows carry tags.

For QuestionDetail, use the same zero-to-NULL normalization on LastEditorUserId. Other nullable counters are returned as stored unless the brief specifies an aggregate. The parser's TagToken output contains no guaranteed order; procedures impose their documented ordering.
