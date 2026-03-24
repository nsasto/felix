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
    public void GetTuiSuggestions_ReturnsAllMatches()
    {
        var suggestions = Program.GetTuiSuggestions(BuildManyCommands(), "/");

        Assert.Equal(10, suggestions.Count);
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

    [Fact]
    public void ResolveProcsExecutionMode_UsesStandaloneWhenKillNeedsPrompt()
    {
        var mode = Program.ResolveProcsExecutionMode(new[] { "kill" });

        Assert.Equal(Program.TuiCommandExecutionMode.Standalone, mode);
    }

    [Fact]
    public void ResolveProcsExecutionMode_UsesCapturedWhenKillHasTarget()
    {
        var mode = Program.ResolveProcsExecutionMode(new[] { "kill", "S-0001" });

        Assert.Equal(Program.TuiCommandExecutionMode.Captured, mode);
    }

    [Fact]
    public void GetFooterStatus_ExplainsPlainTextInput()
    {
        var status = Program.GetFooterStatus("status", hasSuggestions: false);

        Assert.Equal("Commands start with /", status);
    }

    [Fact]
    public void GetFooterStatus_ExplainsRunnableSlashCommand()
    {
        var status = Program.GetFooterStatus("/status", hasSuggestions: false);

        Assert.Equal("Press Enter to run command", status);
    }

    [Fact]
    public void DescribeShellResume_ReportsSuccessfulReturn()
    {
        var message = Program.DescribeShellResume(0);

        Assert.Equal("Returned to shell. Command completed successfully.", message);
    }

    [Fact]
    public void NormalizeTuiOutput_TrimsWhitespaceAndCollapsesBlankRuns()
    {
        var normalized = Program.NormalizeTuiOutput("alpha\t\r\n\r\n\r\n beta  \r\n");

        Assert.Equal("alpha\n\n beta", normalized);
    }

    [Fact]
    public void GetSuggestionWindow_KeepsSelectedItemVisible()
    {
        var window = Program.GetSuggestionWindow(suggestionCount: 20, selectedIndex: 12, maxVisibleRows: 5);

        Assert.Equal(10, window.StartIndex);
        Assert.Equal(5, window.Count);
    }

    private static List<Program.TuiCommandDefinition> BuildCommands()
    {
        return new List<Program.TuiCommandDefinition>
        {
            new("help", "Show shell help", "/help", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue())),
            new("status", "Show status", "/status", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue())),
            new("run", "Run a requirement", "/run <requirement-id>", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue()))
        };
    }

    private static List<Program.TuiCommandDefinition> BuildManyCommands()
    {
        return new List<Program.TuiCommandDefinition>
        {
            new("agent-current", "Show current agent", "/agent-current", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue())),
            new("agent-list", "Show configured agents", "/agent-list", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue())),
            new("context", "Run context command", "/context", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue())),
            new("deps", "Show dependency status", "/deps", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue())),
            new("exit", "Exit the TUI", "/exit", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue())),
            new("help", "Show shell help", "/help", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue())),
            new("list", "List requirements", "/list", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue())),
            new("loop", "Loop requirements", "/loop", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue())),
            new("procs", "Show processes", "/procs", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue())),
            new("run", "Run requirement", "/run", _ => Program.TuiCommandExecutionMode.Captured, _ => Task.FromResult(Program.TuiCommandResult.Continue()))
        };
    }
}
