using System.Text.RegularExpressions;

namespace Stackish.Core;

public static class DatabaseDeployment
{
    public sealed record Batch(string Source, string Sql);

    // Share the CLI entry point's explicit order; never discover/run arbitrary SQL.
    public static IEnumerable<Batch> Batches()
    {
        foreach (string line in Read("deploy.sql").Split('\n'))
        {
            string directive = line.Trim();
            if (directive.Length == 0 || directive.StartsWith("--") || directive == ":ON ERROR EXIT") continue;
            if (!directive.StartsWith(":r sql/")) throw new InvalidOperationException("Unsupported deployment directive: " + directive);
            string path = directive[7..];
            if (path == "indexes.sql") throw new InvalidOperationException("Index creation must remain separate from app deployment.");
            foreach (string sql in Regex.Split(Read(path), @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase))
                if (!string.IsNullOrWhiteSpace(sql)) yield return new(path, sql);
        }
    }

    public static async Task ExecuteAsync(Func<Batch, CancellationToken, Task> execute,
        Action? beforeModuleChanges = null, IProgress<string>? progress = null, CancellationToken token = default)
    {
        var batches = Batches().ToArray();
        bool notified = false;
        for (int i = 0; i < batches.Length; i++)
        {
            token.ThrowIfCancellationRequested();
            var batch = batches[i];
            progress?.Report(batch.Source == "preflight.sql" ? "Checking database requirements…" :
                batch.Source == "inventory.sql" ? "Verifying installed objects…" : $"Installing database objects: step {i + 1} of {batches.Length}…");
            if (!notified && Regex.IsMatch(batch.Sql, @"^\s*CREATE OR ALTER (?:PROCEDURE|FUNCTION)\b", RegexOptions.Multiline | RegexOptions.IgnoreCase))
            {
                // Synchronous notification before issuing DDL: preserve prior results
                // on connection/preflight failures, invalidate them for partial updates.
                beforeModuleChanges?.Invoke();
                notified = true;
            }
            await execute(batch, token);
        }
    }

    private static string Read(string path)
    {
        if (path is "preflight.sql" or "inventory.sql") return WorkloadFiles.Read(path);
        var assembly = typeof(DatabaseDeployment).Assembly;
        string name = assembly.GetManifestResourceNames().Single(n => n.Replace('\\', '/') == "Deployment/" + path);
        using var stream = assembly.GetManifestResourceStream(name)!;
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
