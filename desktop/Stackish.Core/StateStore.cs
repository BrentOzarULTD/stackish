using System.Text.Json;

namespace Stackish.Core;

public sealed class StateStore(string? directory = null)
{
    public string DirectoryPath { get; } = directory ?? Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Stackish");
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };
    public AppState? Load()
    {
        string path = Path.Combine(DirectoryPath, "state.json");
        if (!File.Exists(path)) return null;
        var state = JsonSerializer.Deserialize<AppState>(File.ReadAllText(path));
        if (state?.Connection == null || state.Concurrency is < 1 or > 200)
            throw new InvalidDataException("Invalid saved settings.");
        if (state.Baseline is { } baseline &&
            (baseline.Run?.Configuration?.Connection == null || baseline.Targets?.Length is not > 0 ||
             baseline.Run.Buckets == null || baseline.Run.RecentErrors == null))
            throw new InvalidDataException("Invalid saved baseline.");
        return state;
    }
    public void Save(AppState state)
    {
        Directory.CreateDirectory(DirectoryPath);
        string path = Path.Combine(DirectoryPath, "state.json");
        string temporary = path + ".tmp";
        // No password or connection string exists in these persistence models.
        File.WriteAllText(temporary, JsonSerializer.Serialize(state, Options));
        File.Move(temporary, path, true);
    }
}
