# Moderation and Links Implementation Notes

Implemented objects:

- `dbo.Stackish_CloseQuestion`
- `dbo.Stackish_ReopenQuestion`
- `dbo.Stackish_AddQuestionLink`
- `dbo.Stackish_RemoveQuestionLink`

Close and reopen update-lock the question row, then check type, actor and current state, then set/clear `ClosedDate`, bump `LastActivityDate` and write one type-10 (Comment = reason) or type-11 (Comment NULL) history row with a new RevisionGUID, all in one transaction. Repeats are `NoChange` with no history. The reason is validated (non-NULL, not only spaces/tabs/CR/LF) before any work and stored whole in `PostHistory.Comment` (nvarchar(max)).

Interaction with component 03: `CreateAnswer` reads `ClosedDate` under `UPDLOCK, HOLDLOCK` on the same question row, so close and answer creation serialize. An answer either commits before the close or returns `Conflict`. No change to `CreateAnswer` was needed.

Links: `AddQuestionLink` update-locks the source question row, which serializes concurrent adds from that question through the existence check, so identical directed triples cannot both insert without a constraint. Outcomes: missing source or related question → `NotFound` with the missing ID as EntityId; answer/other-type endpoint, self-link or invalid actor → `Conflict` with `@QuestionId`; existing triple → `NoChange` with the lowest existing LinkId; otherwise `Applied` with the new LinkId. `@LinkTypeId` other than 1 or 3 (including NULL) throws 50902, treated like a bad allowlist argument. Duplicate links (type 3) never close the question or write history, and reopening never removes links. `RemoveQuestionLink` deletes exactly the given LinkId after checking the actor; a second removal is `NotFound`.

Transactions: same policy as component 05. `XACT_ABORT ON` after input validation, commit on every status outcome, full rollback (including a caller's transaction) and rethrow on unexpected errors. Validation errors are thrown before the procedure sets `XACT_ABORT`, so under a caller's `XACT_ABORT ON` they still doom that caller's open transaction.

Validation authored and executed on the authorized disposable `StackOverflow` research database:

- `tests/09-moderation/acceptance.sql`: close/reopen normal paths with history contents, repeats, closed question rejecting `CreateAnswer` and reopened question accepting it, missing/wrong-type targets, invalid actors, blank/NULL/whitespace reasons, a long Unicode reason, default/explicit link types, repeated triple, reverse direction, duplicate link not closing, self/answer links, missing endpoints, invalid link types, exact LinkId removal leaving closure/history alone, removal by an invalid actor, reopen preserving links. Passed.
- `tests/09-moderation/concurrency.sh 20`: 20 identical closes and 20 identical reopens (one Applied and one history row each), close racing 20 `CreateAnswer` calls (e.g. 15 applied before the close, 5 Conflict, no answer dated after the close, AnswerCount matches rows), 20 identical link adds (one row, every caller gets the same LinkId), 20 identical removals (1 Applied, 19 NotFound), and a close whose history insert hits a lock timeout (Posts update rolled back). Passed.
- Harness checked against broken local builds without the question-row lock in `AddQuestionLink` (20 duplicate links) and `CloseQuestion` (20 Applied); both failed as expected and the real procedures were redeployed.

Not executed: the 2024-04 restore.
