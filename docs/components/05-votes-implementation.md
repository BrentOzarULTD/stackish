# Votes Implementation Notes

Implemented objects:

- `dbo.Stackish_UpvoteQuestion`
- `dbo.Stackish_DownvoteQuestion`
- `dbo.Stackish_UpvoteAnswer`
- `dbo.Stackish_DownvoteAnswer`
- `dbo.Stackish_RemovePostVote`
- `dbo.Stackish_GetPostVoteSummary`

The four vote entry points have the same body with different constants (post type, vote type, score delta, reputation delta, actor counter column). There is no shared helper object, per the contract.

Every vote write starts by taking an update lock on the target post row and holds it to commit. That lock serializes every vote change on one post, so the duplicate check against `Votes` and the insert/delete that follows cannot interleave with another call for the same post, without a uniqueness constraint. The row is updated anyway (Score), so the lock costs nothing extra. Actor and owner counters change in one `UPDATE ... WHERE Id IN (@actor, @owner)` so both users' rows are locked in key order, which avoids a lock-order deadlock between two users voting on each other's posts.

Rules as implemented:

- Order of checks: missing post → `NotFound`; wrong post type, self-vote, or actor not a positive existing user → `Conflict`; then the actor's attributed type-2/3 votes on that post decide: any opposite vote → `Conflict`, otherwise any same vote → `NoChange`, otherwise apply.
- Anonymous imported votes (`UserId` NULL/0) never match an actor. `@UserId` 0/NULL/negative is an invalid actor (`Conflict`), so nobody can claim or remove them.
- Deltas: Score ±1; owner Reputation +10/-2 with `GREATEST(1, ...)`; actor UpVotes/DownVotes +1. Missing, NULL or dangling owners skip the reputation update. Removal reverses Score, decrements the actor counter floored at 0, and applies -10/+2 floored at 1, so reputation near 1 is not exactly reversible (tested).
- `RemovePostVote` with more than one matching attributed vote returns `Conflict` and repairs nothing; the up-vote procedures treat existing duplicate same-type votes as `NoChange`.
- Voting does not touch LastActivityDate or acceptance.
- `GetPostVoteSummary` returns stored Score beside counts of type-2/3 rows; they are not reconciled.

Transactions: each write sets `XACT_ABORT ON`, opens a transaction (nesting inside a caller's), and commits on every status outcome. Unexpected errors roll back the whole transaction, including a caller's outer transaction, and rethrow. There are no input-validation throws in this component.

Validation authored and executed on the authorized disposable `StackOverflow` research database (2018-06 dump, SQL Server 2025 CU9, compat 170):

- `tests/05-votes/acceptance.sql`: every procedure's normal path and missing target, same-vote NoChange, opposite-vote Conflict, self-vote, wrong type, invalid/NULL/zero/negative actor, dangling and NULL owners, anonymous historical votes, floor-1 reputation in both directions, actor counter floor, pre-existing duplicate and mixed attributed votes, summary vs stored score, result shape metadata. Checks every counter, score and reputation before/after with `IS DISTINCT FROM`. Passed.
- `tests/05-votes/concurrency.sh 20`: 20 identical upvotes (1 Applied, 19 NoChange, one row, one delta), 20 opposite votes (all Conflict), 20 identical removals (1 Applied), 20 different voters at once (no lost score/reputation/counter updates), a forced overflow error after the vote row and score were written (nothing persisted), and the same error inside a caller transaction (whole transaction rolled back, no open transaction). Passed.
- The race harness was checked against a deliberately broken local build of `UpvoteQuestion` without the post lock: it failed with 20 Applied. The broken build was replaced immediately.

Not executed: the 2024-04 restore. See the handoff notes about the Votes lookup index.
