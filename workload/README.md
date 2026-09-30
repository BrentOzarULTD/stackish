# SQLQueryStress package

Each numbered directory contains an executable `calls.sql` batch and matching `parameters.sql`. The baseline uses groups 01–12; group 13 is an optional substitution. Nothing runs merely by deploying Stackish. No permanent dispatcher or ID pool is installed.

## Set up each window

1. Follow [installation](../docs/installation.md) and validate the database first. Configure SQLQueryStress's Database connection with an explicit database; use the same database for parameter selection.
2. Paste the entire group's `calls.sql` into the main query area. There are no GO separators. Variables beginning **`@Input`** are supplied by SQLQueryStress; other variables are local to the batch.
3. Open Parameter Substitution, paste the matching `parameters.sql`, and use Get Columns. Map the returned columns to the `@Input...` variables listed below. For groups 02 and 10, no mappings are required; leave Parameter Substitution disabled (their parameter files simply return a run marker).
4. Inspect the parameter result before starting. It must have eligible rows and no NULL mapped values. The read-only Python parameter validator is an alternative precheck. All mapped values from one result row belong together, especially question/answer/owner tuples. Do not combine independently randomized columns.
5. Use finite iterations and threads; enable **Force Client Retrieval of Data** to consume page results. Start the desired windows near the same time. Set an explicit timeout appropriate to the expensive operations; timeouts are evidence, not a reason to hide exceptions.
6. Cancel every window to stop, wait for cleanup, and reload parameter pools before the next run.

SQLQueryStress obtains a parameter set, cycles its rows and reuses values when exhausted. The selection query is setup work, not a fresh eligible-ID lookup on every invocation. See the [upstream guide](https://github.com/ErikEJ/SqlQueryStress/wiki) for parameter mappings, per-thread iteration counts, cancellation and retrieval options. The [upstream load engine](https://github.com/ErikEJ/SqlQueryStress/blob/66497b0ce647b732449e4c737a5daa14b72bda06/src/SQLQueryStress/LoadEngine.cs) advances a shared parameter-row counter and consumes every result set when forced retrieval is enabled. Main batches do cheap state checks where pool reuse would otherwise cause predictable no-ops. These checks are not transactional promises: procedures arbitrate races and their outcomes remain visible.

| Directory | Returned column → main-query input |
|---|---|
| 01-pages | QuestionId → @InputQuestionId |
| 02-discovery | None |
| 03-users | UserId → @InputUserId |
| 04-catalog | PostId → @InputPostId; UserId → @InputUserId; TagName → @InputTagName |
| 05-counters | QuestionId → @InputQuestionId; UserId → @InputUserId |
| 06-votes | PostId → @InputPostId; PostTypeId → @InputPostTypeId; UserId → @InputUserId |
| 07-content | QuestionId → @InputQuestionId; UserId → @InputUserId; TagName → @InputTagName |
| 08-edits | PostId → @InputPostId; PostTypeId → @InputPostTypeId; UserId → @InputUserId; Tag1 → @InputTag1; Tag2 → @InputTag2 |
| 09-maintenance | QuestionId → @InputQuestionId; AnswerId → @InputAnswerId; UserId → @InputUserId; RelatedQuestionId → @InputRelatedQuestionId |
| 10-registration | None |
| 11-hot-counters | QuestionId → @InputQuestionId; UserId → @InputUserId |
| 12-expensive | QuestionId → @InputQuestionId; TagName → @InputTagName; SearchText → @InputSearchText; FromDate → @InputFromDate; ToDate → @InputToDate; BadgeName → @InputBadgeName |
| 13-comment-maintenance | CommentId → @InputCommentId; UserId → @InputUserId |

[manifest.json](manifest.json) records the same mappings and baseline shares in machine-readable form. [docs/workload.md](../docs/workload.md) explains the invocation mix and concurrent runs.

## What one invocation does

Each batch invokes exactly one public procedure. Branches choose operations locally; no stored dispatcher is created. Page, directory, profile/card, tag/badge/history reads use existing IDs. Counters increment existing targets. Votes select positive non-owner actors and only treat that actor's type-2/3 vote as removable; NULL/zero historical votes are never claimed. A vote call inserts or removes according to current state, so it does not require another call first. Pre-existing duplicate attributed votes are excluded from the setup pool.

Creation chooses existing positive users, initially open questions and valid catalog tags. It returns IDs for inspection but never requires chaining them to the next invocation. Creation and post editing vary text with a GUID; approximately one in five bodies contains a longer example (about 16,000 characters), while titles/comments stay short. Editing therefore exercises actual changes. Retagging alternates two valid tag sets. Acceptance alternates setting a valid existing child answer and clearing it; the selected question owner acts. Closing/reopening and links similarly use current state to select one action. Group 13 pairs each comment with its recorded existing author, and includes physical deletion.

Write batches intentionally modify imported content and counters. Profile edits replace optional fields, post edits replace title/body, and retags replace the tag set. Use a disposable database. No mutation infrastructure, time delays or database-setting changes are part of these calls.

## Sampling and pool lifetime

The broad selectors choose an integer pivot using MAX(Id), seek up to 4,096 consecutive existing post IDs, and wrap to lower IDs if necessary. Eligibility filtering happens after this bounded window has been materialized in a local table variable. At most 4,096 posts and 512 users are retained; wraparound fills only the remaining capacity. They pair up to 512 positive existing users with those posts. There is no per-call whole-table random sort. Tags are extracted only from the sampled questions; creation/retagging uses two short, unambiguous existing catalog tags. Selectors use local table variables, which disappear at batch end, and no temporary or permanent tables and are compatible with the SchemaOnly metadata request used by SQLQueryStress’s Get Columns button.

This is deliberately gap-biased and clustered around a random ID window, with a bounded wraparound. IDs near larger gaps are more likely to begin a sample; activity, age and author distributions are not uniform. User reads favor authors of sampled posts. The creation/retag tag pair favors the first suitable catalog IDs, so it concentrates tag-counter traffic; choose another valid pair locally to explore common/uncommon tags. Badge-recipient search uses the first award's badge name. Expensive search text and dates come from an actual sampled title/date, so an old snapshot isn't accidentally filtered to “yesterday.” No claim of statistical realism is made for these choices.

The hot group keeps eight sampled question/owner pairs stable for the run. They become hot through repeated access; the selector does not scan the entire database to discover globally popular questions. For hot voting/retag/link exploration, reduce the appropriate group's final TOP to a small pool, keeping its eligibility predicates and tuple mappings intact.

Eligibility can change after setup. Another session may close a question, remove a comment, or win a vote/link race. Occasional Conflict/NoChange/NotFound is expected. Keep runs bounded, reload pools, and measure outcomes. **Group 13 must not run more total calls (threads × iterations) than returned rows**; deleted rows otherwise accumulate stale NotFound results. If a pool is empty, rerun its selector or deliberately widen its local window; do not substitute random missing IDs. Votes can be expensive even during setup when the restore has no useful attributed-vote lookup index.

For a targeted missing/no-op demonstration, use individual component examples or explicit IDs in a separate window and label those results separately. Do not pollute the normal success-oriented mix with intentional conflicts.
