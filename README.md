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
- Space for the restored database, ongoing writes, and index creation. Deployment creates missing supporting indexes; on our 2024-04 test copy, the 13 added indexes occupied about **24.6 GiB**, in addition to the database. Index builds also need working space and transaction-log capacity.
- A database login with permission to deploy objects and create indexes. For a simple isolated lab, a SQL login mapped to a database user in `db_owner` can deploy and run Stackish. The app uses SQL authentication; it has no Windows-integrated or Entra sign-in option.
- The **sqlcmd** command-line tool for database deployment. To run the app from source, install the **.NET 10 SDK** on Windows or Mac. Packaged builds include their own .NET runtime.

The workload commits real changes. Use a lab copy you are comfortable restoring. Keep a clean backup for repeated experiments.

## Deploy the database objects

Clone your fork and open a terminal in the repository root—the folder containing this README. Restore the database using your normal SQL Server backup/restore process first. Stackish does not create the database or import the public data.

Check the server and selected database before deployment:

```sql
SELECT DB_NAME() AS DatabaseName,
       SERVERPROPERTY('ProductVersion') AS EngineVersion,
       compatibility_level
FROM sys.databases
WHERE database_id = DB_ID();
```

Set up compatibility level 170 or later yourself if needed. Stackish checks the setting but never changes it.

Run the following from the repository root, replacing the server, login, and database placeholders. With SQL authentication, let sqlcmd prompt for the password, or supply `SQLCMDPASSWORD` through your local environment; do not put a password in the command or in a repository file.

```sh
sqlcmd -S YOUR_SERVER -U YOUR_LOGIN -d YOUR_DATABASE -b -i sql/deploy.sql
```

Use the TLS/certificate options appropriate for your server. In particular, a locally trusted/self-signed certificate may require an explicit trust setting in your client. Select the database with `-d`; do not depend on the login's default database.

The entry point checks the engine, compatibility, required base tables/columns, and lookup values. It then creates missing supporting indexes, installs the tag parser before dependent objects, and creates or updates **42 stored procedures and one function**. A final inventory check reports missing or unexpected Stackish objects. Initial index creation on the large dataset can take time and block callers, so deploy before starting the workload.

You can rerun the same deployment command. It reuses suitable existing indexes and does not repair imported data, change base tables or constraints, change database settings, or reset activity from previous runs. A failed deployment may have installed some objects already; fix the reported problem and rerun it. Deployment can overwrite your edits to Stackish procedures, so commit tuning or migration changes to your fork first.

## Open the app

Download [Stackish Preview 1](https://github.com/BrentOzarULTD/stackish/releases/tag/v0.1.0-preview.1):

- [Windows x64](https://github.com/BrentOzarULTD/stackish/releases/download/v0.1.0-preview.1/Stackish-win-x64.zip)
- [Mac with Apple Silicon](https://github.com/BrentOzarULTD/stackish/releases/download/v0.1.0-preview.1/Stackish-osx-arm64.zip)
- [Mac with an Intel processor](https://github.com/BrentOzarULTD/stackish/releases/download/v0.1.0-preview.1/Stackish-osx-x64.zip)

The release includes SHA-256 checksums. These are unsigned previews; your operating system may warn or block them under its security policy. No SDK is needed to use a download.

Or build from source with these commands, run from the repository root on either Windows or Mac:

```sh
dotnet restore desktop/Stackish.slnx --locked-mode
dotnet run --project desktop/Stackish.Desktop -c Release
```

For an unsigned packaged build supplied by a maintainer or generated by the repository's Desktop builds workflow, extract the ZIP. Open `Stackish.app` on Mac, or `Stackish.exe` on Windows. Keep all Windows companion files together. Current packages are review builds, not signed/notarized public installers; native Windows and Intel Mac GUI validation remains outstanding. Linux packaging is not included.

1. Enter the SQL Server, database name, username, and password. Choose **Trust server certificate** only if that matches your lab's certificate policy.
2. Click **Test connection**. This checks the database requirements and installed objects; it does not deploy or repair them.
3. Choose the number of **Concurrent operations**. Start small—four is a reasonable first check—and click **Start workload**.
4. Check completed calls, successful writes, and **Errors & outcomes**. A successful connection check alone does not prove the workload is running successfully.
5. Leave the app open and the computer awake while you want activity. It runs until you stop it; no SQL batches, parameter mappings, or additional runner instances are needed.
6. Click **Stop** and wait for **Stopped** before restoring the database or treating the source as quiescent for a cutover. Stop prevents new calls, allows active calls to finish, and requests cancellation after 30 seconds if necessary. Writes can still commit while stopping; cancellation does not prove a write was rolled back. Stop any other writers separately too.

The mix selects roughly **55% read calls and 45% write calls**, including hot targets, content creation, and occasional expensive searches and aggregations. Those are invocation proportions, not shares of CPU or elapsed time. Long-running reads can occupy workers for a while. Some completed calls legitimately report `Conflict`, `NoChange`, or `NotFound`; watch those alongside successful writes and errors, especially during long rehearsals as the data changes.

The password stays in memory. The app saves nonsecret connection settings and a baseline locally, including sampled IDs and error summaries; keep that local state out of your repository as well.

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
