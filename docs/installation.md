# Install, validate, operate, reset

Stackish targets SQL Server 2025 (major version 17+) and compatibility level 170+. Use a disposable restored Stack Overflow database. Final release validation targets **2024-04**. Deployment, integration, contention, and bounded desktop checks have run against that copy. See the [README](../README.md) for the normal desktop setup and migration-rehearsal workflow.

## Select the database and deploy

Choose the database explicitly in every connection. Do not rely on the login's default database. In SSMS, verify the selected database before running anything. In SQLQueryStress, set the main and parameter connections to the same intended database. Check `SELECT DB_NAME(), SERVERPROPERTY('ProductVersion');`.

From the repository root, using SQLCMD mode:

```sh
# Enter credentials through your normal secure connection mechanism.
# With SQL authentication, set SQLCMDPASSWORD outside the repository; omit -P.
sqlcmd -S <server> -U <login> -d <database> -b -i sql/deploy.sql
```

Use your connection's appropriate TLS/certificate options. No endpoint, password, or saved SQLQueryStress connection is shipped. Keep saved connection settings outside the repository.

[sql/deploy.sql](../sql/deploy.sql) is the complete entry point. Relative `:r` paths require the repository root as working directory. It:

1. Runs [preflight](../sql/preflight.sql), rejecting system databases, older engines/compatibility, missing or incompatible base columns, missing Id primary keys, extra required columns that prevent inserts, and incorrect required lookup ID/label pairs.
2. Checks supporting indexes and creates missing access paths, reusing suitable existing indexes under any name. Initial builds on the large restore take time, disk and log space and may block callers; deploy before starting a workload.
3. Creates/alters `Stackish_SplitTags` first, then every public procedure.
4. Checks the exact [43-object inventory](../sql/inventory.sql), reporting missing, extra, or wrong-kind `dbo.Stackish_` objects. It never drops extras.

Deployment is repeatable and does not seed/repair data, change base columns/constraints or replace existing indexes, or change database settings. `CREATE OR ALTER` preserves existing module permissions. The per-module ANSI_NULLS/QUOTED_IDENTIFIER settings are module creation settings, not database changes. A deployment failure stops the script; earlier indexes or module definitions may already have been installed. Resolve the reported problem and rerun the whole entry point. No all-database transaction or schema migration is implied.

## Validate before starting load

The Python validation client consumes every result set and reads exact SQL type metadata (including int versus bigint and varchar versus nvarchar) from python-tds 1.17.1. Its pinned dependency matters because the driver exposes those details through an internal metadata API. The executable suite uses [contracts.json](../tests/integration/contracts.json) for its expected signatures and results.

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

Run these optional maintainer checks before relying on a changed build or database. They are not required each time you open the app. The commands above use a macOS/Linux virtual-environment layout; on Windows use `.venv\Scripts\python.exe` and `.venv\Scripts\pip.exe` instead.

Deployment validation executes the installer twice. Smoke and edge checks perform mutations and roll back their fixtures where practical. Contention checks temporarily commit owned fixtures, then clean them up, and require permission to inspect server requests. Run only on your disposable lab database. If a client is killed or loses connectivity, check its reported fixture IDs before manually cleaning up; do not delete imported data or reseed identities.

The final workload command checks parameter selection and compilation without executing the main workload. Mutation runs require the separate `--run --allow-mutations` flags shown below. Some checks include expensive reads and can take time on the full dataset. Save results outside the repository; output may contain connection metadata and database errors.

## Start and stop SQLQueryStress

See the [workload instructions](../workload/README.md). Initially run a small finite iteration count. Inspect errors and outcomes before increasing threads. There is no permanent dispatcher or server-side loop. Use one instance with the combined batch and its single parameter mapping; its threads choose operations automatically.

For an optional bounded mixed run on your lab database, the evidence client executes the same packaged batches:

```sh
.venv/bin/python tests/integration/workload.py --run --allow-mutations --calls 100 --threads 4
```

This command commits mutations to selected existing content. It is **not part of deployment or smoke**; review the selected workload before running it. It emits each batch's duration, outcomes, row counts, exceptions and a summary. Connection setup is measured separately; these client timings are not SQL Server CPU/reads or SQLQueryStress performance numbers.

To stop, click Cancel in the SQLQueryStress window and wait for execution/rollback to finish. Let bounded evidence runs drain their current calls. Verify there are no remaining Stackish sessions with active requests or open transactions before resetting. SQLQueryStress exceptions are errors only: `NotFound`, `Conflict` and `NoChange` are successful SQL executions, so an exception count of zero does not prove useful work. Capture outcome distributions with the evidence client alongside SQLQueryStress CPU, elapsed time and reads.

## Reset by restoring a backup

Deployment does not reset content. Stop all callers, allow transactions to finish, and have the operator restore the chosen clean backup into the intended disposable database using normal SQL Server restore procedures. Verify server, database name, backup dataset date and file paths first. Restoring over an existing database, dropping one, or replacing it requires explicit authorization; no reset script performs these actions automatically.

After an authorized restore, verify compatibility without changing it, rerun `sql/deploy.sql`, then smoke/edge checks and parameter validation. The entry point recreates missing supporting indexes and reuses suitable existing ones; it does not copy every research index. Record which indexes were created/reused. Tag/body searches and global aggregations can remain costly; deployment does not attempt to eliminate every scan. Clear any desktop baseline after a restore.
