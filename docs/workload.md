# Workload and integration plan

This is a packaging plan for the implementation phase, not a runnable workload yet. All calls should work independently against an existing eligible user/post/tag. New IDs can be returned for manual inspection, but no multi-step browser session is required.

## Initial mix

Start with the following relative call frequencies, then adjust after measuring durations and useful completed operations. Percentages refer to invocations, not CPU time or logical reads.

| Operation group | Share |
|---|---:|
| Question page and comment reads | 18% |
| Question lists, tag filters, search and related questions | 18% |
| User profile, user posts, directory and cards | 10% |
| Tag details, leaderboards, badge lists and history | 9% |
| Question/profile view counters and user access | 12% |
| Question/answer voting and vote removal | 12% |
| Create questions, answers and comments | 10% |
| Edit profiles/posts/comments and retag questions | 7% |
| Acceptance, close/reopen, links and comment deletion | 3% |
| Create users | 1% |
| **Total** | **100% (55% reads / 45% writes)** |

Do not mistake 45% write invocations for 45% of server work. Body search, tag parsing over many posts, badge aggregates and profile aggregates can dominate runtime. Keep expensive operations represented at lower frequency; measure rather than imposing timing targets before implementation.

## Selecting parameters

Deliver SQLQueryStress-ready SQL batches plus separate parameter-selection queries. Several SQLQueryStress instances can run distinct operation groups concurrently. A batch can choose among operations locally if weighted selection is desired; there is no need for a database dispatcher procedure or permanent ID pool.

Select existing IDs of the correct type, rather than a random integer between 1 and MAX(Id), because IDs have gaps. For a cheap broad sample, choose an integer starting point and seek the next eligible ID with wraparound; acknowledge that this is gap-biased, not statistically uniform. Alternative preselected pools may live in the client or exported local files, not new database tables. Avoid sorting millions of rows by NEWID() for every call. Measure parameter-query cost separately.

A paired parameter query may return related values within one row (question+answer+owner for acceptance, comment+author for edits). That is not a required chain of mutations. Acceptance should draw an existing child answer and its question owner. New answers draw open questions; vote actors differ from post owners; comment edits/deletes draw the recorded author. Retagging should include a genuinely changed valid set often enough to exercise writes.

Use several independently runnable scenarios:

- Broad existing-ID reads and writes across the snapshot.
- A small hot set of popular questions/users to produce ordinary contention.
- New content creation alongside existing-content modification.
- Targeted conflict/no-op runs for duplicate votes, missing IDs, repeated acceptance and repeated close/reopen.
- Expensive discovery/aggregation runs to mix longer queries with short operations.

Keep the primary throughput run supplied with eligible IDs so it does not mostly measure NotFound/Conflict/NoChange. A vote-removal run can query attributed type-2/3 votes already present; if none exist, it can wait for an independent voting run or explicitly exercise the NoChange path. Do not delete anonymous imported votes to generate successful removals. Report outcome distribution alongside call count.

Use old dates from the dataset as well as current newly generated dates. Defaulting every query to the last day on a restored 2018/2024 snapshot produces mostly empty results. Include both common and uncommon tags, low/high reputation users, short/long body text and posts with few/many children. Avoid hard-coded maximum IDs or fixed known sample IDs in release examples.

## Validation on an authorized disposable restore

1. Compare core schema and lookup values with the capture. Inventory only the planned 43 Stackish objects. Confirm no base-schema or index changes.
2. Run one successful call and one missing-target call for every procedure. Verify returned column order/types, page bounds, sort modes and NULL behavior.
3. Check mutation deltas relative to before values: question/tag/history creation; parent answer/comment counts; votes/score/user counters; edits; acceptance and links. Do not equate imported counters with recomputed totals.
4. Exercise same-target concurrent operations: duplicate vote attempts/removals, answer/comment creation, retagging, close/reopen and identical links. Assert no lost deltas, duplicate attributed votes/links, partially applied actions or left-open transactions.
5. Test a controlled failure partway through a multi-table operation and confirm rollback. Do this through an isolated validation harness on the disposable copy, not intentionally defective shipped SQL or changes to base constraints.
6. Start mixed sessions and observe errors, outcome frequencies, duration and workload growth. Ordinary blocking/deadlocks may occur under load; do not hide failures or add deliberate transaction defects. Distinguish correctness failures from tuning opportunities.
7. Restore from backup and repeat installation and a compact smoke run. Repeat on the release 2024-04 database; do not require its execution plans to match the custom-index research server.

The original research inspection used metadata and bounded reads only. Step-1 implementation and database testing are recorded separately in [the tag implementation notes](components/07-tags-implementation.md); full-workload validation remains outstanding.
