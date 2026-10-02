using Stackish.Core;
using Xunit;

namespace Stackish.Tests;
public class PasswordStoreTests
{
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
