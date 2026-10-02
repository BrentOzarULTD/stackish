namespace Stackish.Core;

public sealed class RunMeter(RunConfiguration configuration, TimeProvider? timeProvider = null)
{
    private readonly object gate = new();
    private readonly TimeProvider clock = timeProvider ?? TimeProvider.System;
    private readonly Guid id = Guid.NewGuid();
    private readonly long started = (timeProvider ?? TimeProvider.System).GetTimestamp();
    private readonly DateTimeOffset at = (timeProvider ?? TimeProvider.System).GetUtcNow();
    private readonly List<long> completedByBucket = [];
    private readonly Queue<RunError> recent = new();
    private long reads, writes, applied, conflicts, noChange, notFound, errors, canceled;
    private int active;
    private double? stoppedAt;
    private string? failure;
    private bool finished;

    private double Elapsed => clock.GetElapsedTime(started).TotalSeconds;
    public void Enter() { lock (gate) active++; }
    public void Leave() { lock (gate) active--; }
    public void Complete(OperationResult result)
    {
        lock (gate)
        {
            // Finishing calls after Stop are drained, but aren't included in measured QPS
            // or the measured totals. This avoids a changing concurrency during measurement.
            if (stoppedAt != null) return;
            if (result.IsRead) reads++; else writes++;
            switch (result.Outcome)
            {
                case "Applied": applied++; break;
                case "Conflict": conflicts++; break;
                case "NoChange": noChange++; break;
                case "NotFound": notFound++; break;
            }
            int index = Math.Max(0, (int)Math.Ceiling(Elapsed / 5) - 1);
            while (completedByBucket.Count <= index) completedByBucket.Add(0);
            completedByBucket[index]++;
        }
    }
    public void Error(string operation, string message)
    {
        lock (gate)
        {
            errors++;
            recent.Enqueue(new(clock.GetUtcNow(), operation, message));
            while (recent.Count > 200) recent.Dequeue();
        }
    }
    public void Cancel() { lock (gate) canceled++; }
    public void Stop(string? reason = null)
    {
        lock (gate) { stoppedAt ??= Elapsed; failure ??= reason; }
    }
    public void Finish() { lock (gate) { stoppedAt ??= Elapsed; finished = true; } }
    public RunSnapshot Snapshot()
    {
        lock (gate)
        {
            double seconds = stoppedAt ?? Elapsed;
            var buckets = new List<ThroughputBucket>();
            for (int index = 0; index * 5 < seconds; index++)
            {
                double length = Math.Min(5, seconds - index * 5);
                buckets.Add(new(index * 5 + length, length,
                    index < completedByBucket.Count ? completedByBucket[index] : 0));
            }
            return new(id, configuration, at, seconds, finished, failure != null,
                reads, writes, applied, conflicts, noChange, notFound, errors, canceled,
                active, buckets.ToArray(), recent.ToArray(), failure);
        }
    }
}
