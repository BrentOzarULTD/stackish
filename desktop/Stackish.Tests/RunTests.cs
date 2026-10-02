using System.Text.Json;
using Stackish.Core;
using Xunit;

namespace Stackish.Tests;
public sealed class RunTests
{
    private static readonly RunConfiguration Config = new(new("example.invalid", "StackOverflow", "student"), 4, "test-workload");

    [Fact]
    public void ComparisonUsesEqualElapsedIntervalsAndRejectsDifferentSettings()
    {
        var before = Snapshot(100, 20);
        var after = Snapshot(150, 10);
        var comparison = Comparison.Between(before, after)!;
        Assert.Equal(10, comparison.Seconds);
        Assert.Equal(100, comparison.BaselineQps);
        Assert.Equal(150, comparison.CurrentQps);
        Assert.Equal(50, comparison.PercentChange);
        Assert.Null(Comparison.Between(before, after with { Configuration = Config with { Concurrency = 8 } }));
        Assert.Null(Comparison.Between(before, after with { Configuration = Config with { Connection = new("other", "StackOverflow", "student") } }));
        Assert.Null(Comparison.Between(before, after with { Configuration = Config with { WorkloadVersion = "changed" } }));
    }

    [Fact]
    public void ReadinessUsesSeparateSqlBatchesWithoutSqlcmdDelimiters()
    {
        var batches = SqlWorkloadBackend.ReadinessBatches().ToArray();
        Assert.True(batches.Length >= 2);
        Assert.All(batches, batch => Assert.DoesNotMatch(@"(?im)^\s*GO\s*$", batch));
        Assert.All(batches, batch => Assert.True(batch.Split("DECLARE @Expected").Length <= 2));
    }

    [Fact]
    public void AppDeploymentContainsAllModulesInDependencyOrderAndNoIndexDdl()
    {
        var batches = DatabaseDeployment.Batches().ToArray();
        Assert.Equal("preflight.sql", batches.First().Source);
        Assert.Equal("inventory.sql", batches.Last().Source);
        string sql = string.Join("\n", batches.Select(b => b.Sql));
        Assert.Equal(43, System.Text.RegularExpressions.Regex.Matches(sql,
            @"CREATE OR ALTER (?:PROCEDURE|FUNCTION) dbo\.Stackish_", System.Text.RegularExpressions.RegexOptions.IgnoreCase).Count);
        Assert.True(sql.IndexOf("FUNCTION dbo.Stackish_SplitTags", StringComparison.Ordinal) < sql.IndexOf("PROCEDURE dbo.", StringComparison.Ordinal));
        Assert.DoesNotMatch(@"(?im)^\s*(?:GO\s*$|:r|:ON)|\b(?:CREATE|ALTER|DROP)\s+(?:NONCLUSTERED\s+)?INDEX\b", sql);
        Assert.DoesNotContain(typeof(DatabaseDeployment).Assembly.GetManifestResourceNames(), n => n.EndsWith("indexes.sql"));
    }

    [Fact]
    public void ShortAndZeroBaselinesDoNotProduceInventedPercentages()
    {
        Assert.Null(Comparison.Between(Snapshot(100, 3), Snapshot(200, 30)));
        Assert.Null(Comparison.Between(Snapshot(0, 10), Snapshot(200, 10))!.PercentChange);
    }

    [Fact]
    public void MeterExcludesErrorsCancellationAndDrainButKeepsOutcomeCounts()
    {
        var clock = new ManualClock();
        var meter = new RunMeter(Config, clock);
        clock.Advance(1);
        meter.Complete(new(true));
        meter.Complete(new(false, "Applied"));
        meter.Complete(new(false, "Conflict"));
        meter.Error("Vote", "SQL error");
        meter.Cancel();
        clock.Advance(4);
        meter.Stop();
        clock.Advance(20);
        meter.Complete(new(true));
        meter.Finish();
        var result = meter.Snapshot();
        Assert.Equal(3, result.Completed);
        Assert.Equal(1, result.Applied);
        Assert.Equal(1, result.Conflicts);
        Assert.Equal(1, result.Errors);
        Assert.Equal(1, result.Canceled);
        Assert.Equal(5, result.Seconds);
        Assert.Equal(.6, result.Average);
        Assert.Equal(3, result.Buckets.Sum(b => b.Completed));
    }

    [Fact]
    public void CompletionOnBucketBoundaryIsNotLost()
    {
        var clock = new ManualClock();
        var meter = new RunMeter(Config, clock);
        clock.Advance(5); meter.Complete(new(true)); meter.Stop();
        Assert.Equal(meter.Snapshot().Completed, meter.Snapshot().Buckets.Sum(b => b.Completed));
    }

    [Fact]
    public void MeterRetainsEmptyBucketsSoStallsAppearAsZeroThroughput()
    {
        var clock = new ManualClock();
        var meter = new RunMeter(Config, clock);
        clock.Advance(1); meter.Complete(new(true));
        clock.Advance(15); meter.Stop();
        var buckets = meter.Snapshot().Buckets;
        Assert.Equal(4, buckets.Length);
        Assert.Equal(0, buckets[1].Completed);
        Assert.Equal(0, buckets[2].Completed);
        Assert.Equal(1, buckets[3].Seconds);
    }

    [Fact]
    public void SavedBaselineSurvivesReloadAndCannotContainPasswords()
    {
        string directory = Path.Combine(Path.GetTempPath(), "stackish-test-" + Guid.NewGuid());
        try
        {
            var store = new StateStore(directory);
            var run = Snapshot(200, 15);
            store.Save(new(Config.Connection, 4, new(run, ["{\"QuestionId\":42}"])));
            var restored = store.Load()!;
            Assert.Equal(run.Id, restored.Baseline!.Run.Id);
            Assert.Equal("{\"QuestionId\":42}", restored.Baseline.Targets.Single());
            Assert.DoesNotContain("password", File.ReadAllText(Path.Combine(directory, "state.json")), StringComparison.OrdinalIgnoreCase);
        }
        finally { Directory.Delete(directory, true); }
    }

    [Fact]
    public void SameSeedReplaysGroupAndChoiceSequenceAndSqlUsesThoseInputs()
    {
        var first = new Random(1729); var second = new Random(1729);
        for (int i = 0; i < 1000; i++) Assert.Equal(OperationPlan.Choose(first), OperationPlan.Choose(second));
        Assert.Contains("DECLARE @Operation int=@RunOperation;", SqlWorkloadBackend.CallsSql);
        Assert.Contains("DECLARE @g12_Choice int=@RunChoice;", SqlWorkloadBackend.CallsSql);
        Assert.DoesNotContain("% 100;", SqlWorkloadBackend.CallsSql);
    }

    [Fact]
    public async Task StopWaitsForInFlightCallsAndStartsNoMore()
    {
        var backend = new BlockingBackend();
        var runner = new WorkloadRunner(backend, Config with { Concurrency = 1 }, ["target"]);
        var task = runner.RunAsync();
        await backend.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        runner.Stop();
        Assert.False(task.IsCompleted);
        backend.Release.TrySetResult();
        var result = await task.WaitAsync(TimeSpan.FromSeconds(3));
        Assert.Equal(1, backend.Calls);
        Assert.True(result!.Finished);
        Assert.Equal(0, result.Active);
        Assert.True(backend.Disposed);
    }

    [Fact]
    public async Task DrainTimeoutCancelsAnActiveCallAndIsNotThroughput()
    {
        var backend = new BlockingBackend();
        var runner = new WorkloadRunner(backend, Config with { Concurrency = 1 }, ["target"], TimeSpan.FromMilliseconds(20));
        var task = runner.RunAsync();
        await backend.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        runner.Stop();
        var result = await task.WaitAsync(TimeSpan.FromSeconds(3));
        Assert.Equal(1, result!.Canceled);
        Assert.Equal(0, result.Completed);
    }

    [Fact]
    public async Task StoppingDuringPreparationDoesNotStartMeasurementOrOpenWorkers()
    {
        var runner = new WorkloadRunner(new PreparingBackend(), Config);
        var task = runner.RunAsync();
        runner.Stop();
        Assert.Null(await task.WaitAsync(TimeSpan.FromSeconds(3)));
        Assert.Null(runner.Snapshot);
        runner.Stop(); // Harmless after completion/disposal.
    }

    [Fact]
    public async Task EmptyPoolFailsBeforeAnyWorkerCanMutate()
    {
        var backend = new BlockingBackend();
        var runner = new WorkloadRunner(backend, Config, []);
        await Assert.ThrowsAsync<InvalidOperationException>(() => runner.RunAsync());
        Assert.Equal(0, backend.Calls);
    }

    public static RunSnapshot Snapshot(int qps, int seconds) => new(Guid.NewGuid(), Config, DateTimeOffset.Now,
        seconds, true, false, qps * seconds, 0, 0, 0, 0, 0, 0, 0, 0,
        Enumerable.Range(0, (int)Math.Ceiling(seconds / 5.0)).Select(i =>
        {
            int length = Math.Min(5, seconds - i * 5);
            return new ThroughputBucket(i * 5 + length, length, qps * length);
        }).ToArray(), []);

    private sealed class ManualClock : TimeProvider
    {
        private long ticks;
        public override long TimestampFrequency => 1000;
        public override long GetTimestamp() => ticks;
        public void Advance(int seconds) => ticks += seconds * 1000;
    }
    private sealed class PreparingBackend : IWorkloadBackend
    {
        public async Task<string[]> PrepareAsync(CancellationToken token)
        {
            await new TaskCompletionSource().Task.WaitAsync(token);
            return [];
        }
        public Task<IWorkloadWorker> OpenWorkerAsync(CancellationToken token) => throw new Exception("Must not open workers");
    }
    private sealed class BlockingBackend : IWorkloadBackend, IWorkloadWorker
    {
        public readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public int Calls;
        public bool Disposed;
        public Task<string[]> PrepareAsync(CancellationToken cancellationToken) => Task.FromResult(new[] { "target" });
        public Task<IWorkloadWorker> OpenWorkerAsync(CancellationToken cancellationToken) => Task.FromResult<IWorkloadWorker>(this);
        public async Task<OperationResult> ExecuteAsync(Operation operation, string targets, CancellationToken token)
        {
            Interlocked.Increment(ref Calls); Entered.TrySetResult();
            await Release.Task.WaitAsync(token);
            return new(true);
        }
        public ValueTask DisposeAsync() { Disposed = true; return ValueTask.CompletedTask; }
    }
}
