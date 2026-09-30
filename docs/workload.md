# Integrated workload mix

The runnable package is in [workload/](../workload/README.md), with paired main batches and parameter queries. All ten feature components are integrated. The original 43-object plan matches the actual inventory exactly: 42 procedures and one inline tag parser. No dispatcher, ID-pool table, new index or schema migration was added.

## Invocation budget

The starting plan remains **55% read / 45% write invocations**. Two percentage points from discovery and one from catalog are isolated into an expensive group; two counter points form the hot-target group. Percentages apply to calls, not CPU, logical reads, elapsed time, concurrent sessions or bytes returned.

| SQLQueryStress window / directory | Invocation share | Operations |
|---|---:|---|
| 01-pages | 18% | Question page (70%), comments (20%), vote summary (10%) |
| 02-discovery | 16% | Newest (80%) / active (20%) question lists |
| 03-users | 10% | Card (55%), posts (30%), profile (10%), directory (5%) |
| 04-catalog | 8% | Tag detail (45%), tag directory (30%), user badges (20%), history (5%) |
| 05-counters | 10% | Question view (75%), profile view (15%), user access (10%) |
| 06-votes | 12% | Question/answer up/down voting or attributed removal, based on live state |
| 07-content | 10% | Create question (20%), answer (40%), comment (40%) |
| 08-edits | 7% | Profile, question/answer edits and changed retags |
| 09-maintenance | 3% | Acceptance set/clear (45%), close/reopen (30%), link add/remove (25%) |
| 10-registration | 1% | Create user |
| 11-hot-counters | 2% | Question/profile views against eight selected targets |
| 12-expensive | 3% | Exact-tag discovery (35%), body search (20%), unanswered (15%), related (10%), tag leaderboard (10%), badge directory (5%), recipients (5%) |
| **Total** | **100%** | **55% reads / 45% writes** |

Parenthetical percentages are choices **within that group**. Group 08 chooses profile edits 10% of the time; remaining choices depend on whether the sampled post is an answer or question. For questions, the random choice sends values 10–54 to editing and 55–99 to retagging; answers always receive a body edit for values 10–99. Voting removes an existing attributed vote when present; otherwise insertion is 80% up / 20% down. Record the achieved proportions, not an invented fixed split for state-dependent branches.

Group 13 supplies comment edit/delete calls as an optional substitution within the original 7% edit and 3% maintenance budgets. For example, replace one point of edits with 90% comment edits and 10% deletes, then account for the small resulting shift explicitly. Its cached deletion targets are consumable: cap calls at the parameter-row count and reload between runs. It is not an extra 101st percentage point.

## Run concurrent operation groups

Use one SQLQueryStress instance per selected group with the corresponding batch, parameter query and mappings. Start windows together. Each completed batch invokes one public procedure. There is no required order between windows and no chain of returned IDs.

For a finite campaign of N calls, assign approximately `N × share / 100` calls to each group. SQLQueryStress iterations are **per thread**, so choose `threads × iterations` near that group quota. At N=100 with one thread per window, the iteration counts are the percentage numbers in the table. This is a small validation campaign, not a meaningful throughput benchmark. Increase only after inspecting outcomes, costs and growth. A dedicated hot scenario can use more threads and a smaller pool, outside the baseline comparison.

Equal thread shares do not yield equal invocation shares: slow scans finish fewer calls. For steady running, measure mean duration d for each group, then approximate worker allocation proportional to `share × d`, subject to the available concurrency and resource budget. Do not allocate huge numbers of scan workers merely to force a percentage. Prefer finite call quotas, lower offered rate, or document the achieved mix. Canceling all windows at one common time changes the completed-call mix because expensive windows may not have finished their quotas.

The research smoke run already demonstrates substantial cost differences; see [validation evidence](integration-validation.md). Body/tag membership search, global sorts, related questions and profile/badge aggregation may dominate resources at low invocation frequency. Parameter-query cost is recorded separately. This packaging does not add indexes or impose latency targets.

## Keep normal calls useful

The paired selectors use bounded ID windows, existing positive actors, correct post types, open questions for answers, recorded authors for comments, and valid question/answer/owner tuples for acceptance. Vote actors differ from owners; removals touch only attributed type-2/3 votes. Anonymous historical votes remain anonymous. Live-state choice in voting, retagging, acceptance, moderation and linking reduces repeated no-ops when SQLQueryStress reuses cached parameter rows. Races can still legitimately return Conflict, NoChange or NotFound.

Short runs, pool refresh, and outcome distributions are essential. Do not equate zero SQL exceptions with successful mutations. Separate intentional missing-ID/duplicate/no-op experiments from the normal mix. Existing counters are authoritative baselines for local deltas, not totals to reconstruct from incomplete historical events. IDs can be zero, missing or dangling, including orphan records pointing at identities allocated later.

Sampling is biased toward bounded regions of ID space and sampled post owners; it is not statistically uniform. The package never sorts millions of rows randomly per call. Tag/body queries can still scan large tables because the base schema lacks indexed token membership. Search dates are drawn from actual stored dates, preserving useful reads on old snapshots. The creation/retag pair concentrates traffic on two short existing tags; vary that local choice for wider tag distributions.

## Validation boundary

[Installation](installation.md) covers repeatable deployment, exact signatures/result sets, rolled-back workflows, committed/cleaned contention fixtures, and reset by operator-authorized backup restore. The optional evidence client runs these same batches with bounded call counts and reports exceptions, outcomes and durations.

**SQLQueryStress and the mixed workload have not been run in this integration wave while the load-query review is pending.** Read-only parameter validation and targeted correctness races are reported separately. The release 2024-04 copy is not available on the authorized server; research-copy success cannot establish release compatibility or performance. Before release, repeat preflight, installation, smoke/edge checks, contention checks, parameter validation and an approved bounded mixed run on 2024-04, with its actual index inventory. Reset/reinstallation after a restore also remains an operator-authorized release check.
