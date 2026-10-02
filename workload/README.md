# Run Stackish in one SQLQueryStress window

After [installing Stackish](../docs/installation.md), use these two files:

- **Main query:** [calls.sql](calls.sql)
- **Parameter query:** [parameters.sql](parameters.sql)

## Start

1. Open **one** SQLQueryStress instance. Set its Database connection to your chosen Stack Overflow database. Use that same database for parameter selection. Keep credentials and saved connection settings outside the repository.
2. Paste all of **calls.sql** into the main query box.
3. Open **Parameter Substitution**, paste all of **parameters.sql**, and click **Get Columns**.
4. Make this **one mapping**; leave all other variables unmapped:

   | Returned column | Query parameter |
   |---|---|
   | `TargetsJson` | `@InputTargets` |

5. Enable **Force Client Retrieval of Data** so all page result sets are consumed. Use an execution timeout of **600 seconds** initially: some research-copy reads took several minutes even without load.
6. For a first bounded run, set **1 thread and 10 iterations**. Click **Start**. After checking the result, **4 threads and 25 iterations** gives 100 total calls. These are starting points, not validated capacity recommendations; a small run can still take minutes.

The workload automatically mixes page reads, browsing, votes, content creation, edits, counters, moderation, links, a few hot targets, and occasional expensive queries. You do not need to manage operation groups or calculate their thread counts. **Writes commit real changes**, including changes to existing content and profiles. Run against a disposable copy, or a research database explicitly authorized for these mutations.

To stop, click **Cancel** in this one window and let active work/rollback finish. A new run refreshes the parameter sample. To reset the data, stop all callers and follow the [backup restore instructions](../docs/installation.md#reset-by-restoring-a-backup); reinstalling Stackish does not reset it.

If parameter selection reports no eligible rows, rerun it before starting. Do not replace the IDs with arbitrary values. SQL exceptions indicate errors; `NotFound`, `Conflict` and `NoChange` are returned outcomes rather than exceptions. The optional [validation client](../docs/installation.md#validate-before-starting-load) can inspect parameters without running any workload calls; Python is not required to operate SQLQueryStress.

## What the default does

Each invocation randomly chooses **one public procedure call**. The intended mix is **55% reads / 45% writes**, including 3% expensive reads and 2% hot-counter calls. Short runs fluctuate; these are probabilities, not exact quotas. Expensive operations can consume most of the server's resources and occupy threads for much longer.

The parameter query runs at setup and returns up to 512 packaged target rows. SQLQueryStress cycles those rows across its threads. The package keeps related IDs together, including question/answer/owner tuples; the main query unpacks only the chosen operation's targets. No JSON editing is needed. There is no permanent dispatcher, ID-pool table, new index, or server-side workload loop.

Selection shares one bounded sample of up to 4,096 posts and 512 users, seeking from random integer ID pivots and wrapping if needed. It does not randomly sort the whole database on each call. The sample is clustered and gap-biased, not uniform; user reads favor authors, two catalog tags concentrate retag traffic, and eight sampled question/owner pairs form the hot set. Searches use dates from the stored snapshot. Live-state choices reduce predictable no-ops when cached values are reused. Concurrent changes can still cause ordinary conflicts. [Sampling details](scenarios.md#sampling-and-pool-lifetime) explain the tradeoffs.

## Optional developer material

The [numbered scenarios](scenarios.md) remain available for focused investigation; they are not steps in the normal run. Their [manifest](manifest.json) defines the default shares. Comment editing/deletion is an optional scenario and is excluded from the default because cached deletion targets are consumable.

Maintainers regenerate the two ready-to-paste files after changing a numbered scenario or its share:

```sh
python3 tests/integration/package_workload.py
python3 tests/integration/workload.py --static
```

Operators do not need to run either command. The [upstream SQLQueryStress guide](https://github.com/ErikEJ/SqlQueryStress/wiki) covers its controls.
