using Felix.Cli;
using Xunit;

namespace Felix.Cli.Tests;

public class TuiShellTests
{
    [Fact]
    public void TokenizeShellInput_PreservesQuotedSegments()
    {
        var tokens = Program.TokenizeShellInput("/spec-create \"improve tui shell\" --quick");

        Assert.Equal(new[] { "/spec-create", "improve tui shell", "--quick" }, tokens);
    }

    [Fact]
    public void GetTuiSuggestions_ShowsNothingBeforeSlashInput()
    {
        var suggestions = Program.GetTuiSuggestions(BuildCommands(), string.Empty);

        Assert.Empty(suggestions);
    }

    [Fact]
    public void GetTuiSuggestions_FiltersCommandsAfterSlash()
    {
        var suggestions = Program.GetTuiSuggestions(BuildCommands(), "/st");

        Assert.Contains(suggestions, suggestion => suggestion.Value == "status");
        Assert.DoesNotContain(suggestions, suggestion => suggestion.Value == "run");
    }

    [Fact]
    public void ResolveFinalInput_UsesSelectedCommandSuggestion()
    {
        var result = Program.ResolveFinalInput("/ru", new List<Program.TuiSuggestion>
        {
            new("run", "Run a planned requirement", true)
        }, 0);

        Assert.Equal("/run", result);
    }

    [Fact]
    public void ResolveFinalInput_ReplacesTrailingArgumentWithSelection()
    {
        var result = Program.ResolveFinalInput("/run S-0", new List<Program.TuiSuggestion>
        {
            new("S-0001", "planned requirement", false)
        }, 0);

        Assert.Equal("/run S-0001", result);
    }

    private static List<Program.TuiCommandDefinition> BuildCommands()
    {
        return new List<Program.TuiCommandDefinition>
        {
            new("help", "Show shell help", "/help", _ => Task.FromResult(true)),
            new("status", "Show status", "/status", _ => Task.FromResult(true)),
            new("run", "Run a requirement", "/run <requirement-id>", _ => Task.FromResult(true))
        };
    }
}
