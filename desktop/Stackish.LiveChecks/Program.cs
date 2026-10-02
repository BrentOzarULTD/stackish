using System.Diagnostics;
using System.Text.Json;
using Stackish.Core;

// Maintainer evidence client, not part of the packaged desktop app or offline CI.
if (!args.Contains("--allow-mutations"))
{
    Console.Error.WriteLine("Bounded runs commit real workload writes. Pass --allow-mutations on an authorized training copy. Optional: --seconds 60 --workers 4 --runs 2 --trust-certificate. For a continuous check: --seconds 1800 --runs 1.");
    return 2;
}
int Option(string name, int fallback, int min, int max)
{
    int index = Array.IndexOf(args, name);
    int value = index < 0 ? fallback : int.Parse(args[index + 1]);
    if (value < min || value > max) throw new ArgumentOutOfRangeException(name, $"Use {min}–{max}.");
    return value;
}
string Env(string name) => Environment.GetEnvironmentVariable(name) ?? throw new InvalidOperationException("Set " + name + " outside the repository.");
string temporary = Path.Combine(Path.GetTempPath(), "stackish-live-" + Guid.NewGuid());
WorkloadRunner? active = null;
bool interrupted = false;
Console.CancelKeyPress += (_, e) => { e.Cancel = true; interrupted = true; active?.Stop(); };
try
{
    int seconds = Option("--seconds", 60, 10, 86400), workers = Option("--workers", 4, 1, 16), runs = Option("--runs", 2, 1, 2);
    var settings = new ConnectionSettings(Env("STACKISH_SERVER"), Env("STACKISH_DATABASE"), Env("STACKISH_USER"), args.Contains("--trust-certificate"));
    var backend = new SqlWorkloadBackend(settings, Env("SQLCMDPASSWORD"));
    Console.WriteLine("Readiness: " + await backend.TestAsync());
    var config = new RunConfiguration(settings, workers, WorkloadFiles.Version);
    var measured = new EvidenceBackend(backend);
    var state = new StateStore(temporary);
    SavedBaseline? baseline = null;
    bool failed = false;
    for (int iteration = 1; iteration <= runs && !interrupted; iteration++)
    {
        active = new WorkloadRunner(measured, config, baseline?.Targets);
        var setup = Stopwatch.StartNew();
        var execution = active.RunAsync();
        bool setupReported = false;
        int last = -1;
        while (!execution.IsCompleted)
        {
            await Task.Delay(250); // Client measurement polling, never a workload delay.
            if (active.Snapshot is not { } snapshot) continue;
            if (!setupReported) { setupReported = true; Console.WriteLine("SETUP " + JsonSerializer.Serialize(new { iteration, seconds = setup.Elapsed.TotalSeconds, targets = active.Targets.Length })); }
            int elapsed = (int)snapshot.Seconds;
            if (elapsed / 10 != last)
            {
                last = elapsed / 10;
                Console.WriteLine("PROGRESS " + JsonSerializer.Serialize(new { iteration, snapshot.Seconds, snapshot.Completed, snapshot.Errors, snapshot.Active }));
            }
            if (elapsed >= seconds || interrupted) { active.Stop(); break; }
        }
        var drain = Stopwatch.StartNew();
        var result = await execution;
        if (result == null) { if (interrupted) break; throw new InvalidOperationException("No measurement."); }
        Console.WriteLine("RESULT " + JsonSerializer.Serialize(new { iteration, drainSeconds = drain.Elapsed.TotalSeconds, result }));
        failed |= result.Failed || result.Errors > 0;
        if (baseline == null)
        {
            state.Save(new(settings, workers, new(result, active.Targets)));
            baseline = state.Load()!.Baseline!;
            if (baseline.Run.Id != result.Id || !baseline.Targets.SequenceEqual(active.Targets)) throw new InvalidOperationException("Baseline persistence mismatch.");
        }
        else Console.WriteLine("COMPARISON " + JsonSerializer.Serialize(Comparison.Between(baseline.Run, result)));
        active = null;
    }
    return failed ? 1 : interrupted ? 130 : 0;
}
catch (Exception e) { Console.Error.WriteLine(SqlWorkloadBackend.Explain(e)); return 1; }
finally { if (Directory.Exists(temporary)) Directory.Delete(temporary, true); }

sealed class EvidenceBackend(IWorkloadBackend inner) : IWorkloadBackend
{
    public Task<string[]> PrepareAsync(CancellationToken token) => inner.PrepareAsync(token);
    public async Task<IWorkloadWorker> OpenWorkerAsync(CancellationToken token) => new EvidenceWorker(await inner.OpenWorkerAsync(token));
}
sealed class EvidenceWorker(IWorkloadWorker inner) : IWorkloadWorker
{
    public async Task<OperationResult> ExecuteAsync(Operation operation, string targets, CancellationToken token)
    {
        var clock = Stopwatch.StartNew();
        try
        {
            var result = await inner.ExecuteAsync(operation, targets, token);
            Console.WriteLine("CALL " + JsonSerializer.Serialize(new { operation.Name, operation.GroupRoll, operation.Choice, milliseconds = clock.Elapsed.TotalMilliseconds, result }));
            return result;
        }
        catch (Exception e)
        {
            Console.WriteLine("CALL " + JsonSerializer.Serialize(new { operation.Name, operation.GroupRoll, operation.Choice, milliseconds = clock.Elapsed.TotalMilliseconds, canceled = token.IsCancellationRequested, error = SqlWorkloadBackend.Explain(e) }));
            throw;
        }
    }
    public ValueTask DisposeAsync() => inner.DisposeAsync();
}
