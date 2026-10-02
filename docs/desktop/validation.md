# Desktop and 2024-04 release validation

This follow-up builds on the unmerged integration PR #6 (`5950ffb`) and fetched main `79107be`. No contributor PR was merged. The desktop app uses Claude's supplied design as reference, with the requested before/after QPS comparison. The original integration report remains [historical evidence](../integration-validation.md).

## Target and release discoveries

The operator restored the **2024-04** copy and authorized testing on the existing `StackOverflow` testbed, then explicitly authorized missing workload indexes as part of initial deployment. Observed engine **17.0.5005.3**, compatibility **170**. The highest initial post ID was 78253176, dated **2024-03-31 23:59:19.670**. Initial counts: 59,819,048 posts, 22,484,235 users, 238,984,011 votes, 90,380,323 comments, 51,289,973 badges, 6,552,590 links and 65,675 tags. PostHistory was empty. This session did not perform the restore, drop or replace a database.

Unlike the earlier research copy, the workload tables initially had only their clustered Id primary keys. There were no Stackish modules. Preflight first rejected nullable `PostHistory.RevisionGUID`; accepting that compatible snapshot variant was the only base-schema check adjustment. New history writes still supply GUIDs. Complete module deployment then passed twice with unchanged base metadata and all 43 signatures/defaults.

The first full smoke attempt, before supporting indexes, passed 29 calls (24 Applied, four NoChange and the five-result-set question page), then timed out on GetUserProfile after 600 seconds. The question page took 181.008 seconds; attributed votes/removals took approximately 5.9 seconds each. Fixtures rolled back, identities were not reseeded, and a subsequent server check found no remaining Stackish test sessions or open transactions. This attempt was not a passing full smoke.

The initial desktop-engine readiness check passed, but parameter selection stopped with “No eligible rows for 04-catalog.” Inspection found imported tags encoded as `|java|html|`, not `<java><html>`. The parser and exact-membership reads now accept both forms; new writes retain the existing bracket-delimited input/storage contract. Retagging uses actual old/new token sets, preserving stored-counter deltas without rewriting imported content.

The operator's subsequent index authorization is implemented in [initial-deployment indexes](../indexes.md). This is an explicit scope expansion: 13 access-path specifications are separate from the unchanged **42 procedures + one TVF** inventory. No table/column/constraint/settings migrations or permanent dispatcher/ID-pool objects were added.

## Desktop checks completed

- .NET 10 Release build: zero warnings/errors. Locked dependency restore passed.
- **12 core tests passed**, covering measured bucket boundaries/stalls, equal-elapsed comparison, zero/short baselines, incompatible settings, baseline persistence without passwords, seeded operation selection, SQLCMD batch boundaries, preparation cancellation, no dispatch after Stop, drain cancellation, and empty-target rejection.
- Actual Avalonia controls rendered in nine offline scenarios, including 960×640 and 1000×700. Compact layout overlap was fixed by scrolling the monitor while keeping Start/Stop fixed in the left rail. Review screenshots are explicitly marked illustrative.
- The self-contained Apple Silicon Mac app launched as a native window. Windows x64 and Intel Mac packages were cross-published successfully; native execution on those two targets is not yet validated.
- All three ZIP packages contain their launcher and dependencies; Mac launcher executable permissions were preserved. Builds remain unsigned/not notarized.
- The bounded live-check client refuses to execute without `--allow-mutations`. Offline CI does not invoke live checks or contain credentials.

## Indexed release checks

Initial index deployment created all **13** supporting indexes. Both the original second pass and a subsequent complete two-pass deployment reused existing indexes, preserved base columns/constraints/settings and verified all **43** signatures/defaults. The installed indexes reserve approximately **24.6 GiB** in total on this copy; this is an observed footprint, not a capacity guarantee. The entry point reports each Created/Reused decision.

Early indexed smoke observations: question page **95.52 ms**, user profile **101.45 ms**, applied question upvote **72.50 ms**, newest question list **72.72 ms**. These are individual remote fixture calls, with different cache/state conditions from the initial unindexed attempt, not a controlled throughput comparison. Global/tag reads still execute substantial work.

The full indexed smoke passed: **93 calls across all 42 procedures**, with exact ordered metadata for every result set, workflow/counter assertions and rollback. Outcomes were 29 Applied, four NoChange, two Conflict, 21 NotFound and 37 reads. Negative outcomes were deliberately asserted missing/duplicate/closed-target checks, not normal-workload success rates. The reference/pagination/inherited-session suite also passed and rolled back its fixtures.

Expensive observed smoke durations remained substantial: known-tag listing **133.150 s**, related questions **217.628 s**, tag leaderboard **25.221 s**, badge directory **16.988 s**, and a missing-tag unanswered scan **53.415 s**. No latency target or production benchmark is claimed.

The release-format suite passed parser cases for both encodings, mixed-format question pages/searches/tag lists/unanswered/related/leaderboards, exact membership (including rejection of a composite pipe-containing tag name), and unchanged/changed retag counter deltas. Owned fixtures rolled back. A temporary transactional rename of the deployment-owned Tags index proved structural reuse under a different name; all 13 specifications reported Reused and rollback restored its name.

Contention passed **14 observed-overlap gates** with eight workers (nine calls for close versus eight answers). Across 125 successful calls: 64 Applied, 42 NoChange, 14 NotFound and five Conflict. Three answers committed before closing and five correctly conflicted; stored answer/counter deltas matched. Vote duplication/removal, distinct voters, view/answer/comment counters, retags, links, closing/reopening and full rollback of the expected 8115 overflow all passed. Owned committed fixtures were deleted by ID; identities and imported rows were preserved.

The combined parameter selector passed SchemaOnly compatibility and returned **512** usable payloads, round-tripped all ten parameterized branches, retained eight hot targets and compiled the main batch with NOEXEC. Preparation/validation took **2.100 seconds** in this check.

## Actual desktop-engine mixed runs

The checked-in `Stackish.LiveChecks` client ran the same Core engine as the desktop UI, with **four workers**, the default 55%/45% invocation mix, a 60-second measurement target and the normal 30-second drain/cancel policy. It consumed every returned row/result set. No SQLQueryStress instance was used. The first baseline and all 512 target tuples were saved/reloaded through StateStore before the second run; the second reused those targets and the same per-worker seed/choices. No tuning occurred between the two runs.

| Measurement | First run | Second run |
|---|---:|---:|
| Setup (outside measurement) | 3.270 s | 2.007 s |
| Measured duration | 60.230 s | 60.172 s |
| Completed reads | 50 | 50 |
| Applied writes | 41 | 41 |
| Conflict / NoChange / NotFound | 0 / 0 / 0 | 0 / 0 / 0 |
| SQL errors | 0 | 0 |
| Calls canceled during drain | 3 | 3 |
| Active calls after completion | 0 | 0 |
| Stop-to-finished drain | 31.157 s | 34.257 s |
| Full measured average | 1.511 calls/s | 1.512 calls/s |

The matched comparison used the same first **60 seconds**: **1.5167 → 1.5167 calls/s, 0% change**. This verifies comparison mechanics, not a tuning gain. All 12 workload groups were selected in each run, including hot counters and expensive reads. Each run dispatched 95 calls: 91 completed during measurement, one read completed during drain and three reads were canceled. Drain completions were correctly excluded from measured QPS/totals. Long reads occupied the workers near the end; zero-throughput buckets remained visible. A 60-second run is a bounded functional check, not a recommendation for measuring queries that take several minutes.

A final server inspection found no remaining Stackish sessions or open transactions, with 43 modules and 13 supporting indexes still installed.

No exceptions or correctness assertions remain in the final executed suites. The early unindexed profile timeout and pipe-tag setup failure are preserved above as discoveries rather than omitted. Normal mixed writes were committed as intended, including changes to existing content; they were not undone by reconstructing imported counters. Use a backup restore to reset that workload data.

## Remaining boundaries

SQLQueryStress itself has not run. Desktop engine evidence is not a SQLQueryStress benchmark. Headless screenshot data is not server-performance evidence. The default workload commits changes to existing eligible content; restoring a clean backup is the reset, and the desktop baseline should be cleared after a restore. No automatic restore or cache flushing is implemented.

Independent review is required before merge. Public distribution still needs signing/notarization and native Windows/Intel Mac validation. Linux is deferred.
