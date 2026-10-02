# Stackish

Practice a database migration with real-world data and a small application you can understand, change, and break in your own lab.

Stackish simulates Stack Overflow activity against the public Stack Overflow database: asking and answering questions, commenting, voting, editing, browsing, and searching. It includes T-SQL stored procedures and a Windows/Mac desktop app that keeps a mixed workload running while you experiment.

Use it to rehearse moving a SQL Server application to another database, explore where AI helps with that work, or practice SQL Server performance tuning. It is a learning workload, not a production website or a benchmark that predicts how your company's application will perform.

## Start with a migration rehearsal

Fork this repository into your own account. Restore the sample database, deploy Stackish, and get the app running against SQL Server first. That gives you a working source system to compare with your migration.

Then work through the same phases as a larger project:

1. Discover the source schema and decide how to represent it on your target platform.
2. Copy the data. Leave Stackish running against the source when you want to practice keeping up with ongoing changes.
3. Port the stored procedures and functions, and test that their behavior still matches.
4. Change the app's connection and workload code to use your target database.
5. Rehearse the process again, including catching up with writes and stopping the source workload for cutover.

Stackish generates the source activity; it does not copy data, configure change capture, synchronize databases, or perform a cutover. The shipped app connects to **SQL Server only**. PostgreSQL, Babelfish, and other destinations are migration projects for you to undertake, not supported backends you can select in a menu. Database checks and workload batches are SQL Server-specific too; changing a connection string alone is not a port.

If you use an AI tool, start by asking it to inspect the repository and your restored database, identify the decisions that need your input, and propose a migration plan **before changing anything**. Keep credentials and local connection files out of your fork. You choose the tools and destination.

## What you need

- **SQL Server 2025 or later**, with the selected database at **compatibility level 170 or later**. The Windows/Mac app can connect to a separate SQL Server machine.
- A disposable restore of the **2024-04 Stack Overflow database**, available through [Brent's database download page](https://www.brentozar.com/archive/2015/10/how-to-download-the-stack-overflow-database-via-bittorrent/). The data and backup are not included in this repository. Other exports may differ; the 2024-04 copy is the release validation target.
- Space for the restored database, ongoing writes, and index creation. Optional supporting indexes occupied about **24.6 GiB** on our 2024-04 test copy. If you choose to create them, allow additional working space and transaction-log capacity.
- A database login with permission to deploy procedures and functions. Creating optional indexes requires additional permissions. For a simple isolated lab, a SQL login mapped to a database user in `db_owner` can deploy and run Stackish. The app uses SQL authentication; it has no Windows-integrated or Entra sign-in option.
- Packaged builds include their own .NET runtime and procedure/function installer. **sqlcmd** is only needed for command-line deployment or the optional index script. Building from source requires the **.NET 10 SDK**.

The workload commits real changes. Use a lab copy you are comfortable restoring. Keep a clean backup for repeated experiments.

## Prepare the database

**Download version matters:** the currently published **Windows Preview 1 does not have the installer button**. For that download, obtain this repository and run the command-line procedure/function installation below before using Test connection. The in-app installer described here is in the current source, pending updated downloads. Index preparation is optional with either version.

Restore your disposable database first. Stackish does not restore backups, import data, or change database settings. Use SQL Server 2025 or later and compatibility level 170 or later.

With the current source build, open the app, enter the server, database and SQL login, then click **Install / update Stackish**. The app checks the required schema and lookup values, installs **42 stored procedures and one function** in dependency order, and verifies the inventory. It shows progress and reports failures. No repository checkout or sqlcmd installation is needed for this step.

**Install / update replaces existing Stackish procedure/function definitions**, including your tuning changes, and clears the app's saved baseline immediately before the first module-changing batch. Failed connections or preflight checks preserve it. Use it for a fresh restore or a deliberate update. For an already prepared database, use **Test connection** and start the workload; that check changes nothing. If installation fails or is interrupted, resolve the reported problem and retry. Completed batches remain installed, and rerunning is safe. Stop other callers before updating procedures.

### Optional index preparation

**The app never creates or changes indexes.** You can run without the suggested indexes, choose a subset, or use your own tuning. Large reads and writes can be much slower without suitable indexes.

The separate [index creation script](sql/indexes.sql) is **idempotent**: it reuses suitable existing indexes under any name and creates only missing ones. It does not drop, rebuild, or modify existing indexes. If one of its proposed names already exists with an incompatible definition, it reports a conflict instead of overwriting your work. Review the script and choose the indexes appropriate for your experiment; running the whole script creates all missing suggestions. New indexes are named only for their key columns (for example, `PostId_CreationDate_Id`). The Messages tab reports progress immediately, such as `Index 4 of 13`, including whether each index is being created or reused.

With sqlcmd, select your database explicitly and supply the password at its prompt or through a local `SQLCMDPASSWORD` environment variable:

```sh
sqlcmd -S YOUR_SERVER -U YOUR_LOGIN -d YOUR_DATABASE -b -i sql/indexes.sql
```

You can also open `sql/indexes.sql` in SSMS, select the intended database, and execute it there. Initial creation can take substantial time and disk/log space; finish index preparation before measuring workload performance. Use appropriate TLS/certificate options for your server.

For command-line procedure/function installation, run from the repository root:

```sh
sqlcmd -S YOUR_SERVER -U YOUR_LOGIN -d YOUR_DATABASE -b -i sql/deploy.sql
```

This entry point installs the same modules as the app and **does not run the index script**. Neither installer repairs imported data, changes base tables/constraints or database settings, or resets workload activity.

## Open the app

Download [Stackish Preview 1](https://github.com/BrentOzarULTD/stackish/releases/tag/v0.1.0-preview.1):

- [Windows x64 — Preview 1; requires CLI module installation](https://github.com/BrentOzarULTD/stackish/releases/download/v0.1.0-preview.1/Stackish-win-x64.zip)
- **Mac downloads are withdrawn.** The original bundles had invalid signatures and could show “Stackish is damaged.” A corrected, Developer ID-signed and notarized distribution must pass downloaded-package checks before Mac downloads return. You can build locally from source below.

The release includes a SHA-256 checksum for the Windows archive. This is an unsigned preview; your operating system may warn or block it under its security policy. No SDK is needed to use a download.

Or build from source with these commands, run from the repository root on either Windows or Mac:

```sh
dotnet restore desktop/Stackish.slnx --locked-mode
dotnet run --project desktop/Stackish.Desktop -c Release
```

For the Windows preview, extract the entire ZIP and open `Stackish.exe`; keep its companion files together. Mac packages generated by the build workflow are developer artifacts, not verified public installers. Native Windows and Intel Mac GUI validation remains outstanding. Linux packaging is not included.

1. Enter the SQL Server, database name, username, and password. Choose **Trust server certificate** only if that matches your lab's certificate policy.
2. Prepare a fresh restore using the CLI command for Preview 1, or **Install / update Stackish** in the current source build. For an already prepared database, click **Test connection**; it checks requirements and installed objects without changing them.
3. Choose the number of **Concurrent operations**. Start small—four is a reasonable first check—and click **Start workload**.
4. Check completed calls, successful writes, and **Errors & outcomes**. A successful connection check alone does not prove the workload is running successfully.
5. Leave the app open and the computer awake while you want activity. It runs until you stop it; no SQL batches, parameter mappings, or additional runner instances are needed.
6. Click **Stop** and wait for **Stopped** before restoring the database or treating the source as quiescent for a cutover. Stop prevents new calls and immediately sends cancellation for active queries. The app waits only for cancellation and connection cleanup, not for queries to finish normally. Writes can still commit while stopping; cancellation does not prove a write was rolled back. Stop any other writers separately too.

The mix selects roughly **55% read calls and 45% write calls**, including hot targets, content creation, and occasional expensive searches and aggregations. Those are invocation proportions, not shares of CPU or elapsed time. Long-running reads can occupy workers for a while. Some completed calls legitimately report `Conflict`, `NoChange`, or `NotFound`; watch those alongside successful writes and errors, especially during long rehearsals as the data changes.

By default, the password stays in memory. Check **Remember password** to store it in macOS Keychain or Windows Credential Manager after a successful connection. It reloads on the next launch for that connection; use **Load saved password** after changing connection details. Uncheck Remember password to remove that connection’s saved password. The app saves nonsecret connection settings and a baseline locally, including sampled IDs and error summaries; keep that local state out of your repository as well.

## Compare before and after tuning

Run the workload, click **Stop**, tune in SSMS, and start another run. The first successful stopped run with completed calls and at least five measured seconds becomes the saved baseline. The graph overlays that baseline with the new run, aligned by elapsed time. Use **Use this run as baseline** to replace it or **Clear baseline** to start over.

**Queries/sec counts completed Stackish operation calls**, not individual SQL statements. Calls reporting `Conflict`, `NoChange`, or `NotFound` count; errors and cancellations do not. Setup time and calls finishing after Stop are excluded from throughput. A higher rate with fewer useful writes is not necessarily an improvement.

The percentage comparison uses matching completed five-second intervals and requires the same connection settings, concurrency, and workload configuration. It is intended for before/after tuning of the same database, not a built-in SQL Server-versus-PostgreSQL benchmark. Five seconds is only the minimum for saving a baseline; run long enough for expensive operations to complete. Data changes and cache state affect the results, and a run does not undo its writes.

## Reset an experiment

Stop all workload clients and wait for active requests and transactions to finish. Restore your clean backup into the intended lab database using your usual SQL Server restore process. Check the destination carefully before overwriting anything.

Rerun `sql/deploy.sql` after restoring, test the app's connection, and **Clear baseline** before starting again. Deployment alone does not reset the data, and clearing the chart does not reset the database. Stackish has no automatic restore or reset button.

## Validation and source

The 2024-04 testbed passed deployment repeatability, integration smoke checks, targeted contention checks, and two bounded desktop workload runs. Continuous-run results and known limitations are recorded on the [preview release page](https://github.com/BrentOzarULTD/stackish/releases/tag/v0.1.0-preview.1). These checks establish a tested starting point, not correctness of a future port or a guarantee of unattended operation. Expensive reads can occupy workers for minutes, delay new writes, time out, or encounter deadlocks; watch the error and successful-write counts during a migration rehearsal. SQLQueryStress packaging remains available as an optional alternative; SQLQueryStress itself was not run during this validation.

- [Detailed installation and validation commands](docs/installation.md)
- [Desktop operation, packaging, and measurement details](docs/desktop/README.md)
- [SQL source](sql/) and [executable integration checks](tests/integration/)
- [Optional SQLQueryStress instructions](workload/README.md)

This README and the linked operating instructions get the workload running. Discovering and documenting the schema, business rules, dependencies, and migration decisions is part of the exercise. The code intentionally retains different contributors' styles; there is no goal of making every procedure look alike or adding intentional defects.

## License

Stackish's code is available under the [MIT license](LICENSE). Fork it, adapt it, and share what you learn. The Stack Overflow dataset and bundled third-party assets have their own licensing terms; the repository's MIT license does not relicense them.
