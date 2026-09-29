# Votes and reputation

## Scope and ownership

Base tables: Votes, Posts, Users.
Dependencies: None; acceptance belongs to 03.

Own future files under `sql/05-votes/` and `examples/05-votes/`; do not edit other components. Deliver working code for this assignment, examples, and a short implementation/validation note. This brief authorizes file preparation, not deployment to the research server.

## Procedure contracts

| Name (after Stackish_) | Parameters | Output | Behavior |
|---|---|---|---|
| `UpvoteQuestion` | `@QuestionId int, @UserId int` | Write | Apply type-2 vote to a question. |
| `DownvoteQuestion` | `@QuestionId int, @UserId int` | Write | Apply type-3 vote to a question. |
| `UpvoteAnswer` | `@AnswerId int, @UserId int` | Write | Apply type-2 vote to an answer. |
| `DownvoteAnswer` | `@AnswerId int, @UserId int` | Write | Apply type-3 vote to an answer. |
| `RemovePostVote` | `@PostId int, @UserId int` | Write | Remove only the actor-attributed up/down vote on a question or answer. |
| `GetPostVoteSummary` | `@PostId int` | PostId int, Score int, RecordedUpVotes bigint, RecordedDownVotes bigint | One row for an existing question/answer; otherwise empty. Do not equate row counts with historical score. |

## Acceptance checks

Check same-vote no-op, opposite-vote conflict, self-vote, wrong type, missing owner, anonymous historical votes, floor-1 reputation behavior and existing duplicate attributed votes. Race two identical votes and two removals; require one applied delta and no duplicate insert. Check each counter, score and owner reputation before/after.

Also apply common input, missing-ID, no-op and unexpected-error rules. Writes must be all-or-nothing. Provide a normal call and missing-target example per procedure, plus the component-specific checks above. Run mutations only on an explicitly authorized disposable database; report unrun checks honestly.
