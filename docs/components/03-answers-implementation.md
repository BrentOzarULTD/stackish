# Answers Implementation Notes

Implemented objects:

- `dbo.Stackish_CreateAnswer`
- `dbo.Stackish_EditAnswer`
- `dbo.Stackish_SetAcceptedAnswer`

Answer creation inserts the answer, writes initial body history and increments the parent question's `AnswerCount` and `LastActivityDate` in one transaction. The parent question row is locked while the procedure checks type and closed state, so concurrent answer creation applies stored-counter deltas without lost increments.

Answer edits record body history only when the body bytes change. If the parent question still exists, it is locked before the answer and its `LastActivityDate` is bumped in the same transaction; dangling imported parents do not block editing the answer itself.

Acceptance intentionally changes only the question pointer and activity timestamp. It treats imported `AcceptedAnswerId = 0` as no accepted answer, requires the current question owner to act, and verifies a non-null answer belongs to the exact question. A transaction-owned application lock per question serializes concurrent acceptance changes.

Validation authored:

- `tests/03-answers/acceptance.sql` covers create/edit/acceptance normal paths, missing targets, closed parents, answers-to-answers, no-op edits, wrong actor, mismatched accepted answer parent, clearing acceptance with `NULL`, legacy zero acceptance, invalid input, and verifies acceptance does not create votes or change fixture reputation.
- `tests/03-answers/concurrency.sh` covers separate-session concurrent answer creation, parent answer-count deltas and edit-vs-acceptance races.

Checks run on the authorized disposable `StackOverflow` database:

- Deployment scripts for 07 Tags, 02 Questions, 03 Answers and 04 Comments.
- `tests/03-answers/acceptance.sql`
- `tests/03-answers/concurrency.sh` with 20 parallel calls

Remaining integration coverage: run these same checks on the eventual 2024-04 restore.
