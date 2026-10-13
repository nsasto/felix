using Felix.Cli;
using Xunit;

namespace Felix.Cli.Tests;

public sealed class Felix3CommandTests
{
    [Fact]
    public void RootCommand_RegistersFelix3WorkflowCommands()
    {
        var root = Program.CreateRootCommand(@"C:\fake\felix.ps1");
        var v3 = Assert.Single(root.Subcommands, command => command.Name == "v3");
        var names = v3.Subcommands.Select(command => command.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);

        Assert.Contains("setup", names);
        Assert.Contains("migrate", names);
        Assert.Contains("run", names);
        Assert.Contains("next", names);
        Assert.Contains("loop", names);
        Assert.Contains("resume", names);
        Assert.Contains("stop", names);
        Assert.Contains("status", names);
    }

    [Fact]
    public void Felix3Run_RequiresExplicitSpecPath()
    {
        var root = Program.CreateRootCommand(@"C:\fake\felix.ps1");
        var run = root.Subcommands.Single(command => command.Name == "v3").Subcommands.Single(command => command.Name == "run");

        Assert.Contains(run.Options, option => option.Name == "spec" && option.IsRequired);
        Assert.Single(run.Arguments);
    }
}
