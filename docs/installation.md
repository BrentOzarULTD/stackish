# Install, validate, operate, reset

Stackish targets SQL Server 2025 (major version 17+) and compatibility level 170+. Use a disposable restored Stack Overflow database. Final release validation targets **2024-04**. The operator restored that copy for the desktop wave; see [current validation](desktop/validation.md). Earlier 2018-06 research results are retained separately.

## Select the database and deploy

Choose the database explicitly in every connection. Do not rely on the login's default database: this research login previously defaulted to a smaller restore. In SSMS, verify the selected database before running anything. In SQLQueryStress, set the main and parameter connections to the same intended database. Check `SELECT DB_NAME(), SERVERPROPERTY('ProductVersion');`.

From the repository root, using SQLCMD mode:

```sh
# Enter credentials through your normal secure connection mechanism.
# With SQL authentication, set SQLCMDPASSWORD outside the repository; omit -P.
sqlcmd -S <server> -U <login> -d <database> -b -i sql/deploy.sql
```

Use your connection's appropriate TLS/certificate options. No endpoint, password, or saved SQLQueryStress connection is shipped. Keep saved connection settings outside the repository.

[sql/deploy.sql](../sql/deploy.sql) is the complete entry point. Relative `:r` paths require the repository root as working directory. It:

1. Runs [preflight](../sql/preflight.sql), rejecting system databases, older engines/compatibility, missing or incompatible base columns, missing Id primary keys, extra required columns that prevent inserts, and incorrect required lookup ID/label pairs. Required reference meanings are checked; unused enum rows and extra nullable/defaulted columns are permitted. Lookup and inventory comparisons explicitly use database collation, avoiding catalog/database collation conflicts.
2. Checks [supporting indexes](indexes.md) and creates missing access paths, reusing suitable existing indexes under any name. Initial builds on the large restore take time, disk and log space and may block callers; deploy before starting a workload.
3. Creates/alters `Stackish_SplitTags` first, then every public procedure. No procedure calls another procedure as a mandatory dependency.
4. Checks the exact [43-object inventory](../sql/inventory.sql), reporting missing, extra, or wrong-kind `dbo.Stackish_` objects. It never drops extras.

Deployment is repeatable and does not seed/repair data, change base columns/constraints or replace existing indexes, or change database settings. `CREATE OR ALTER` preserves existing module permissions. The per-module ANSI_NULLS/QUOTED_IDENTIFIER settings are module creation settings, not database changes. Missing supporting indexes are the explicitly authorized exception to the original no-index scope. A deployment failure stops the script; earlier indexes or module definitions may already have been installed. Resolve the reported problem and rerun the whole entry point. No all-database transaction or schema migration is implied.

## Validate before starting load

The Python validation client consumes every result set and reads exact SQL type metadata (including int versus bigint and varchar versus nvarchar) from python-tds 1.17.1. Its pinned dependency matters because the driver exposes those details through an internal metadata API. Expectations are independently transcribed from component briefs into [contracts.json](../tests/integration/contracts.json), not inferred from procedure implementations.

```sh
python3 -m venv .venv
.venv/bin/pip install -r tests/integration/requirements.txt
python3 tests/integration/validate.py static
python3 tests/integration/workload.py --static

# Supply these environment variables locally, without committing their values:
# STACKISH_SERVER, STACKISH_DATABASE, STACKISH_USER, SQLCMDPASSWORD
# Optional STACKISH_TIMEOUT (seconds, default 600).
.venv/bin/python tests/integration/validate.py deploy --allow-mutations
.venv/bin/python tests/integration/validate.py smoke --allow-mutations
.venv/bin/python tests/integration/edges.py --allow-mutations
.venv/bin/python tests/integration/release.py --allow-mutations
.venv/bin/python tests/integration/contention.py --allow-mutations --workers 8
.venv/bin/python tests/integration/workload.py
```

The deployment validation runs the entry point twice, checks base columns/constraints/settings and existing indexes are preserved, allows only named supporting-index additions on the first pass, requires unchanged metadata on the second pass, and checks all public parameters, directions and declaration defaults. Static checks compare source signatures against the contract manifest and ensure the deployment includes each object once, parser first. For an affected-workflow recheck, `smoke --allow-mutations --quick` omits seven explicitly listed expensive global read procedures; it is not a substitute for a full initial or release smoke run. The smoke suite performs a cross-component workflow in one transaction, checks counters against starting values, checks live result shapes including missing pages, and rolls back in `finally`. It deliberately avoids `INSERT ... EXEC` so it can observe all result sets and each procedure's transaction behavior.

The release suite checks both imported tag formats, exact tag membership across discovery/aggregation procedures, retag deltas and structural index reuse under another name, rolling back its fixtures and temporary index rename.

The edge suite changes only owned fixture rows to exercise missing authors, zero references and wrong-type parents, then rolls back. It checks validation errors under inherited XACT_ABORT OFF and ON. Components 02–05 and 09 can roll back a caller's entire transaction on unexpected errors; no test assumes savepoint isolation. Successful routines must leave transaction counts and inherited options unchanged.

The contention client commits identifiable fixture users/posts/tags, coordinates separate sessions behind locks on owned rows, checks overlap through `sys.dm_exec_requests`, and deletes owned rows afterward. It needs permission to inspect server requests. It does not add WAITFOR to workload SQL, change a procedure to a defective version, or alter a base constraint. It checks vote duplication/removal, score/reputation deltas, view/answer/comment counters, retags, links, closing versus answer creation, and a forced overflow on an owned fixture to verify full rollback. This is bounded correctness testing, not throughput measurement.

Rollback still consumes identity values. Never reseed to conceal gaps. Imported orphan records can refer to newly allocated IDs; tests abort on incompatible vote/link collisions rather than deleting those imported rows. Cleanup does not reconstruct imported counters. If a client is killed or connectivity is lost during committed fixture tests, inspect the logged exact IDs and marker; cleanup may require manual verification. Do not use broad name-pattern deletes or wipe all rows referencing a newly assigned user ID.

The final command above runs **parameter queries only**, including SchemaOnly/Get Columns compatibility and NOEXEC compilation of the main batches, reporting row counts and preparation durations. The default checks the combined single-window pair, including every packaged target through its typed JSON projection. Main batches are not executed without `--run`. Optional `--groups` selects numbered scenarios for focused checks. Use `--compile-only` to check metadata/compilation without fetching parameter data. Empty bounded windows fail validation: rerun to select another window, or choose an appropriate wider local window. Do not start a run with an empty pool. Component acceptance files remain available for more exhaustive individual feature checks; they are separate from this integration suite.

## Start and stop SQLQueryStress

See [workload instructions](../workload/README.md) and [mix](workload.md). Initially run a small finite iteration count. Inspect errors and outcomes before increasing threads. There is no permanent dispatcher or server-side loop. Use one instance with the combined batch and its single parameter mapping; its threads choose operations automatically.

For a separately authorized bounded mixed run, the optional evidence client executes the same packaged batches:

```sh
.venv/bin/python tests/integration/workload.py --run --allow-mutations --calls 100 --threads 4
```

This command commits mutations to selected existing content. It is **not part of deployment or smoke**, and must not be run while the load-test query is awaiting review. It emits each batch's duration, outcomes, row counts, exceptions and a summary. Connection setup is measured separately; these client timings are not SQL Server CPU/reads or SQLQueryStress performance numbers.

To stop, click Cancel in the SQLQueryStress window and wait for execution/rollback to finish. Let bounded evidence runs drain their current calls. Verify there are no remaining Stackish sessions with active requests or open transactions before resetting. SQLQueryStress exceptions are errors only: `NotFound`, `Conflict` and `NoChange` are successful SQL executions, so an exception count of zero does not prove useful work. Capture outcome distributions with the evidence client alongside SQLQueryStress CPU, elapsed time and reads.

## Reset by restoring a backup

Deployment does not reset content. Stop all callers, allow transactions to finish, and have the operator restore the chosen clean backup into the intended disposable database using normal SQL Server restore procedures. Verify server, database name, backup dataset date and file paths first. Restoring over an existing database, dropping one, or replacing it requires explicit authorization; no reset script performs these actions automatically.

After an authorized restore, verify compatibility without changing it, rerun `sql/deploy.sql`, then smoke/edge checks and parameter validation. The entry point recreates missing supporting indexes and reuses suitable existing ones; it does not copy every research index. Record which indexes were created/reused. Tag/body searches and global aggregations can remain costly; deployment does not attempt to eliminate every scan. Clear any desktop baseline after a restore.
