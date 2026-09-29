# Questions

## Scope and ownership

Base tables: Posts, PostHistory, Tags; read Users.
Dependencies: 07 tag parser.

Own future files under `sql/02-questions/` and `examples/02-questions/`; do not edit other components. Deliver working code for this assignment, examples, and a short implementation/validation note. This brief authorizes file preparation, not deployment to the research server.

## Procedure contracts

| Name (after Stackish_) | Parameters | Output | Behavior |
|---|---|---|---|
| `CreateQuestion` | `@UserId int, @Title nvarchar(max), @Body nvarchar(max), @Tags nvarchar(max)` | Write | Insert question, initial history, and tag-count deltas atomically. |
| `EditQuestion` | `@QuestionId int, @EditorUserId int, @Title nvarchar(max), @Body nvarchar(max), @EditSummary nvarchar(max)=NULL` | Write | Replace title/body only. Write history only for changed fields. |
| `RetagQuestion` | `@QuestionId int, @EditorUserId int, @Tags nvarchar(max), @EditSummary nvarchar(max)=NULL` | Write | Validate and normalize tags, adjust membership deltas, and write type-6 history. Equivalent tag sets are NoChange. |
| `RecordQuestionView` | `@QuestionId int` | Write | Increment ViewCount only on a question, once per call; no distinct-viewer tracking. |

## Acceptance checks

Check multiple tags, the 150-character combined limit, duplicate/missing/malformed tags, initial history, no-op edit/retag, legacy missing author, wrong post type, and concurrent retags/view increments. Validate tag-count deltas against before values, not a full recount.

Also apply common input, missing-ID, no-op and unexpected-error rules. Writes must be all-or-nothing. Provide a normal call and missing-target example per procedure, plus the component-specific checks above. Run mutations only on an explicitly authorized disposable database; report unrun checks honestly.
