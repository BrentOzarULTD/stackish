# Initial-deployment indexes

The operator explicitly expanded the original integration scope to include missing workload indexes. `sql/deploy.sql` runs [indexes.sql](../sql/indexes.sql) after base-schema preflight and before the tag parser and procedures. It creates nonunique rowstore indexes only; no new constraints, tables, settings, data repair, dispatcher or ID pools.

| Table | Leading keys | Purpose |
|---|---|---|
| Votes | PostId, UserId | Attributed vote checks/removal and per-post summaries |
| Posts | ParentId, PostTypeId | Answers, acceptance checks, unanswered tests and tag leaderboard joins |
| Posts | OwnerUserId, PostTypeId | User posts, profile totals and tag aggregates |
| Comments | PostId, CreationDate, Id | Comment lists and per-post page previews |
| Comments | UserId | Profile comment totals |
| Badges | UserId, Name | User awards and profile summaries |
| Badges | Name, Date descending, Id descending | Badge recipients and a narrower source for the directory |
| PostLinks | PostId, RelatedPostId, LinkTypeId | Duplicate link checks and question-page links |
| PostHistory | PostId, CreationDate descending, Id descending | History pages |
| Tags | TagName | Catalog validation, tag joins and retag counters |
| Posts | PostTypeId, CreationDate descending, Id descending | Newest questions; included tags/supporting columns provide a narrower search source |
| Posts | PostTypeId, LastActivityDate descending, Id descending | Active questions |
| Users | Reputation descending, Id ascending | Default user directory |

These are 13 access-path specifications, separate from the 43 procedure/function inventory. The script reports Created or Reused for each. An enabled, unfiltered rowstore index under any name qualifies if the leading key columns match in order and direction (or all directions are reversed). Extra trailing keys are allowed. INCLUDE columns are coverage choices for new indexes, not a reason to duplicate an existing seek path. A disabled, hypothetical, filtered or differently ordered index does not satisfy this general-purpose requirement. If an access path is missing but its intended Stackish index name is already in use with an incompatible definition, deployment stops instead of replacing it.

No indexes include Body, comment Text, history Text or other max-length content. Existing index definitions are never rebuilt, renamed or dropped by deployment. The new indexes have maintenance/storage costs and initial creation can block activity; install before starting load and allow enough database/log space and time. No ONLINE/compression/filegroup/recovery-model assumptions are imposed. If creation fails, resolve the reported capacity/permission issue and rerun: completed indexes are reused. The default Python deployment check's 600-second command timeout can be raised with `STACKISH_TIMEOUT` for the initial large builds.

`ListQuestions` recompiles its selected sort statement so its CASE ordering can fold to the newest/active ordering index. Other contributor query styles are preserved. Tag membership and body substring searches still have no dedicated token/full-text index, and expensive aggregates still do real work. Expensive reads remain part of the simulated database activity.

The desktop connection test is read-only and checks schema/lookups/module inventory. It never silently builds an index. Run the complete deployment after a restore; rerun it to verify/recreate missing access paths before measuring a new baseline.
