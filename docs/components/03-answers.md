# Answers

## Scope and ownership

Base tables: Posts, PostHistory; read Users.
Dependencies: No procedure dependencies; shared rules match 02.

Own future files under `sql/03-answers/` and `examples/03-answers/`; do not edit other components. Deliver working code for this assignment, examples, and a short implementation/validation note. This brief authorizes file preparation, not deployment to the research server.

## Procedure contracts

| Name (after Stackish_) | Parameters | Output | Behavior |
|---|---|---|---|
| `CreateAnswer` | `@QuestionId int, @UserId int, @Body nvarchar(max)` | Write | Create answer and initial-body history; increment parent answer count/activity. Closed question is Conflict. |
| `EditAnswer` | `@AnswerId int, @EditorUserId int, @Body nvarchar(max), @EditSummary nvarchar(max)=NULL` | Write | Edit body/history and bump parent activity when parent exists. |
| `SetAcceptedAnswer` | `@QuestionId int, @UserId int, @AnswerId int=NULL` | Write | Owner-only set, replace or clear acceptance; pointer/activity only. |

## Acceptance checks

Check concurrent answer creation without lost counts, closed parents, answers to answers, body edits, mismatched parent on acceptance, wrong actor, NULL clearing, legacy zero acceptance, and repeated acceptance. Assert Votes and reputation are unchanged by acceptance.

Also apply common input, missing-ID, no-op and unexpected-error rules. Writes must be all-or-nothing. Provide a normal call and missing-target example per procedure, plus the component-specific checks above. Run mutations only on an explicitly authorized disposable database; report unrun checks honestly.
