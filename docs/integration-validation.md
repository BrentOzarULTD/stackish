# Integration validation — September 30, 2026

Historical report. The subsequent desktop wave received a 2024-04 restore and explicit authorization to install supporting indexes. See [current release validation](desktop/validation.md); the remaining gates below describe the earlier wave, not the latest server state.

Started from fetched `main` at `79107be` (the merge of PR #5), on branch `codex/integration-workload-packaging`. GitHub reported no open PRs at the start; all ten components were available. No contributor PR was merged by this integration session.

## Inventory and delivered package

The original component totals reconcile exactly: 6 + 4 + 3 + 4 + 6 + 5 + 3 + 4 + 4 + 3 = **42 procedures**, plus `Stackish_SplitTags` = **43 objects**. There are no unexplained omissions or additions. `sql/inventory.sql` contains the complete named inventory; `tests/integration/contracts.json` contains the independent signature/result contract for each object.

Delivered: complete SQLCMD deployment/preflight/inventory; exact metadata and multi-result smoke validation; reference/session/pagination checks; bounded contention and rollback validation; one mixed SQLQueryStress batch with one parameter query and one mapping; 13 optional individual scenarios; an optional bounded evidence client; and installation, operation, parameter mapping, sampling, mix and reset documentation. Integration added no persistent database helpers, tables, indexes, constraints or settings.

## What ran

Authorized target: the existing research `StackOverflow` database, supplied as the **2018-06** snapshot with customized indexes. Observed engine **17.0.5005.3**, compatibility **170**, database collation `SQL_Latin1_General_CP1_CI_AS`. No database was restored, dropped or replaced.

| Check | Actual result |
|---|---|
| Offline source signatures and deployment coverage | Passed: all 43 declarations match the contract manifest, no duplicates/missing objects, parser first |
| Complete deployment, repeated | Passed twice after final module/preflight changes; base column/index/constraint and checked database-setting metadata unchanged |
| Live parameter names/order/types/lengths/directions/defaults | Passed for all 43 objects; parser output also checked on the final workflow run |
| Full integration smoke | Passed: 93 procedure calls, exact ordered SQL result types/names, normal and applicable missing-target cases, every page result set, cross-component workflow; fixtures rolled back |
| Final affected-workflow smoke | Passed after narrow module fixes and additional history, anonymous-vote preservation, acceptance-side-effect and profile-aggregate delta assertions; the quick rerun explicitly omitted seven expensive global reads already exercised in full smoke |
| Reference, pagination and inherited-session checks | Passed after fixes: wrong-type parent, missing/zero author/reference, missing user with surviving posts, unknown catalog tag, one-answer page, per-post comment limit including imported orphan comments, zero comment limit, XACT_ABORT OFF/ON behavior |
| Contention | Passed: 14 observed-overlap gates, eight workers each (nine for close plus eight answers); vote/remove, distinct voters, view/answer/comment counters, retag, link/unlink, close/reopen, close versus answer creation |
| Controlled unexpected failure | Expected arithmetic overflow 8115 on an owned fixture, after multi-table vote work began; whole caller transaction rolled back, no partial vote/score change, transaction count zero |
| Cleanup | Rolled-back smoke/edge fixtures; committed contention fixtures deleted by owned IDs. No reseeding, imported orphan cleanup, or counter reconstruction |
| SQLQueryStress parameter setup | All 13 selectors returned usable non-NULL mapped rows and matched SchemaOnly/Get Columns metadata |
| Workload batch compilation | All 13 batches compiled with NOEXEC and typed inputs; **not executed** |
| SQLQueryStress / bounded mixed workload | **Not run**, as requested pending load-query review |
| 2024-04 release restore | **Not available / not tested** |

The full smoke initially exercised the merged component implementations. The final deployment added the narrow changes below; final workflow/edge checks exercised the affected reads and mutations. Known-tag discovery's original query branch was unchanged. The expensive full suite was not repeated merely to reproduce its scan timings.

Full-smoke outcomes were 29 Applied, 4 NoChange, 2 Conflict and 21 NotFound, plus 37 read calls. Negative outcomes were explicitly expected assertions (missing IDs, duplicate votes, closed-answer rejection), **not a measurement of the proposed normal workload's success rate**. All 42 procedures were called. CreateUser has no missing entity argument; its invalid-input path is checked separately. Unfiltered global directories have no meaningful missing-ID call.

The final contention run recorded 125 successful procedure calls: 67 Applied, 42 NoChange, 14 NotFound and 2 Conflict, plus the separately caught expected overflow. Duplicate votes/removals/retags/links/closes/reopens applied exactly once; competing deletes/removals returned expected missing/no-change outcomes. All 14 gates observed every worker waiting before release. In the close/answer race, **six answers committed before closing and two returned Conflict**; the stored answer-count delta matched six and no answer had a creation date after closure. This checks correctness under overlap, not throughput capacity. No unexpected database error or correctness assertion remains in the final executed suites.

## Findings and narrow fixes

- `GetUserPosts` and the post set in `GetUserProfile` joined a parent by ID without requiring a question. A rolled-back fixture reproduced a false title and `IsAccepted=1` when its parent pointed to a type-2 row. Both joins now require `PostTypeId=1`, retaining the answer and its ParentId with NULL title/false acceptance when the parent is invalid.
- `GetUserPosts` could expose orphan posts for a missing user. It now returns the contract's typed empty set when the user does not exist. Question pages still preserve content with missing authors.
- `GetPostHistory` now normalizes an optional historical UserId of zero to NULL, matching the shared reference contract. A rolled-back owned-history fixture verifies this without changing imported history.
- `GetQuestionsByTag` did not require the tag to exist in the catalog. It now returns the same typed empty shape before scanning Posts for an unknown tag, even if a legacy post carries that unregistered token.
- Catalog/database collation differences broke an early inventory comparison. Inventory and lookup comparisons now explicitly use database collation. Actual lookup-column collations match the database; no collation was changed.
- A first CTE-only parameter selector produced an unexpectedly costly plan. That owned read-only validation session was stopped. Final selectors materialize bounded local table variables, pass SQLQueryStress's SchemaOnly metadata request, and add no persistent state.
- Imported `Comments.PostId` references, like previously documented votes/links/badges, can attach historical rows to newly created identities. A first pagination assertion incorrectly expected its fresh comment to be oldest. The final check uses the actual existing rows; imported comments were never deleted to manufacture a clean fixture.

Development failures in the client harness (metadata adaptation, observing transaction state across RPC/batch boundaries, and a quick-suite variable name) were corrected and their affected checks rerun. Uncaught XACT_ABORT errors can roll back a transaction at batch end; the final session-policy test observes `XACT_STATE()` inside the SQL CATCH. The controlled overflow test also keeps its BEGIN/CATCH in one SQL batch. Contributor implementations were not restyled.

## Observed durations

These are individual client-observed smoke calls over the remote connection, not a load benchmark or promised latency. They include result consumption and client/network overhead. Cache state, parameters and the research custom indexes matter.

| Call | Observed duration |
|---|---:|
| Typical successful mutation | Approximately 0.06–0.08 s |
| Question page (five populated sets) | 0.089 s |
| User profile (fixture user, all five sets) | 2.883 s |
| Question list (newest, two rows) | 103.992 s |
| Known-tag question list (two rows) | 87.936 s |
| Related questions (two rows) | 177.372 s |
| Tag leaderboard (two rows) | 86.637 s |
| Badge directory (two rows) | 9.246 s |
| Unknown-tag question list before catalog guard | 86.794 s |
| Unknown-tag unanswered query (empty) | 227.019 s |

The unknown-tag guard's final edge call returned empty in approximately one network round trip. Unanswered/tag/body/related queries can still be expensive; no index or broad query refactoring was added. A read-only server inspection during a slow scan showed no blocking session and a parallel-query wait. This wave does not claim a full performance diagnosis.

Final parameter-validation durations, including the SchemaOnly check and data fetch: most groups **0.19–0.35 s**, catalog **4.115 s**, expensive-search preparation **1.269 s**. Returned pools were 512 rows for most groups, 8 for hot counters, 128 for expensive reads, and one unused run marker for the two parameter-free groups. These are setup costs, not per-invocation work. Compiling the main batches was performed separately with NOEXEC.

## Single-window packaging follow-up

The default is now [workload/calls.sql](../workload/calls.sql) plus [workload/parameters.sql](../workload/parameters.sql). One SQLQueryStress instance randomly selects the same 55% read / 45% write mix. Its only mapping is `TargetsJson` to `@InputTargets`; related targets are packaged together automatically. All threads share the mix, including expensive operations and eight hot targets. The numbered scenarios remain optional, and the evidence client now defaults to the combined pair. A maintainer-only generator and freshness check keep the standalone SQL consistent with the numbered source scenarios and manifest shares.

Checks actually run for this follow-up:

- The first read-only check found `dbo.Stackish_SplitTags` missing from the shared research database. Repeated the authorized complete deployment twice: all 43 signatures/defaults passed, and checked base metadata remained unchanged. No workload or fixture calls were made.
- The combined selector passed SchemaOnly/Get Columns compatibility and returned **512 non-NULL JSON payloads**. Each payload was decoded through SQL Server's actual typed projection for all **10 parameterized branches**, preserving every value and tuple; the other two branches need no targets. The hot set contained **eight distinct question/owner pairs**.
- The combined workload compiled with typed input under **NOEXEC**, without executing its calls. Two successful combined parameter preparation, compilation and JSON round-trip checks took **8.639 and 15.760 seconds** on the research copy (the latter after retaining the source search-text Unicode width); this is not per-call overhead or a load benchmark.
- Offline routing checks covered every random value 0–99 and matched all 12 manifest shares; named procedure arguments also matched the public contracts. Generated-file freshness, contract inventory, Python compilation and whitespace checks passed.

Content creation now checks whether a cached answer target is still open; if already closed, it adds a comment instead. This avoids accumulating predictable closed-question conflicts when moderation runs in the same window. The procedure still arbitrates a close that races after the check. This changed branch compiled but has **not been executed** as part of the workload.

No SQLQueryStress GUI run, bounded mixed run, new mutation smoke, or throughput measurement was performed in this follow-up. Prior component/smoke results above remain historical evidence; the single-window mix's actual success distribution and GUI execution remain unverified.

## Remaining release gates

- Review the actual [single-window batch and mapping](../workload/README.md) before any SQLQueryStress or mixed execution. The proposed random mix remains 55% read / 45% write invocations, with 3% expensive-branch reads and a 2% hot-counter share. Normal-load outcome frequencies and resource consumption have **not** been measured.
- Validate schema/lookups, all result contracts, mutations, contention, parameter setup, and an approved bounded mixed run on the **2024-04** release dataset. The research copy does not establish release-copy compatibility or performance. Inspect its actual indexes, especially attributed vote lookup support; do not add indexes silently.
- An operator-authorized restore/reset/redeployment cycle has not run. No restore/drop/replace was authorized or attempted.
- This wave did not rerun every contributor's standalone acceptance/concurrency file. Those historical results remain in their notes; the integration suites above are the checks actually run here.
- Independent PR review is required. Stop at the PR; do not merge.
