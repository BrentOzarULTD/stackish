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
// Exercise clipboard failures offline: neither synchronous nor asynchronous backend
// failures may escape to the async-void UI handler or change the measured run.
var clipboardVm = new MainViewModel(new StateStore(Path.Combine(output, "empty-state")));
clipboardVm.ShowPreview(baseline, Sample(421, 420, true), false, true);
if (!clipboardVm.HasPreviousRun) throw new InvalidOperationException("Comparison is missing the previous-run legend.");
var firstVm = new MainViewModel(new StateStore(Path.Combine(output, "empty-state")));
if (firstVm.HasPreviousRun) throw new InvalidOperationException("First launch must not show a previous run.");
firstVm.ShowPreview(baseline, baseline, false);
if (firstVm.HasPreviousRun) throw new InvalidOperationException("The first stopped run is still the current run.");
var preservedRun = clipboardVm.CurrentRun;
foreach (Func<string, Task> failure in new Func<string, Task>[]
{
    _ => throw new InvalidOperationException("Clipboard unavailable"),
    _ => Task.FromException(new IOException("Clipboard backend failed"))
})
{
    clipboardVm.CopyErrorsAsync(failure).GetAwaiter().GetResult();
    if (!clipboardVm.HasMessage || !clipboardVm.Message.Contains("Could not copy") || clipboardVm.CurrentRun != preservedRun)
        throw new InvalidOperationException("Clipboard failure was not reported safely.");
}
string? copied = null;
clipboardVm.CopyErrorsAsync(text => { copied = text; return Task.CompletedTask; }).GetAwaiter().GetResult();
if (copied != clipboardVm.ErrorText) throw new InvalidOperationException("Clipboard retry lost the error details.");
Console.WriteLine("Clipboard failure and retry checks passed.");
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

// Credential UI tests use a fake vault: no Keychain access, prompts, or real secrets.
var vault = new TestPasswordStore();
var passwordVm = new MainViewModel(new StateStore(Path.Combine(output, "empty-state")), vault)
{ Server = "fixture", Database = "database", Username = "user", Password = "test-secret" };
void Finish(Task task)
{
    var deadline = DateTime.UtcNow.AddSeconds(5);
    while (!task.IsCompleted && DateTime.UtcNow < deadline) Dispatcher.UIThread.RunJobs();
    if (!task.IsCompleted) throw new TimeoutException("Credential UI operation did not finish");
    task.GetAwaiter().GetResult();
}
Finish(passwordVm.RememberSuccessfulPasswordAsync());
if (vault.Secret != null) throw new Exception("Passwords must not be saved without opt-in");
passwordVm.RememberPassword = true;
Finish(passwordVm.RememberSuccessfulPasswordAsync());
if (vault.Secret != "test-secret") throw new Exception("Opted-in password was not saved");
passwordVm.Password = "";
Finish(passwordVm.LoadPasswordAsync());
if (passwordVm.Password != "test-secret" || !passwordVm.RememberPassword) throw new Exception("Saved password did not reload");
passwordVm.Username = "other";
if (passwordVm.Password != "" || passwordVm.RememberPassword) throw new Exception("Changed connection reused another login's password");
Finish(passwordVm.LoadPasswordAsync());
if (passwordVm.Password != "") throw new Exception("Wrong identity loaded a password");
passwordVm.Username = "user";
Finish(passwordVm.LoadPasswordAsync());
vault.Fail = true;
Finish(passwordVm.ForgetPasswordAsync());
if (!passwordVm.RememberPassword || !passwordVm.Message.Contains("may still be saved")) throw new Exception("Deletion failure was hidden");
vault.Fail = false;
Finish(passwordVm.ForgetPasswordAsync());
if (vault.Secret != null || passwordVm.RememberPassword || passwordVm.Password != "test-secret") throw new Exception("Forget did not remove only the stored password");
vault.Fail = true;
Finish(passwordVm.LoadPasswordAsync());
if (!passwordVm.Message.Contains("Could not read")) throw new Exception("Vault read error was hidden");
passwordVm.RememberPassword = true;
Finish(passwordVm.RememberSuccessfulPasswordAsync());
if (!passwordVm.Message.Contains("could not save")) throw new Exception("Vault write error was hidden");
Console.WriteLine("Credential opt-in, reload, identity isolation, deletion and error checks passed.");

sealed class TestPasswordStore : IPasswordStore
{
    public string Name => "test vault";
    public string? Secret;
    private string? key;
    public bool Fail;
    private void Check() { if (Fail) throw new IOException("Synthetic vault failure"); }
    public string? Read(ConnectionSettings connection) { Check(); return key == PasswordStore.Key(connection) ? Secret : null; }
    public void Write(ConnectionSettings connection, string password) { Check(); key = PasswordStore.Key(connection); Secret = password; }
    public void Delete(ConnectionSettings connection) { Check(); if (key == PasswordStore.Key(connection)) Secret = null; }
}
