# Step 1: tags and parsing implementation

Implements [component 07](07-tags.md) as four public objects on SQL Server 2025 / compatibility 170:

| Object | Purpose |
|---|---|
| `dbo.Stackish_SplitTags` | Inline TVF returning distinct tag tokens under database collation |
| `dbo.Stackish_ListTags` | Literal prefix search, popularity/name/newest sorting and paging |
| `dbo.Stackish_GetTagDetail` | Stored tag count, excerpt and wiki body |
| `dbo.Stackish_GetTagTopUsers` | Answer-owner leaderboard for an exact question tag |

## Installation and calls

Run from the repository root in SQLCMD mode, choosing the target database explicitly. Supply credentials using your normal connection mechanism; they are not stored here.

```sh
sqlcmd -S <server> -d <database> -b -i sql/07-tags/deploy.sql
sqlcmd -S <server> -d <database> -b -t 600 -i examples/07-tags/calls.sql
```

[Deployment](../../sql/07-tags/deploy.sql) checks the engine/compatibility floor, creates the parser first, then creates or alters the three procedures. It does not change compatibility, base tables, indexes or data. The paths in its `:r` commands are relative to the repository root. Individual object scripts can also be executed in their listed order in a query tool that understands GO batches.

[Call examples](../../examples/07-tags/calls.sql) choose a catalog tag and a nonexistent tag at runtime. They include normal and empty-result calls for every procedure. These are read-only, but the existing-tag leaderboard can be expensive; allow enough timeout for the restored database and its storage.

## Implementation choices

- The parser uses STRING_SPLIT with ordinals to distinguish completed tokens from an unfinished final fragment. It accepts closed fragments beginning with one `<`, excludes nested opening brackets and empty/whitespace-only tokens, and preserves the remaining token text. It does not validate a complete write request, enforce five tags, canonicalize spelling or detect duplicates after DISTINCT. Space, tab, CR and LF are treated as blank here and by required-name validation.
- Name-prefix searches escape `~`, `%`, `_` and `[` before using LIKE. NULL or empty prefixes match all names. Each sort has an explicit Id tie-breaker; wiki bodies are joined after selecting the tag page.
- Wiki lookups are LEFT JOINs requiring a positive pointer and the correct post type (4 for excerpts, 5 for wiki bodies). Missing/zero/wrong-type targets retain the tag with NULL text.
- The leaderboard checks that the tag exists, resolves catalog spelling, and materializes exact matching question IDs in a local temp table. It matches `<tag>` with CHARINDEX instead of splitting every tag on every question. It then counts type-2 child answers from existing positive users. Missing/nonpositive owners are excluded. Catalog duplicates do not multiply answers.
- COUNT_BIG and SUM over bigint score values avoid int overflow. Stored Tags.Count is displayed as-is, independent of actual matching questions.
- No explicit transactions are opened by these read procedures, and no user data is changed. Multi-statement leaderboard reads are not a consistent snapshot when writes occur concurrently. Validation errors use THROW and inherit the caller's XACT_ABORT/transaction behavior.
- These problems did not require a SQL Server 2025-only feature. The implementation uses ordinary T-SQL without an older-version compatibility promise.

## Validation

Executed September 29, 2026 on the authorized `StackOverflow` 2018-06 research database, SQL Server 2025 CU9 / compatibility 170:

- Deployed all four objects, then redeployed successfully using CREATE OR ALTER.
- [Acceptance checks](../../tests/07-tags/acceptance.sql) passed with controlled fixture rows in the existing Users, Posts and Tags tables. Covered parser NULL/empty/Unicode/punctuation/deduplication/malformed-fragment/length cases; all directory sorts and paging; literal wildcard and Unicode prefixes; stored counts; valid, zero, dangling and wrong-type wiki pointers; exact-tag isolation; missing/nonpositive owners; wrong post types; duplicate catalog names; deterministic leaderboard ties; a 4,000,000,000 score aggregate; and empty unknown-tag results.
- Ran the complete read-only example script successfully against imported data, including the `.net` leaderboard and unknown-tag calls.
- Fixture rows were rolled back. Identity allocations still advanced; no reseeding was performed.
- After broadening blank checks to include tabs/CR/LF, reran the affected parser and invalid-input assertions successfully. That small change did not alter the already-tested catalog or leaderboard queries.
- [Metadata assertions](../../tests/07-tags/metadata.sql) passed. They now reject missing/wrong-kind objects, parameter count/order/name/type/length/direction mismatches, changed/missing/added defaults, and parser/directory/detail result count/order/name/type mismatches. The leaderboard's local temp table prevents static result discovery for that branch; acceptance checks exercise its returned shape with INSERT ... EXEC.
- Verified the revised assertions against 13 deliberate deployed-definition regressions: extra/reordered/renamed/retyped/resized parameters; changed/missing/added defaults; renamed/retyped/extra/reordered result columns; and an extra parser output column. Each alteration was rolled back, the original definition was checked, and the final unmodified metadata check passed. No procedure behavior changed in this review fix.

Run the checks on an authorized disposable restore:

```sh
sqlcmd -S <server> -d <database> -b -t 600 -i tests/07-tags/acceptance.sql
sqlcmd -S <server> -d <database> -b -i tests/07-tags/metadata.sql
```

The fixture suite assumes the research database's case-insensitive collation and unused positive ID 2147483647 for dangling-reference cases, checking the latter before use. Fixture tests should not be run inside an existing caller transaction. A failed/cancelled connection can require rollback time; let cleanup finish before restoring or rerunning.

## Metadata default checks

SQL Server does not expose T-SQL parameter defaults through `sys.parameters`; see [Microsoft's catalog documentation](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-parameters-transact-sql?view=sql-server-ver17). The test therefore also compares the four simple declaration headers from `sys.sql_modules`, normalizing keyword case and spaces/tabs/line endings. This is deliberately not a general SQL parser: comments or alternative syntax inside a header fail the check and require an explicit test update. Procedure bodies are not compared.

## Limits and review focus

The public schema has no indexed tag-to-question mapping. Existing-tag leaderboards scan question data even for rare tags, and were the slow part of acceptance testing; reserve them for lower-frequency workload calls. No index hint or new base index was added. Temp-table result metadata needs execution-based verification. Test results are from the 2018-06 research copy, not the eventual 2024-04 release restore. Concurrent mixed-write workload testing belongs to later integration; these procedures intentionally offer normal read-committed behavior rather than cross-statement snapshot consistency.
