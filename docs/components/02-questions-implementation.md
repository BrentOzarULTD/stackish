# Questions Implementation Notes

Implemented objects:

- `dbo.Stackish_CreateQuestion`
- `dbo.Stackish_EditQuestion`
- `dbo.Stackish_RetagQuestion`
- `dbo.Stackish_RecordQuestionView`

Question writes validate text lengths before converting to bounded table columns. Tag writes validate the raw bracketed input for complete syntax, duplicate tokens, token count and storage length before calling `dbo.Stackish_SplitTags`; the stored tag string uses catalog spelling ordered by tag name. The procedures do not create tags.

Create and retag operations adjust `Tags.Count` by local deltas in the same transaction as the post/history changes. Retagging uses a transaction-owned application lock per question so concurrent retags cannot both calculate deltas from the same starting tag set. Question edits compare `varbinary(max)` values so case-only and trailing-space-only changes are treated as real edits under the research database collation.

Multi-table mutations set `XACT_ABORT ON` and roll back their own transaction on error. Tests that deliberately catch thrown validation errors set `XACT_ABORT OFF` at the session level and isolate those checks.

Validation authored:

- `tests/02-questions/acceptance.sql` covers create/edit/retag/view normal paths, missing targets, wrong post type, missing actor, no-op edit/retag, initial and edit history, tag-count deltas, invalid tag syntax/duplicates/unknown tags/oversized input, and rollback of rejected create calls.
- `tests/02-questions/concurrency.sh` covers separate-session concurrent view increments.

Checks run on the authorized disposable `StackOverflow` database:

- Deployment scripts for 07 Tags, 02 Questions, 03 Answers and 04 Comments.
- `tests/02-questions/acceptance.sql`
- `tests/02-questions/concurrency.sh` with 20 parallel calls

Remaining integration coverage: concurrent retag races should be exercised in a broader cross-component run.
