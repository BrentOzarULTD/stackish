using Stackish.Core;
using Xunit;

namespace Stackish.Tests;
public class PasswordStoreTests
{
    [NativeVaultFact]
    public void NativeVaultCreatesReloadsUpdatesIsolatesAndDeletes()
    {
        var connection = new ConnectionSettings("stackish-vault-test-" + Guid.NewGuid().ToString("N"), "fixture", "test-user");
        var other = connection with { Username = "different-user" };
        var store = PasswordStore.Create();
        try
        {
            Assert.Null(store.Read(connection));
            store.Delete(connection); // Missing entries are safe to remove.
            store.Write(connection, "synthetic-初期-🔑");
            Assert.Equal("synthetic-初期-🔑", PasswordStore.Create().Read(connection));
            Assert.Null(store.Read(other));
            store.Write(other, "separate-synthetic-password");
            store.Write(connection, "synthetic-replacement-ß");
            Assert.Equal("synthetic-replacement-ß", PasswordStore.Create().Read(connection));
            Assert.Equal("separate-synthetic-password", store.Read(other));
            store.Write(connection, "");
            Assert.Equal("", store.Read(connection));
            store.Delete(connection);
            Assert.Null(PasswordStore.Create().Read(connection));
            Assert.Equal("separate-synthetic-password", store.Read(other));
            store.Delete(connection);
        }
        finally
        {
            try { store.Delete(connection); }
            finally { store.Delete(other); }
        }
        Assert.Null(store.Read(connection));
        Assert.Null(store.Read(other));
    }

    [Fact]
    public void KeysSeparateConnectionsWithoutAmbiguousDelimiters()
    {
        var connection = new ConnectionSettings("server", "database", "login");
        Assert.Equal(PasswordStore.Key(connection), PasswordStore.Key(new(" server ", " database ", " login ", true)));
        Assert.NotEqual(PasswordStore.Key(connection), PasswordStore.Key(connection with { Server = "another" }));
        Assert.NotEqual(PasswordStore.Key(connection), PasswordStore.Key(connection with { Database = "another" }));
        Assert.NotEqual(PasswordStore.Key(connection), PasswordStore.Key(connection with { Username = "Login" }));
        Assert.NotEqual(PasswordStore.Key(new("a/b", "c", "d")), PasswordStore.Key(new("a", "b/c", "d")));
        Assert.DoesNotContain("login", PasswordStore.Key(connection));
    }
}

public sealed class NativeVaultFactAttribute : FactAttribute
{
    public NativeVaultFactAttribute()
    {
        if (Environment.GetEnvironmentVariable("STACKISH_TEST_NATIVE_VAULT") != "1")
            Skip = "Opt in with STACKISH_TEST_NATIVE_VAULT=1; creates and deletes synthetic OS vault entries.";
        else if (!OperatingSystem.IsMacOS() && !OperatingSystem.IsWindows())
            Skip = "Native credential storage supports macOS and Windows.";
    }
}
