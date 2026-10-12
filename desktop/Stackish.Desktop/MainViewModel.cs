using System.ComponentModel;
using System.Runtime.CompilerServices;
using Avalonia.Threading;
using Stackish.Core;

namespace Stackish.Desktop;

public sealed class MainViewModel : INotifyPropertyChanged
{
    private readonly StateStore store;
    private readonly IPasswordStore passwords;
    private bool rememberPassword, credentialBusy;
    private string passwordHint = "Password is not saved";
    private readonly DispatcherTimer timer;
    private WorkloadRunner? runner;
    private Task? runTask;
    private Task? deploymentTask;
    private CancellationTokenSource? deploymentCancellation;
    private bool deploying;
    private string deploymentProgress = "";
    private RunSnapshot? run;
    private SavedBaseline? baseline;
    private string[] targets = [];
    private bool connected, busy, stopping, testing, drawer, preview;
    private string server = "", database = "StackOverflow", username = "", password = "", message = "", version = "";
    private bool trustCertificate;
    private decimal concurrency = 8;
    public event PropertyChangedEventHandler? PropertyChanged;

    public MainViewModel(StateStore? stateStore = null, IPasswordStore? passwordStore = null)
    {
        store = stateStore ?? new StateStore();
        passwords = passwordStore ?? PasswordStore.Create();
        LoadPasswordCommand = new(() => _ = LoadPasswordAsync(), () => CanConfigure && HasCredentialIdentity);
        TestCommand = new(() => _ = TestAsync(), () => CanConfigure);
        DeployCommand = new(() => deploymentTask = DeployAsync(), () => CanConfigure);
        StartCommand = new(() => _ = StartAsync(), () => connected && CanConfigure);
        StopCommand = new(Stop, () => busy && !stopping);
        EditCommand = new(() => { connected = false; Refresh(); }, () => CanConfigure);
        DrawerCommand = new(() => { drawer = !drawer; Refresh(); });
        BaselineCommand = new(UseBaseline, () => CanConfigure && run is { Finished: true, Failed: false, Completed: > 0, Seconds: >= 5 } && run.Id != baseline?.Run.Id);
        ClearBaselineCommand = new(() => { baseline = null; Save(); Refresh(); }, () => CanConfigure && baseline != null);
        try
        {
            if (store.Load() is { } saved)
            {
                server = saved.Connection.Server; database = saved.Connection.Database;
                username = saved.Connection.Username; trustCertificate = saved.Connection.TrustCertificate;
                concurrency = Math.Clamp(saved.Concurrency, 1, 200); baseline = saved.Baseline;
            }
        }
        catch (Exception) { message = "Saved settings could not be read. Enter your connection again; the saved file has not been changed."; }
        timer = new DispatcherTimer(TimeSpan.FromSeconds(1), DispatcherPriority.Background, (_, _) =>
        {
            if (busy && runner?.Snapshot is { } snapshot) { run = snapshot; Refresh(); }
        });
        timer.Start();
        // Offline previews use their own state directory and must never access the real vault.
        if (stateStore == null) _ = LoadPasswordAsync();
    }

    public ActionCommand LoadPasswordCommand { get; }
    public ActionCommand TestCommand { get; }
    public ActionCommand DeployCommand { get; }
    public bool Deploying => deploying;
    public string DeploymentProgress => deploymentProgress;
    public ActionCommand StartCommand { get; }
    public ActionCommand StopCommand { get; }
    public ActionCommand EditCommand { get; }
    public ActionCommand DrawerCommand { get; }
    public ActionCommand BaselineCommand { get; }
    public ActionCommand ClearBaselineCommand { get; }
    public string Server { get => server; set { if (server != value) { server = value; CredentialIdentityChanged(); } } }
    public string Database { get => database; set { if (database != value) { database = value; CredentialIdentityChanged(); } } }
    public string Username { get => username; set { if (username != value) { username = value; CredentialIdentityChanged(); } } }
    public string Password { get => password; set => Set(ref password, value); }
    public bool RememberPassword
    {
        get => rememberPassword;
        set
        {
            if (value == rememberPassword || credentialBusy) return;
            if (!value) { _ = ForgetPasswordAsync(); return; }
            rememberPassword = true;
            passwordHint = $"Will save in {passwords.Name} after a successful connection";
            Refresh();
        }
    }
    public string RememberPasswordLabel => $"Remember password in {passwords.Name}";
    public string PasswordHint => passwordHint;
    private bool HasCredentialIdentity => !string.IsNullOrWhiteSpace(server) && !string.IsNullOrWhiteSpace(database) && !string.IsNullOrWhiteSpace(username);
    private void CredentialIdentityChanged()
    {
        password = ""; rememberPassword = false; connected = false;
        passwordHint = "Password is not saved for this connection";
        Refresh();
    }
    public async Task LoadPasswordAsync()
    {
        if (!CanConfigure || !HasCredentialIdentity) return;
        var identity = Settings;
        credentialBusy = true; message = ""; Refresh();
        try
        {
            string? saved = await Task.Run(() => passwords.Read(identity));
            if (PasswordStore.Key(identity) != PasswordStore.Key(Settings)) return;
            password = saved ?? ""; rememberPassword = saved != null;
            passwordHint = saved == null ? "No saved password for this connection" : $"Saved in {passwords.Name}";
        }
        catch (Exception) { message = $"Could not read {passwords.Name}. Enter the password manually, or try Load saved password again."; }
        finally { credentialBusy = false; Refresh(); }
    }
    public async Task ForgetPasswordAsync()
    {
        if (credentialBusy) return;
        var identity = Settings;
        credentialBusy = true; message = ""; Refresh();
        try
        {
            await Task.Run(() => passwords.Delete(identity));
            rememberPassword = false; passwordHint = "Saved password removed; the entered password lasts for this session";
        }
        catch (Exception) { message = $"Could not remove the saved password from {passwords.Name}. It may still be saved; try again."; }
        finally { credentialBusy = false; Refresh(); }
    }
    // Called only after SQL authentication succeeds. Vault failure must not undo a working connection.
    public async Task RememberSuccessfulPasswordAsync()
    {
        if (!rememberPassword) return;
        var identity = Settings;
        string secret = password;
        try
        {
            await Task.Run(() => passwords.Write(identity, secret));
            passwordHint = $"Saved in {passwords.Name}";
        }
        catch (Exception) { message = $"Connected, but could not save the password in {passwords.Name}. Try connecting again to retry."; }
    }
    public bool TrustCertificate { get => trustCertificate; set => Set(ref trustCertificate, value); }
    public decimal Concurrency { get => concurrency; set { concurrency = Math.Clamp(decimal.Truncate(value), 1, 200); Refresh(); } }
    public bool IsPreview => preview;
    public bool ShowConnection => !connected;
    public bool Connected => connected;
    public bool Busy => busy || deploying;
    public bool Idle => !Busy;
    public bool CanConfigure => !busy && !testing && !deploying && !credentialBusy;
    public bool ShowStop => busy;
    public bool ShowStart => !busy;
    public bool ShowDrawer => drawer;
    public bool HasRun => run != null;
    public bool HasMessage => !string.IsNullOrEmpty(message);
    public string Message => message;
    public string ConnectionLabel => connected ? $"{server}  /  {database}  as {username}" : "Not connected";
    public string ConnectionVersion => "SQL Server " + version;
    public string TestLabel => testing ? "Testing…" : "Test connection";
    public string StartLabel => run == null ? "▶  Start workload" : "▶  Start new run";
    public bool HasPreviousRun => baseline != null && baseline.Run.Id != run?.Id;
    public string StopLabel => stopping ? "Stopping…" : "■  Stop";
    public string ActionHint => busy ? (stopping ? "Canceling active queries…" : "Stop, tune in SSMS, then run again") : connected ? "The first stopped run becomes your baseline" : "Connect to a database first";
    public string Status => deploying ? "Installing Stackish" : testing ? "Connecting" : stopping ? "Stopping" : busy ? run == null ? "Preparing" : "Running" : run?.Failed == true ? "Failed" : run != null ? "Stopped" : connected ? "Ready" : "Not connected";
    public string StatusColor => run?.Failed == true && !busy ? "#B3261E" : stopping ? "#9A5B00" : busy ? "#145C38" : "#1E1F23";
    public string StatusBackground => run?.Failed == true && !busy ? "#FBE9E7" : stopping ? "#FBF0DC" : busy ? "#E7F3EC" : "#F2F0EC";
    public string StatusDetail => deploying ? deploymentProgress : stopping ? $"Cancellation sent for {run?.Active ?? 0} active queries. Waiting for SQL Server to acknowledge." : busy ? run == null ? "Selecting eligible targets and opening connections…" : $"{(int)concurrency} concurrent operations · {(baseline == null ? "recording first run" : "comparing with your baseline")}" : run?.Failure ?? (run != null ? "Measurement stopped. The summary is preserved until your next run." : connected ? $"{(int)concurrency} concurrent operations · runs until you stop it" : "Enter connection details above, then test the connection.");
    public string Elapsed => run == null ? "00:00:00" : Duration(run.Seconds, true);
    public string Completed => run?.Completed.ToString("N0") ?? "—";
    public string ReadWriteDetail => run == null ? "" : $"{run.Reads:N0} reads · {run.Writes:N0} writes";
    public string Rate => run == null ? "—" : FormatRate(busy ? RecentRate(run) : run.Average);
    public string RateDetail => run == null ? "" : busy ? $"recent buckets · average {FormatRate(run.Average)}" : "average over the measured run";
    public string Active => run?.Active.ToString("N0") ?? "—";
    public string ActiveDetail => run == null ? "" : busy ? $"of {(int)concurrency} allowed" : "all calls finished";
    public string Applied => run?.Applied.ToString("N0") ?? "—";
    public string Expected => run?.Expected.ToString("N0") ?? "—";
    public string OutcomeDetail => run == null ? "" : $"Conflict {run.Conflicts:N0} · NoChange {run.NoChange:N0} · NotFound {run.NotFound:N0}";
    public string Errors => run?.Errors.ToString("N0") ?? "—";
    public string ErrorDetail => run?.Canceled > 0 ? $"{run.Canceled:N0} canceled separately" : "SQL or connection failures";
    public string ErrorText => run == null || run.RecentErrors.Length == 0 ? "No SQL or connection errors recorded." : string.Join("\n\n", run.RecentErrors.Reverse().Select(e => $"{e.At.ToLocalTime():HH:mm:ss}  {e.Operation}\n{e.Message}"));
    public string OutcomesText => run == null ? "No run yet." : $"Conflict: {run.Conflicts:N0}\nNoChange: {run.NoChange:N0}\nNotFound: {run.NotFound:N0}\n\nThese calls completed without SQL errors, but did not change data. They count toward queries/sec, so compare them alongside throughput.";
    public RunSnapshot? CurrentRun => run;
    public RunSnapshot? BaselineRun => baseline?.Run;
    public bool HasBaseline => baseline != null;
    public bool NoBaseline => baseline == null;
    public string BaselineLabel => baseline == null ? "Before / after tuning" : $"Baseline · {baseline.Run.StartedAt.ToLocalTime():MMM d, h:mm tt}";
    public string BaselineSummary => baseline == null ? "Run the workload, then Stop. That first run is saved automatically." : $"{FormatRate(baseline.Run.Average)} queries/sec · {baseline.Run.Configuration.Concurrency} concurrent · {Duration(baseline.Run.Seconds)}";
    public string ComparisonText
    {
        get
        {
            if (baseline == null) return "Your first stopped run will appear here as the baseline.";
            if (run == null || run.Id == baseline.Run.Id) return "Baseline saved. Tune in SSMS, then Start new run.";
            if (baseline.Run.Configuration.Difference(run.Configuration) is { } difference) return difference + " — percentage comparison unavailable.";
            var comparison = Comparison.Between(baseline.Run, run);
            if (comparison == null) return "Collecting the first shared 5 seconds…";
            string change = comparison.PercentChange is { } pct ? $"{pct:+0.0;-0.0;0.0}%" : "no percentage (zero baseline)";
            return $"{change} · {FormatRate(comparison.BaselineQps)} → {FormatRate(comparison.CurrentQps)} queries/sec over the first {Duration(comparison.Seconds)}";
        }
    }

    public static string Duration(double seconds, bool alwaysHours = false)
    {
        var time = TimeSpan.FromSeconds(seconds);
        return alwaysHours || seconds >= 3600
            ? $"{(long)time.TotalHours:00}:{time.Minutes:00}:{time.Seconds:00}"
            : $"{time.Minutes:00}:{time.Seconds:00}";
    }
    private static string FormatRate(double rate) => rate.ToString(rate < 10 ? "0.00" : "N0");
    private static double RecentRate(RunSnapshot snapshot)
    {
        var buckets = snapshot.Buckets.TakeLast(2).ToArray();
        var seconds = buckets.Sum(b => b.Seconds);
        return seconds > 0 ? buckets.Sum(b => b.Completed) / seconds : 0;
    }
    private ConnectionSettings Settings => new(server, database, username, trustCertificate);
    private RunConfiguration Configuration => new(Settings, (int)concurrency, WorkloadFiles.Version);

    private async Task TestAsync()
    {
        testing = true; message = ""; Refresh();
        try { version = await new SqlWorkloadBackend(Settings, password).TestAsync(); connected = true; await RememberSuccessfulPasswordAsync(); Save(); }
        catch (Exception ex) { message = SqlWorkloadBackend.Explain(ex); connected = false; }
        finally { testing = false; Refresh(); }
    }
    private async Task DeployAsync()
    {
        deploying = true; connected = false; message = "";
        deploymentProgress = "Checking database…";
        deploymentCancellation = new(); Refresh();
        try
        {
            var progress = new Progress<string>(text => { deploymentProgress = text; Refresh(); });
            var backend = new SqlWorkloadBackend(Settings, password);
            await backend.DeployAsync(progress, deploymentCancellation.Token, beforeModuleChanges: () =>
            {
                baseline = null; run = null; targets = []; Save(); Refresh();
            });
            version = await backend.TestAsync(deploymentCancellation.Token);
            connected = true;
            await RememberSuccessfulPasswordAsync();
            Save();
        }
        catch (OperationCanceledException) { message = "Installation stopped. Some objects may already be installed. Click Install / update Stackish to retry."; }
        catch (Exception ex) { message = "Installation did not finish. " + SqlWorkloadBackend.Explain(ex) + " Some objects may already be installed; resolve the error and retry."; }
        finally { deploying = false; deploymentCancellation.Dispose(); deploymentCancellation = null; Refresh(); }
    }
    public async Task CopyErrorsAsync(Func<string, Task> writeClipboard)
    {
        try { await writeClipboard(ErrorText); }
        catch (Exception)
        {
            message = "Could not copy to the clipboard. Your error details are still available below. Try copying again.";
            Refresh();
        }
    }
    private async Task StartAsync()
    {
        if (busy) return;
        busy = true; stopping = false; run = null; message = ""; Refresh();
        var configuration = Configuration;
        bool compatible = baseline?.Run.Configuration.Difference(configuration) == null && baseline != null;
        runner = new(new SqlWorkloadBackend(Settings, password), configuration, compatible ? baseline!.Targets : null);
        Save();
        runTask = RunToCompletionAsync();
        await runTask;
    }
    private async Task RunToCompletionAsync()
    {
        try
        {
            run = await runner!.RunAsync();
            targets = runner.Targets;
            if (baseline == null && run is { Failed: false, Completed: > 0, Seconds: >= 5 })
                baseline = new(run, targets);
        }
        catch (Exception ex) { message = SqlWorkloadBackend.Explain(ex); drawer = true; }
        finally { busy = false; stopping = false; runner = null; Save(); Refresh(); }
    }
    private void Stop() { if (runner == null) return; stopping = true; runner.Stop(); Refresh(); }
    public async Task StopAndCloseAsync() { deploymentCancellation?.Cancel(); if (deploymentTask != null) await deploymentTask; Stop(); if (runTask != null) await runTask; timer.Stop(); }
    private void UseBaseline() { if (run != null) { baseline = new(run, targets); Save(); Refresh(); } }
    private void Save()
    {
        try { store.Save(new(Settings, (int)concurrency, baseline)); }
        catch (Exception) { message = "Could not save local settings or baseline. This run is still available while the app stays open."; }
    }
    private void Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        field = value; PropertyChanged?.Invoke(this, new(name));
    }
    private void Refresh()
    {
        PropertyChanged?.Invoke(this, new(null));
        foreach (var command in new[] { LoadPasswordCommand, DeployCommand, TestCommand, StartCommand, StopCommand, EditCommand, DrawerCommand, BaselineCommand, ClearBaselineCommand }) command.Refresh();
    }

    // Used only by the separate offline screenshot project. No simulated mode in the app.
    public void ShowPreview(RunSnapshot before, RunSnapshot? current, bool running, bool showDrawer = false, bool isStopping = false)
    {
        preview = true; stopping = isStopping;
        server = before.Configuration.Connection.Server; database = before.Configuration.Connection.Database;
        username = before.Configuration.Connection.Username; concurrency = before.Configuration.Concurrency;
        connected = true; baseline = new(before, []); run = current ?? before; busy = running; drawer = showDrawer;
        timer.Stop(); Refresh();
    }
}
