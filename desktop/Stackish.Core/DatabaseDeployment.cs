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
