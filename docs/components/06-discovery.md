# Question discovery

## Scope and ownership

Base tables: Read Posts, Users, PostLinks, Tags.
Dependencies: 07 parser. No calls to other procedures required.

Own future files under `sql/06-discovery/` and `examples/06-discovery/`; do not edit other components. Deliver working code for this assignment, examples, and a short implementation/validation note. This brief authorizes file preparation, not deployment to the research server.

## Procedure contracts

| Name (after Stackish_) | Parameters | Output | Behavior |
|---|---|---|---|
| `ListQuestions` | `@Sort varchar(20)='newest', PAGE` | QuestionSummary | Allow newest (CreationDate desc), active (LastActivityDate desc), score (Score desc), views (ViewCount desc). Include closed questions. |
| `SearchQuestions` | `@Text nvarchar(200)=NULL, @TagName nvarchar(150)=NULL, @OwnerUserId int=NULL, @MinScore int=NULL, @HasAccepted bit=NULL, @FromDate datetime=NULL, @ToDate datetime=NULL, @SearchBody bit=0, PAGE` | QuestionSummary | AND supplied filters; literal text substring in Title, or Title OR Body when SearchBody=1. Created date range. Order Score desc, Id desc. NULL text/tag disables that filter; empty supplied text/tag is invalid. |
| `GetQuestionsByTag` | `@TagName nvarchar(150), @Sort varchar(20)='active', PAGE` | QuestionSummary | One exact tag; sorts active/newest/score as above. Unknown tag yields empty. |
| `GetUnansweredQuestions` | `@TagName nvarchar(150)=NULL, @Mode varchar(20)='no_answers', PAGE` | QuestionSummary | Modes no_answers (no actual type-2 children) or no_solution (no valid accepted answer AND no child answer with positive score). Open questions only; newest first. Do not rely on AnswerCount for eligibility. |
| `GetRelatedQuestions` | `@QuestionId int, PAGE` | QuestionSummary | Other questions sharing at least one exact tag; order shared-tag count descending, Score descending, Id descending. Missing source returns empty. This is tag overlap, not semantic search. |

## Acceptance checks

Check java vs javascript, tags with punctuation, wildcard characters as literal search, empty result sets, combined filters, date boundaries, both unanswered definitions, zero/dangling acceptance and deterministic pagination. Unknown authors must not hide question results. Do not require a full-text index.

Also apply common input, missing-ID, no-op and unexpected-error rules. Writes must be all-or-nothing. Provide a normal call and missing-target example per procedure, plus the component-specific checks above. Run mutations only on an explicitly authorized disposable database; report unrun checks honestly.
