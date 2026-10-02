using Avalonia;
using Avalonia.Headless;
using Avalonia.Threading;
using Stackish.Core;
using Stackish.Desktop;

// Offline rendering only. Never constructs a database backend or starts a workload.
AppBuilder.Configure<App>().UseSkia().UseHeadless(new AvaloniaHeadlessPlatformOptions
{ UseHeadlessDrawing = false }).SetupWithoutStarting();
string output = args.FirstOrDefault() ?? Path.Combine(Path.GetTempPath(), "stackish-desktop-preview");
Directory.CreateDirectory(output);
var configuration = new RunConfiguration(new("sql-class-01.example.lab,1433", "StackOverflow", "stackish_student"), 8, WorkloadFiles.Version);
var start = new DateTimeOffset(2026, 10, 1, 10, 32, 0, TimeSpan.FromHours(-7));
RunSnapshot Sample(int qps, int seconds, bool finished)
{
    var random = new Random(19);
    var buckets = Enumerable.Range(1, seconds / 5).Select(i => new ThroughputBucket(i * 5, 5, (int)(qps * 5 * (.88 + random.NextDouble() * .24)))).ToArray();
    long total = buckets.Sum(b => b.Completed), reads = (long)(total * .55), writes = total - reads;
    return new(Guid.NewGuid(), configuration, start, seconds, finished, false, reads, writes,
        writes - 121, 48, 64, 9, 2, 0, finished ? 0 : 8, buckets,
        [new(start.AddSeconds(seconds - 14), "Vote on post", "SQL Server chose this call as a deadlock victim. (SQL 1205)")]);
}
var baseline = Sample(310, 600, true);
foreach (var scenario in new[] { "setup", "baseline-saved", "comparison-running", "comparison-stopped", "stopping", "errors", "compact", "minimum-setup", "minimum-running" })
{
    var vm = new MainViewModel(new StateStore(Path.Combine(output, "empty-state")));
    if (scenario != "setup" && scenario != "minimum-setup") vm.ShowPreview(baseline, scenario == "baseline-saved" ? null : Sample(421, 420, scenario == "comparison-stopped"), scenario is "comparison-running" or "compact" or "minimum-running" or "errors" or "stopping", scenario == "errors", scenario == "stopping");
    var window = new MainWindow { DataContext = vm, Width = scenario.StartsWith("minimum") ? 960 : scenario == "compact" ? 1000 : 1280, Height = scenario.StartsWith("minimum") ? 640 : scenario == "compact" ? 700 : 800 };
    window.Show(); Dispatcher.UIThread.RunJobs();
    using var frame = window.CaptureRenderedFrame() ?? throw new InvalidOperationException("No rendered frame.");
    frame.Save(Path.Combine(output, scenario + ".png"), Avalonia.Media.Imaging.PngBitmapEncoderOptions.Default);
    // Preview runs are sample view-model states, with no real work to drain.
    vm.ShowPreview(baseline, null, false);
    window.Close();
    Console.WriteLine(scenario + ".png");
}
