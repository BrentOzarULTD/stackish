# Moderation and links

## Scope and ownership

Base tables: Posts, PostHistory, PostLinks; read Users.
Dependencies: None.

Own future files under `sql/09-moderation/` and `examples/09-moderation/`; do not edit other components. Deliver working code for this assignment, examples, and a short implementation/validation note. This brief authorizes file preparation, not deployment to the research server.

## Procedure contracts

| Name (after Stackish_) | Parameters | Output | Behavior |
|---|---|---|---|
| `CloseQuestion` | `@QuestionId int, @UserId int, @Reason nvarchar(max)` | Write | Immediate close and type-10 history, with required nonblank reason; repeated close NoChange. |
| `ReopenQuestion` | `@QuestionId int, @UserId int` | Write | Clear ClosedDate and add type-11 history; already open NoChange. |
| `AddQuestionLink` | `@QuestionId int, @RelatedQuestionId int, @UserId int, @LinkTypeId int=1` | Write | Type 1 linked or 3 duplicate. Both IDs must be questions. Return new or existing LinkId as EntityId. NoChange only when the same directed triple already exists. |
| `RemoveQuestionLink` | `@LinkId int, @UserId int` | Write | Delete the specific link after validating actor. Do not change closure or history. |

## Acceptance checks

Check close/reopen repeats and race behavior, self/wrong-type links, invalid link type, reversed link direction, duplicate insertion races, and exact LinkId deletion. Adding a duplicate link must not implicitly close the question.

Also apply common input, missing-ID, no-op and unexpected-error rules. Writes must be all-or-nothing. Provide a normal call and missing-target example per procedure, plus the component-specific checks above. Run mutations only on an explicitly authorized disposable database; report unrun checks honestly.
