# Comments

## Scope and ownership

Base tables: Comments, Posts; read Users.
Dependencies: None.

Own future files under `sql/04-comments/` and `examples/04-comments/`; do not edit other components. Deliver working code for this assignment, examples, and a short implementation/validation note. This brief authorizes file preparation, not deployment to the research server.

## Procedure contracts

| Name (after Stackish_) | Parameters | Output | Behavior |
|---|---|---|---|
| `AddComment` | `@PostId int, @UserId int, @Text nvarchar(max)` | Write | Add to a question or answer, increment CommentCount on that exact post. |
| `EditComment` | `@CommentId int, @UserId int, @Text nvarchar(max)` | Write | Only the original author may edit. Preserve CreationDate and Score. |
| `DeleteComment` | `@CommentId int, @UserId int` | Write | Only original author may delete; decrement parent counter once. Missing parent does not prevent deleting an existing owned comment; skip its counter. |
| `GetPostComments` | `@PostId int, PAGE` | Comment | CreationDate ascending then Id ascending. Missing post returns empty even if orphaned comments exist. |

## Acceptance checks

Check question and answer comments, 700-character limit, foreign author, repeated deletion, nonexistent parents, missing comment authors on reads, and concurrent add/delete counter deltas. No comment vote procedures.

Also apply common input, missing-ID, no-op and unexpected-error rules. Writes must be all-or-nothing. Provide a normal call and missing-target example per procedure, plus the component-specific checks above. Run mutations only on an explicitly authorized disposable database; report unrun checks honestly.
