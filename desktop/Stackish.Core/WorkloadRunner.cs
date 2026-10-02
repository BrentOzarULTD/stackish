namespace Stackish.Core;

public interface IWorkloadWorker : IAsyncDisposable
{
    Task<OperationResult> ExecuteAsync(Operation operation, string targets, CancellationToken cancellationToken);
}

public interface IWorkloadBackend
{
    Task<string[]> PrepareAsync(CancellationToken cancellationToken);
    Task<IWorkloadWorker> OpenWorkerAsync(CancellationToken cancellationToken);
}

public sealed class WorkloadRunner(IWorkloadBackend backend, RunConfiguration configuration,
    string[]? cachedTargets = null)
{
    private readonly CancellationTokenSource stopStarting = new();
    private readonly object lifecycle = new();
    private RunMeter? meter;
    private bool started, completed;
    public string[] Targets { get; private set; } = [];
    public RunSnapshot? Snapshot => meter?.Snapshot();

    public void Stop()
    {
        lock (lifecycle)
        {
            if (completed || stopStarting.IsCancellationRequested) return;
            meter?.Stop();
            // The same token stops setup, prevents new calls, and cancels active SQL immediately.
            stopStarting.Cancel();
        }
    }

    public async Task<RunSnapshot?> RunAsync()
    {
        lock (lifecycle)
        {
            if (started) throw new InvalidOperationException("This run has already started.");
            started = true;
        }
        ArgumentOutOfRangeException.ThrowIfLessThan(configuration.Concurrency, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(configuration.Concurrency, 200);
        var workers = new List<IWorkloadWorker>();
        try
        {
            Targets = cachedTargets ?? await backend.PrepareAsync(stopStarting.Token);
            if (Targets.Length == 0) throw new InvalidOperationException("No eligible workload targets. Try Start again to choose another sample.");
            // Opening connections is setup, not measured throughput.
            for (int i = 0; i < configuration.Concurrency; i++)
                workers.Add(await backend.OpenWorkerAsync(stopStarting.Token));
            lock (lifecycle)
            {
                if (stopStarting.IsCancellationRequested) return null;
                meter = new RunMeter(configuration);
            }
            await Task.WhenAll(workers.Select((worker, index) => Task.Run(() => RunWorkerAsync(worker, index))));
            meter.Finish();
            return meter.Snapshot();
        }
        catch (OperationCanceledException) when (stopStarting.IsCancellationRequested) { return null; }
        finally
        {
            foreach (var worker in workers) await worker.DisposeAsync();
            lock (lifecycle) { completed = true; }
            // Retain the stop token source so late UI Stop events are harmless.
        }
    }

    private async Task RunWorkerAsync(IWorkloadWorker worker, int index)
    {
        var metrics = meter ?? throw new InvalidOperationException("Run has not started.");
        var random = new Random(unchecked(configuration.Seed + index * 104729));
        int cursor = index;
        long? firstFailure = null;
        while (!stopStarting.IsCancellationRequested)
        {
            var operation = OperationPlan.Choose(random);
            var targets = Targets[cursor % Targets.Length];
            cursor = (cursor + configuration.Concurrency) % Targets.Length;
            bool entered = false;
            try
            {
                Task<OperationResult> execution;
                lock (lifecycle)
                {
                    if (stopStarting.IsCancellationRequested) break;
                    metrics.Enter();
                    entered = true;
                    execution = worker.ExecuteAsync(operation, targets, stopStarting.Token);
                }
                var result = await execution;
                metrics.Complete(result);
                firstFailure = null;
            }
            catch (Exception) when (stopStarting.IsCancellationRequested) { metrics.Cancel(); }
            catch (Exception ex)
            {
                var message = SqlWorkloadBackend.Explain(ex);
                metrics.Error(operation.Name, message);
                firstFailure ??= Environment.TickCount64;
                if (SqlWorkloadBackend.IsFatal(ex) || Environment.TickCount64 - firstFailure.Value >= 10_000)
                {
                    lock (lifecycle)
                    {
                        metrics.Stop("Stopped after repeated errors. Open Errors & outcomes for details.");
                        Stop();
                    }
                }
            }
            finally { if (entered) metrics.Leave(); }
        }
    }
}
