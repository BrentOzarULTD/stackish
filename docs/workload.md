# Integrated workload mix

The runnable package is in [workload/](../workload/README.md), with one main batch, one parameter query, and one mapping for a single SQLQueryStress instance. All ten feature components are integrated. The original 43-object plan matches the actual inventory exactly: 42 procedures and one inline tag parser. No dispatcher, ID-pool table or schema migration was added. The desktop/release follow-up adds explicitly authorized [supporting indexes](indexes.md) during deployment.

## Invocation budget

The starting plan remains **55% read / 45% write invocations**. Two percentage points from discovery and one from catalog are isolated into an expensive group; two counter points form the hot-target group. Percentages apply to calls, not CPU, logical reads, elapsed time, concurrent sessions or bytes returned.

| Branch inside the single batch | Invocation share | Operations |
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

## Run the mix in one window

Follow the [six setup steps](../workload/README.md). Paste `workload/calls.sql` and `workload/parameters.sql`, map `TargetsJson` to `@InputTargets`, choose threads and iterations, and Start. All threads run the same batch. Each invocation rolls a random integer from 0 through 99 and selects exactly one group according to the table, then one procedure within that group. There is no required sequence and no chain of returned IDs. Multiple threads provide concurrency across whatever operations they choose.

SQLQueryStress iterations are **per thread**: four threads and 25 iterations means 100 calls total. The percentages are probabilities, so that run will not produce exactly 55 reads and 45 writes. A complete finite run approaches the intended mix as call counts grow. Canceling early can further skew completed-call proportions because slow operations may still be in flight. Thread count controls overall concurrency; operators do not allocate threads or quotas among groups.

All threads share this mix, so long scans can temporarily occupy every thread. This is part of the workload, not a promise of a steady background write rate. The 3% expensive branch is not the only costly branch: global discovery, profiles and catalog reads may also be expensive. Start with a small finite run, inspect costs and outcomes, and increase concurrency only when appropriate. No artificial delays, transaction wrapper, session-policy changes or persistent dispatcher are added.

The research smoke run demonstrates substantial cost differences; see [validation evidence](integration-validation.md). Body/tag membership search, global sorts, related questions and profile/badge aggregation may dominate resources at low invocation frequency. Parameter-query cost is setup work and is recorded separately. Deployment now supplies missing supporting access paths; the workload imposes no latency targets.

## Keep normal calls useful

The combined selector uses bounded ID windows, existing positive actors, correct post types, open questions for answers, and valid question/answer/owner tuples for acceptance. Vote actors differ from owners; removals touch only attributed type-2/3 votes. Anonymous historical votes remain anonymous. Live-state choice in voting, retagging, acceptance, moderation and linking reduces repeated no-ops when SQLQueryStress reuses cached parameter rows. If a cached creation target has closed, the answer branch adds a comment instead; a close after that check can still race. Races can legitimately return Conflict, NoChange or NotFound.

Short runs, pool refresh, and outcome distributions are essential. Do not equate zero SQL exceptions with successful mutations. Separate intentional missing-ID/duplicate/no-op experiments from the normal mix. Existing counters are authoritative baselines for local deltas, not totals to reconstruct from incomplete historical events. IDs can be zero, missing or dangling, including orphan records pointing at identities allocated later.

Sampling is biased toward bounded regions of ID space and sampled post owners; it is not statistically uniform. The package never sorts millions of rows randomly per call. Tag/body queries can still scan large tables because the base schema lacks indexed token membership. Search dates are drawn from actual stored dates, preserving useful reads on old snapshots. The creation/retag pair concentrates traffic on two short existing tags; vary that local choice for wider tag distributions.

## Validation boundary

[Installation](installation.md) covers repeatable deployment, exact signatures/result sets, rolled-back workflows, committed/cleaned contention fixtures, and reset by operator-authorized backup restore. The optional evidence client defaults to this same single batch with bounded call counts and reports exceptions, outcomes and durations.

SQLQueryStress remains unrun. The operator subsequently restored the 2024-04 release copy and authorized live desktop-engine tests and supporting indexes. See [desktop/release validation](desktop/validation.md) for the actual executed checks, outcomes and remaining gaps; historical research results alone do not establish release compatibility.
