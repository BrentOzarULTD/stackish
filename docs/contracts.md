# Shared behavioral contracts

These rules specify interoperability, not coding style. They are Stackish choices, not a promise of exact Stack Overflow behavior.

## Implementation baseline

Target SQL Server 2025 with database compatibility level 170. Use features introduced in 2025 when they are appropriate for the problem; there is no requirement to showcase them or provide older-version fallbacks. The target must already meet this baseline; deployment must not change compatibility or other database settings.

## Object and call conventions

- Every object uses `dbo.Stackish_` plus the exact name in its brief. Base tables remain under dbo. No new persistent state, user-defined table types, helper tables, or index changes.
- `int` for entity IDs; `datetime` UTC for stored timestamps. Capture the current UTC time once per mutation. Generate identity values through INSERT, never MAX(Id)+1, IDENTITY_INSERT, or reseeding.
- Every required text value must be nonblank; honor storage lengths and reject oversized input instead of silently truncating it. Write text parameters deliberately use nvarchar(max) so validation sees the full input before converting to the destination length. The schema defines stored limits (for example DisplayName 40, Title 250, Comments.Text 700 and Posts.Tags 150 characters). Read filter parameters retain the bounded types shown in their briefs.
- Stored procedures use NOCOUNT. Successful writes return one row with `Outcome varchar(20)`, `EntityId int`: Outcome is `Applied`, `NoChange`, `NotFound`, or `Conflict`. No extra debug result sets. Creation returns the new identity; otherwise EntityId is the target ID (link removal uses LinkId; vote removal uses PostId).
- Missing IDs on writes return NotFound without modifying anything. Wrong post type, invalid actor, self-vote, closed question for a new answer, incompatible vote, or owner-only action by another user returns Conflict. Malformed text, bad paging or sort arguments, or invalid tag syntax throws a descriptive error >= 50000. Unexpected SQL failures propagate after rolling back changes made by the call. No success row on an error.
- Reads return typed empty result sets when the target is absent; page procedures preserve all declared result sets and their order. Aggregate summaries for an existing entity can return zeros. Reads do not change counters; separate Record... calls do that.
- Lists use `@Offset int = 0, @PageSize int = 30`, with Offset >= 0 and PageSize 1..100. Include deterministic Id tie-breakers. Sort parameters are varchar(20) allowlists. No total-count result set unless explicitly listed. Return all named columns in the declared order. Source columns retain their SQL types; aggregate counts and sums use bigint; derived IsAccepted is bit. Do not SELECT *.
- Nullable optional filters mean no filter. Date ranges are start-inclusive/end-exclusive. All human text parameters are Unicode. Query text is data, never executable SQL.

## Imported data

Zero or NULL means no optional reference. Positive IDs can still be dangling. Resolve relationships using the referenced row's type as well as ID when needed. Read joins to missing authors and wiki posts must not drop the primary content. Return NULL author fields when absent. Exclude special/nonpositive users from acting-user pools, but do not hide their imported posts.

Never recalculate historical Score, Reputation, AnswerCount, CommentCount, FavoriteCount, or Tags.Count from dump rows as part of ordinary operations. Public snapshots may omit underlying events. Preserve the initial values and apply local deltas. NULL counters are zero for increments; prevent counter underflow when decrementing. No bulk repair or backfill during deployment.

## New rows and edits

New Users: Reputation=1; UpVotes=DownVotes=Views=0; CreationDate=LastAccessDate=now; EmailHash and AccountId NULL. DisplayName is not unique. Age is optional, nonnegative, and not identity/authentication data.

New questions: PostTypeId=1; OwnerUserId=actor; Title, Body, Tags supplied; Score=ViewCount=AnswerCount=CommentCount=FavoriteCount=0; CreationDate=LastActivityDate=now. ParentId, AcceptedAnswerId, ClosedDate, CommunityOwnedDate and editor fields NULL.

New answers: PostTypeId=2; OwnerUserId=actor; ParentId=question; Body supplied; Score=ViewCount=CommentCount=0; CreationDate=LastActivityDate=now. Title, Tags, AcceptedAnswerId, AnswerCount, FavoriteCount, closure/community/editor fields NULL. Increment the parent's AnswerCount and LastActivityDate atomically. Closed questions reject new answers; existing answers can still be edited or voted on.

New comments: CreationDate=now; Score=0; positive existing UserId; PostId is an existing question or answer. Increment that post's CommentCount. Deletion is physical and decrements the same counter once. Comments do not bump post activity. No comment edit history exists in this schema.

Question and answer edits update LastEditDate, LastActivityDate, LastEditorUserId and clear LastEditorDisplayName. An answer edit also bumps its parent question's LastActivityDate if that question exists. Question title/body editing and retagging are separate operations. An editor may be any existing positive user; no ownership gate on post edits. Comment editing/deletion require its original author. Closed questions remain editable/commentable/votable.

History: creation writes initial title/body/tags (types 1/2/3 for questions, type 2 for answers). Edits write new values, not diffs (4/5/6). Only changed fields get rows, with one shared RevisionGUID per operation. Store now, PostId, actor, optional edit summary in Comment, and the new field value in Text. No-op edits create no history. There is no initial-history backfill for imported posts; the first new edit is not proof of the original text. Close/reopen record types 10/11, Comment=reason where supplied, Text=NULL. History writes belong to the mutating component, not a shared procedure dependency.

## Tags

Store 1..5 distinct existing tags in Posts.Tags as `<tag><other-tag>`, using spelling from Tags.TagName in alphabetical order under the database collation. The combined value cannot exceed nvarchar(150), even though Tags.TagName itself allows 150 characters. No tag creation or wiki editing in version 1.

The shared `Stackish_SplitTags(@Tags nvarchar(150))` inline TVF returns `TagName nvarchar(150)` and one row per distinct nonempty token in a valid bracket-delimited string, no ordinal. NULL/empty input yields zero rows. It is a parser, not a validator; callers must reject malformed write input, duplicates, unknown tags and excess tags before storing it. Deduplication follows the database collation (case-insensitive on the research copy); output order and the spelling chosen among case variants are not guaranteed. The parser keeps token text rather than trimming or canonicalizing it. Whitespace-only tokens and unclosed/nested fragments are not valid tags. Do not use the DISTINCT parser output alone to detect duplicates or validate a complete input string. Validate the full nvarchar(max) write input, including its 150-character storage limit, before calling the bounded parser. Reads of imported strings may extract valid tokens without repairing the source.

CreateQuestion increments Tags.Count once for each assigned tag. RetagQuestion adjusts only added/removed tags, in the same transaction as the post and history. Missing legacy tag rows are skipped for decrements, not invented; new tags must resolve to exactly one catalog row or the call conflicts. No new PostTags table. Exact-tag matching must respect delimiters (java is not javascript); treat SQL wildcard characters as literal input. A single-tag lookup may use CHARINDEX on the complete `<tag>` token instead of splitting every row. Use the parser when extracting multiple tokens. Optional ListTags prefixes may be empty (matching all names); required tag names must be nonblank.

## Votes and reputation

Four explicit entry points cover question/answer up/down voting. They can share private local logic within the component, but no extra database helper objects without updating the inventory.

New votes use VoteTypeId 2/3, UserId=positive actor, BountyAmount=NULL, CreationDate=now. Actor must exist and differ from the post owner. Unknown/missing owners do not block votes; skip the owner's reputation update. One attributed up/down vote per (actor, post) across types 2 and 3: same vote is NoChange; opposite vote is Conflict until the old vote is removed. Historical NULL/0 UserId votes do not belong to the caller. Never rewrite them or infer who cast them.

Apply score delta +1/-1, owner reputation delta +10/-2 (floor 1), and actor UpVotes/DownVotes +1. No daily cap, privilege threshold, community-wiki exception or downvoter reputation cost. RemovePostVote deletes the actor's single attributed type-2/3 vote, reverses its score and actor counter deltas, and applies the inverse reputation delta with floor 1. If more than one matching attributed vote already exists, return Conflict without repair. No match is NoChange. Floor clipping means reputation is not exactly reversible near 1; do not promise a full historical reputation ledger. These are deliberate simplifications. Acceptance has no reputation effects.

Vote insertion/removal and every associated counter change are atomic, including concurrent duplicate attempts. Scores and counters must not suffer lost updates. Do not reset an existing user's totals from the Votes table. Voting does not update LastActivityDate. Vote summary labels row-derived counts as RecordedUpVotes and RecordedDownVotes alongside stored Score; they need not reconcile.

## Acceptance, moderation, and links

SetAcceptedAnswer requires the question's existing owner as actor. `@AnswerId = NULL` clears acceptance; positive IDs must point to an answer of that exact question. Zero is invalid input for AnswerId. Repeating the effective choice is NoChange; treat imported 0 as no acceptance. Update AcceptedAnswerId and question LastActivityDate only. Do not modify imported type-1 Votes or fabricate acceptance history types. Only valid child-answer references are reported as accepted by reads.

Any positive existing user can close/reopen a question. Close sets ClosedDate only if open; reopen clears it only if closed. Both bump LastActivityDate and append history atomically; repeated requests are NoChange. No special moderator user table, privileges or vote counts.

PostLinks supports directed question-to-question links with type 1 or 3. No self-link. Duplicate triple (PostId, RelatedPostId, LinkTypeId) is NoChange. Reverse-direction links are distinct. A duplicate link does not close the question, and reopening does not remove links. Link removal affects exactly one LinkId. AddQuestionLink returns the missing ID as EntityId for NotFound and `@QuestionId` for Conflict (self-link, non-question endpoint, invalid actor); a LinkTypeId other than 1 or 3 is a bad allowlist argument and throws. Links have no actor column; validate the supplied actor but do not store it elsewhere. No cycle detection or canonical duplicate-chain resolution in version 1.

## Concurrent writes and freedom of implementation

The caller expects a complete action or no action. Components choose appropriate transaction/locking approaches, but must protect existence checks, duplicate prevention and associated deltas within the operation. No new uniqueness constraints are available to rescue check-then-insert races. Preserve a caller's transaction when feasible and document transaction behavior; do not leave transactions open on return. Integration tests include repeated/concurrent votes, answers, retags, comments, acceptance and links. Do not hard-code index names, force plans, add intentional failures or add NOLOCK everywhere as a blanket convention.

Use regular joins, temp tables, CTEs, subqueries, branching, parameterized dynamic SQL, or other ordinary implementations as appropriate. Contributors need not share a formatting convention, error-message prose, or query architecture. Do not add global formatting cleanup to integration.
