# Tags and parsing

## Scope and ownership

Base tables: Read Tags, Posts, Users.
Dependencies: Owns the only shared function; deploy it first.

Own future files under `sql/07-tags/` and `examples/07-tags/`; do not edit other components. Deliver working code for this assignment, examples, and a short implementation/validation note. This brief authorizes file preparation, not deployment to the research server.

## Procedure contracts

| Name (after Stackish_) | Parameters | Output | Behavior |
|---|---|---|---|
| `ListTags` | `@NamePrefix nvarchar(150)=NULL, @Sort varchar(20)='popular', PAGE` | TagId int, TagName nvarchar(150), QuestionCount int, Excerpt nvarchar(max) | Sort popular Count desc, name TagName asc, or newest Id desc; append Id tie-breaker. QuestionCount is stored Tags.Count; do not recompute. |
| `GetTagDetail` | `@TagName nvarchar(150)` | TagId int, TagName nvarchar(150), QuestionCount int, Excerpt nvarchar(max), WikiBody nvarchar(max) | Left join ExcerptPostId to type 4 and WikiPostId to type 5. Missing wiki text is NULL. No match yields empty. |
| `GetTagTopUsers` | `@TagName nvarchar(150), PAGE` | UserId int, DisplayName nvarchar(40), AnswerCount bigint, TotalScore bigint | Rank answer owners for questions with this tag by summed answer Score desc, answer count desc, UserId asc. Only existing positive users; unknown tag yields empty. |

## Shared function

`dbo.Stackish_SplitTags(@Tags nvarchar(150))` is an inline TVF returning `TagName nvarchar(150)`. Follow the parser contract. This is the only extra database object allocated to this assignment.

## Acceptance checks

Check parser NULL/empty inputs, canonical multitag strings, duplicate token elimination, punctuation and non-ASCII characters. Check missing/zero wiki pointers, catalog sort ties and answer-derived tag leaderboard. Parser must not require a table type, permanent helper table or new index.

Also apply common input, missing-ID, no-op and unexpected-error rules. Writes must be all-or-nothing. Provide a normal call and missing-target example per procedure, plus the component-specific checks above. Run mutations only on an explicitly authorized disposable database; report unrun checks honestly.
