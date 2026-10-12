using System.Data;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

namespace Stackish.Core;

public sealed partial class SqlWorkloadBackend(ConnectionSettings settings, string password) : IWorkloadBackend
{
    private string ConnectionString => new SqlConnectionStringBuilder
    {
        DataSource = settings.Server.Trim(), InitialCatalog = settings.Database.Trim(),
        UserID = settings.Username.Trim(), Password = password,
        Encrypt = SqlConnectionEncryptOption.Mandatory, TrustServerCertificate = settings.TrustCertificate,
        ConnectTimeout = 15, Pooling = false, ApplicationName = "Stackish Desktop"
    }.ConnectionString;

    public async Task<string> TestAsync(CancellationToken token = default)
    {
        if (string.IsNullOrWhiteSpace(settings.Server) || string.IsNullOrWhiteSpace(settings.Database) ||
            string.IsNullOrWhiteSpace(settings.Username))
            throw new InvalidOperationException("Enter the server, database and username first.");
        await using var connection = new SqlConnection(ConnectionString);
        await connection.OpenAsync(token);
        foreach (var batch in ReadinessBatches())
        {
            await using var preflight = new SqlCommand(batch, connection) { CommandTimeout = 60 };
            await preflight.ExecuteNonQueryAsync(token);
        }
        return connection.ServerVersion;
    }

    public async Task DeployAsync(IProgress<string>? progress = null, CancellationToken token = default, Action? beforeModuleChanges = null)
    {
        await using var connection = new SqlConnection(ConnectionString);
        await connection.OpenAsync(token);
        await DatabaseDeployment.ExecuteAsync(async (batch, cancellation) =>
        {
            await using var command = new SqlCommand(batch.Sql, connection) { CommandTimeout = 60 };
            await command.ExecuteNonQueryAsync(cancellation);
        }, beforeModuleChanges, progress, token);
    }

    public static IEnumerable<string> ReadinessBatches() => new[] { "preflight.sql", "inventory.sql" }
        .SelectMany(name => Regex.Split(WorkloadFiles.Read(name), @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase))
        .Where(batch => !string.IsNullOrWhiteSpace(batch));

    public async Task<string[]> PrepareAsync(CancellationToken cancellationToken)
    {
        await using var connection = new SqlConnection(ConnectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new SqlCommand(WorkloadFiles.Read("parameters.sql"), connection) { CommandTimeout = 600 };
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var targets = new List<string>();
        while (await reader.ReadAsync(cancellationToken)) targets.Add(reader.GetString(0));
        return targets.ToArray();
    }

    public async Task<IWorkloadWorker> OpenWorkerAsync(CancellationToken cancellationToken)
    {
        var connection = new SqlConnection(ConnectionString);
        try { await connection.OpenAsync(cancellationToken); return new SqlWorker(connection); }
        catch { await connection.DisposeAsync(); throw; }
    }

    // Use the exact packaged SQL, but make branch selection reproducible per worker.
    // Text GUIDs and state-dependent outcomes remain live; this is not an exact replay.
    public static string CallsSql { get; } = ChoiceDeclaration().Replace(WorkloadFiles.Read("calls.sql"),
        m => $"DECLARE {m.Groups[1].Value} int=" + (m.Groups[1].Value == "@Operation" ? "@RunOperation;" : "@RunChoice;"));

    [GeneratedRegex(@"DECLARE (@Operation|@g\d+_Choice) int=ABS\(CONVERT\(bigint,CHECKSUM\(NEWID\(\)\)\)\) % 100;")]
    private static partial Regex ChoiceDeclaration();

    private sealed class SqlWorker(SqlConnection connection) : IWorkloadWorker
    {
        private readonly SqlCommand command = CreateCommand(connection);
        private static SqlCommand CreateCommand(SqlConnection connection)
        {
            var command = new SqlCommand(CallsSql, connection) { CommandTimeout = 600 };
            command.Parameters.Add("@InputTargets", SqlDbType.NVarChar, -1);
            command.Parameters.Add("@RunOperation", SqlDbType.Int);
            command.Parameters.Add("@RunChoice", SqlDbType.Int);
            return command;
        }
        public async Task<OperationResult> ExecuteAsync(Operation operation, string targets, CancellationToken token)
        {
            command.Parameters["@InputTargets"].Value = targets;
            command.Parameters["@RunOperation"].Value = operation.GroupRoll;
            command.Parameters["@RunChoice"].Value = operation.Choice;
            // Keep cancellation registered through reader disposal, including gaps between reads.
            using var cancellation = token.Register(() => command.Cancel());
            token.ThrowIfCancellationRequested();
            string? outcome = null;
            await using var reader = await command.ExecuteReaderAsync(token);
            do
            {
                bool status = reader.FieldCount > 0 && reader.GetName(0) == "Outcome";
                var row = new object[reader.FieldCount];
                while (await reader.ReadAsync(token))
                {
                    reader.GetValues(row); // Consume every column, including all page result sets.
                    if (status) outcome = reader.GetString(0);
                }
            } while (await reader.NextResultAsync(token));
            if (!operation.IsRead && outcome is not ("Applied" or "Conflict" or "NoChange" or "NotFound"))
                throw new InvalidOperationException("Write returned an unrecognized result. Check the installed Stackish version.");
            return new(operation.IsRead, outcome);
        }
        public async ValueTask DisposeAsync()
        {
            await command.DisposeAsync();
            await connection.DisposeAsync();
        }
    }

    public static bool IsFatal(Exception exception) => exception is SqlException sql &&
        (sql.Class >= 20 || sql.Number is 18456 or 4060 or 208 or 2812);

    public static string Explain(Exception exception) => exception is SqlException sql ? sql.Number switch
    {
        51004 => "Stackish is not fully installed in this database, or extra Stackish objects are present. Use Install / update Stackish to install its procedures and function. Unexpected extra Stackish objects must be reviewed separately.",
        18456 => "Login rejected. Check the username and password. (SQL 18456)",
        4060 => "The database is unavailable or this login cannot access it. (SQL 4060)",
        -2 => "The operation timed out. The server may be busy or the query may be expensive.",
        1205 => "SQL Server chose this call as a deadlock victim. (SQL 1205)",
        208 or 2812 => "A required Stackish object is missing. Install Stackish in the selected database.",
        _ when sql.Number >= 51000 => sql.Message,
        _ => $"SQL Server error {sql.Number}: {sql.Message}"
    } : exception.Message;
}
