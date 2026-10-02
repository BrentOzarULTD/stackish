using Stackish.Core;
using Xunit;

namespace Stackish.Tests;

public sealed class DeploymentTests
{
    [Fact]
    public async Task FailedPreflightPreservesBaseline()
    {
        bool cleared = false;
        await Assert.ThrowsAsync<InvalidOperationException>(() => DatabaseDeployment.ExecuteAsync(
            (batch, _) => throw new InvalidOperationException("Rejected schema"),
            beforeModuleChanges: () => cleared = true));
        Assert.False(cleared);
    }

    [Fact]
    public async Task CancellationBeforeModulesPreservesBaseline()
    {
        using var cancellation = new CancellationTokenSource();
        bool cleared = false;
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => DatabaseDeployment.ExecuteAsync(
            (batch, _) => { cancellation.Cancel(); return Task.CompletedTask; },
            beforeModuleChanges: () => cleared = true, token: cancellation.Token));
        Assert.False(cleared);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task BaselineClearedOnceBeforeFirstModuleEvenIfDeploymentFails(bool fail)
    {
        int cleared = 0, modules = 0;
        async Task Execute() => await DatabaseDeployment.ExecuteAsync((batch, _) =>
        {
            if (batch.Sql.Contains("CREATE OR ALTER", StringComparison.OrdinalIgnoreCase))
            {
                Assert.Equal(1, cleared);
                if (modules++ == 0) Assert.Contains("FUNCTION dbo.Stackish_SplitTags", batch.Sql);
                if (fail) throw new InvalidOperationException("Module installation failed");
            }
            else if (modules == 0) Assert.Equal(0, cleared);
            return Task.CompletedTask;
        }, beforeModuleChanges: () => cleared++);

        if (fail) await Assert.ThrowsAsync<InvalidOperationException>(Execute);
        else await Execute();
        Assert.Equal(1, cleared);
        Assert.True(modules > 0);
    }
}
