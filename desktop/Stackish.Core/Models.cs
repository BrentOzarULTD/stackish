using System.Security.Cryptography;
using System.Text;

namespace Stackish.Core;

public sealed record ConnectionSettings(string Server, string Database, string Username, bool TrustCertificate = false)
{
    public string Identity => $"{Server.Trim().ToUpperInvariant()}\n{Database.Trim().ToUpperInvariant()}";
}

public sealed record RunConfiguration(ConnectionSettings Connection, int Concurrency, string WorkloadVersion, int Seed = 1729)
{
    public string? Difference(RunConfiguration other)
    {
        if (Connection.Identity != other.Connection.Identity) return "Different server or database";
        if (Connection.Username != other.Connection.Username) return "Different login";
        if (Concurrency != other.Concurrency) return "Different concurrency";
        if (WorkloadVersion != other.WorkloadVersion) return "Different workload version";
        if (Seed != other.Seed) return "Different operation sequence";
        return null;
    }
}

public sealed record ThroughputBucket(double EndSeconds, double Seconds, long Completed)
{
    public double QueriesPerSecond => Seconds > 0 ? Completed / Seconds : 0;
}

public sealed record RunError(DateTimeOffset At, string Operation, string Message);
public sealed record RunSnapshot(
    Guid Id, RunConfiguration Configuration, DateTimeOffset StartedAt, double Seconds,
    bool Finished, bool Failed, long Reads, long Writes, long Applied, long Conflicts,
    long NoChange, long NotFound, long Errors, long Canceled, int Active,
    ThroughputBucket[] Buckets, RunError[] RecentErrors, string? Failure = null)
{
    // Only fully consumed, non-error operations count as throughput. An operation may
    // execute several SQL statements. Expected business outcomes remain visible separately.
    public long Completed => Reads + Writes;
    public long Expected => Conflicts + NoChange + NotFound;
    public double Average => Seconds > 0 ? Completed / Seconds : 0;
}

public sealed record SavedBaseline(RunSnapshot Run, string[] Targets);
public sealed record AppState(ConnectionSettings Connection, int Concurrency, SavedBaseline? Baseline);
public sealed record OperationResult(bool IsRead, string? Outcome = null);
public sealed record Operation(int GroupRoll, int Choice, string Name, bool IsRead);

public static class OperationPlan
{
    public static Operation Choose(Random random)
    {
        int roll = random.Next(100);
        return new(roll, random.Next(100), Name(roll), roll < 52 || roll >= 97);
    }

    public static string Name(int roll) => roll switch
    {
        < 18 => "Read question page", < 34 => "Browse questions", < 44 => "Browse users",
        < 52 => "Browse tags and badges", < 62 => "Update activity counters", < 74 => "Vote on post",
        < 84 => "Create content", < 91 => "Edit content", < 94 => "Acceptance, closing and links",
        < 95 => "Register user", < 97 => "Update hot counters", _ => "Search and aggregate"
    };
}

public sealed record Comparison(double Seconds, double BaselineQps, double CurrentQps)
{
    public double? PercentChange => BaselineQps > 0 ? (CurrentQps / BaselineQps - 1) * 100 : null;

    public static Comparison? Between(RunSnapshot baseline, RunSnapshot current)
    {
        if (baseline.Configuration.Difference(current.Configuration) != null) return null;
        // Compare complete five-second intervals shared by both runs, never full averages
        // from different durations. Ignore the stop/drain tail and unfinished buckets.
        double seconds = Math.Floor(Math.Min(baseline.Seconds, current.Seconds) / 5) * 5;
        if (seconds < 5) return null;
        long before = baseline.Buckets.Where(b => b.EndSeconds <= seconds).Sum(b => b.Completed);
        long after = current.Buckets.Where(b => b.EndSeconds <= seconds).Sum(b => b.Completed);
        return new(seconds, before / seconds, after / seconds);
    }
}

public static class WorkloadFiles
{
    public static string Read(string name)
    {
        using var stream = typeof(WorkloadFiles).Assembly.GetManifestResourceStream("Workload." + name)
            ?? throw new InvalidOperationException("Missing bundled workload: " + name);
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
    public static string Version { get; } = "desktop-v1-" + Convert.ToHexString(SHA256.HashData(
        Encoding.UTF8.GetBytes(Read("calls.sql") + Read("parameters.sql"))))[..16];
}
