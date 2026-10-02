# Stackish desktop — before and after tuning

The first desktop version targets Windows and macOS. It uses the existing stored procedures and the integrated workload from PR #6. The app does not install database objects, change indexes, or restore data; the separate deployment entry point now installs missing [supporting indexes](../indexes.md). Linux packaging is deferred.

For a packaged review build, unzip the archive and open `Stackish.app` on Mac, or extract the whole Windows archive and open `Stackish.exe` inside its folder. Keep the Windows companion files together. The packages include .NET; an SDK is only needed to build from source.

## Run, tune, compare

1. Install Stackish in your chosen training database using the [installation guide](../installation.md).
2. Open the app, enter the server/database and SQL login, then **Test connection**. That check verifies the engine, compatibility, schema, lookups and installed inventory without changing them. Passwords stay in memory and are never saved.
3. Choose concurrent operations and **Start workload**. The app selects eligible targets and opens worker connections before starting the measured interval. No SQL or parameter mappings are needed.
4. Click **Stop**. New calls stop, active calls drain, and the first nonfailed run of at least five seconds with completed calls becomes the baseline. After 30 seconds the app requests cancellation of remaining calls, then waits for the database driver to finish. Cancellation is not proof that a write did not commit.
5. Tune the database in SSMS. Return to Stackish and click **Start new run**. The saved baseline appears as a dashed gray curve and the new run as a solid blue curve, both aligned to elapsed time from their own start.
6. Repeat as needed. The baseline stays fixed until you click **Use this run as baseline** or **Clear baseline**. It survives closing the app. Neither action changes database data.

Concurrency is fixed during a run. A different server/database, login, concurrency, workload version or operation seed disables the percentage comparison. This is a deliberate change from the supplied mockup's live concurrency control. The curves remain visible with an explanatory message.

## What the chart measures

**Queries/sec means fully consumed, completed Stackish operation calls per second**, not individual T-SQL statements. Each invocation can execute several statements and return multiple result sets. SQL errors and canceled calls are excluded. Conflict, NoChange and NotFound are completed operations and count toward throughput, but are also shown separately. Higher QPS accompanied by many more no-op outcomes may not represent useful improvement.

Five-second buckets include zero-throughput intervals, so expensive queries and stalls are visible. Both curves share one elapsed-time axis and one rate axis; they are never stacked. The percentage compares the same completed five-second intervals from the beginning of both runs, ending at the shorter run's duration. It does not compare a short current average with an entire long baseline, extrapolate the current curve, or divide by a zero baseline. The live rate tile covers recent buckets; the stopped tile shows the full measured average.

Measurement freezes when Stop is pressed. Calls that finish while draining can still change the database, but are excluded from measured totals and QPS because concurrency is falling. Errors and cancellations during drain remain visible. Setup/connection time and time spent tuning are excluded.

The app reuses baseline target tuples and a repeatable per-worker operation/variant sequence for compatible runs. This improves comparability without pretending to be a deterministic database benchmark. Concurrent scheduling, cache state, background activity, text GUIDs and state-dependent votes/moderation still differ. Run long enough to include completions from the expensive reads when using the graph to assess tuning; the five-second minimum is a display rule, not a useful benchmark duration. The workload commits changes; it does not undo the first run. Warm/cold cache and changing data must be considered when teaching from the comparison. Clear the baseline after restoring/replacing the database or deliberately changing the target sample. No automated restore, cache flush, or compensating writes are performed.

## Build and run

Requires the .NET 10 SDK for development. Packaged builds include the runtime.

```sh
dotnet restore desktop/Stackish.slnx --locked-mode
dotnet test desktop/Stackish.Tests
dotnet run --project desktop/Stackish.Desktop
```

Generate self-contained review builds:

```sh
python3 desktop/package.py --runtime osx-arm64
python3 desktop/package.py --runtime osx-x64
python3 desktop/package.py --runtime win-x64
```

macOS output: `desktop/artifacts/<runtime>/Stackish.app`. Windows output: `desktop/artifacts/win-x64/publish/Stackish.exe`; keep its accompanying files together. Each runtime directory also contains a ready-to-share ZIP. The Mac ZIP preserves the app executable permissions. These are unsigned development builds, not signed/notarized public installers. Native Windows execution and Intel Mac execution must be validated on those platforms before claiming release readiness. The CI workflow builds and tests the Windows/Mac targets without a database or credentials; it never starts a live workload.

Nonsecret connection settings and one baseline (including sampled IDs, measurements, and error summaries) are stored under the current user's local application-data directory in `Stackish/state.json`. It contains no password. A failed save is reported in the app. Do not commit local state or real connection details.

## Design and implementation

The [original Claude handoff](design-reference/claude-handoff.md) and its Windows/Mac reference screenshots are design source material. The implemented change is a before/after throughput chart and baseline controls. Additional first-version choices: fixed concurrency per run, password persistence omitted, native window chrome, no automatic database installation, and cancellation remains in Stopping until active work actually finishes. The app does not claim cancellation/rollback finishes at an exact deadline.

The interface uses Avalonia with bundled IBM Plex fonts and their OFL license. It retains the paper background, restrained red branding, compact control rail, six metrics, and an errors/outcomes drawer. Keyboard shortcuts: Windows F5 / Shift+F5; macOS Command+R / Command+period; Escape closes the drawer. Closing during a run asks to stop and quit.

The separate `Stackish.Preview` project renders illustrative screenshots from actual Avalonia controls; it has no database connection and never runs a workload:

```sh
dotnet run --project desktop/Stackish.Preview -- /tmp/stackish-preview
```

The core tests cover SQL readiness batch boundaries, stop during preparation, bucket-boundary accounting, equal-duration comparisons, incompatible settings, zero baselines, error/no-op accounting, persistence, replayed operation choices, stop/drain behavior and cancellation. These are correctness tests with an in-memory backend, not evidence of SQL Server throughput. See [validation](validation.md) for what actually ran.

## Screenshots for review

These are offline renders of the implemented controls with clearly marked illustrative data, not measured server performance.

![Before/after comparison while running](screenshots/comparison-running.png)

![Stopped comparison with baseline controls](screenshots/comparison-stopped.png)

## Bounded maintainer validation

The separate live-check client uses the actual desktop engine for two finite runs, persists/reloads the first baseline, reuses targets and prints calls, outcomes, durations, stop/drain results and the matched comparison. It is not needed to operate the GUI and is never run in CI. With the four connection environment variables from the installation guide set locally:

```sh
dotnet run --project desktop/Stackish.LiveChecks -c Release -- --allow-mutations --seconds 60 --workers 4
```

Use `--trust-certificate` only when that is the intended certificate policy for your training server. The test commits real mutations. It requests Stop after the measured duration, drains/cancels exactly like the app, and finishes before starting the second run. Ctrl+C requests Stop; wait for it to finish. Its temporary baseline file is removed after validation. Output can contain nonsecret server/database/login settings and database error messages; keep raw evidence outside the repository. There is no tuning between these two runs, so a difference is a repeat-run observation, not proof of a tuning improvement.
