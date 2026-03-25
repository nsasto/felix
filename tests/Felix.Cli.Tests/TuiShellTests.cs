using Felix.Cli;
using Xunit;
using System.Reflection;

namespace Felix.Cli.Tests;

public class TuiShellTests
{
    [Fact]
    public void TokenizeShellInput_PreservesQuotedSegments()
    {
        var tokens = Program.TokenizeShellInput("spec create \"improve tui shell\" --quick");

        Assert.Equal(new[] { "spec", "create", "improve tui shell", "--quick" }, tokens);
    }

    [Fact]
    public void BuildTuiCommandCatalog_IncludesSupportedSurfaceAndExcludesUnsupportedEntries()
    {
        var catalog = Program.BuildTuiCommandCatalog(Program.CreateRootCommand("felix.ps1"));

        Assert.Contains(catalog, entry => entry.SlashPath == "run");
        Assert.Contains(catalog, entry => entry.SlashPath == "run-next");
        Assert.Contains(catalog, entry => entry.SlashPath == "loop");
        Assert.Contains(catalog, entry => entry.SlashPath == "spec pull");
        Assert.Contains(catalog, entry => entry.SlashPath == "agent current");
        Assert.Contains(catalog, entry => entry.SlashPath == "procs list");
        Assert.DoesNotContain(catalog, entry => entry.SlashPath == "procs kill");
        Assert.DoesNotContain(catalog, entry => entry.SlashPath == "install");
        Assert.DoesNotContain(catalog, entry => entry.SlashPath == "tui");
        Assert.DoesNotContain(catalog, entry => entry.SlashPath == "dashboard");
    }

    [Fact]
    public void ResolveExecutionMode_UsesConfiguredSafetyPolicy()
    {
        Assert.Equal(Program.TuiCommandExecutionMode.Captured, Program.ResolveExecutionMode("spec pull"));
        Assert.Equal(Program.TuiCommandExecutionMode.Captured, Program.ResolveExecutionMode("agent current"));
        Assert.Equal(Program.TuiCommandExecutionMode.Standalone, Program.ResolveExecutionMode("run"));
        Assert.Equal(Program.TuiCommandExecutionMode.Standalone, Program.ResolveExecutionMode("procs kill"));
    }

    [Fact]
    public void GetTuiSuggestions_FiltersCommandsAfterSlash()
    {
        var catalog = Program.BuildTuiCommandCatalog(Program.CreateRootCommand("felix.ps1"));

        var suggestions = Program.GetTuiSuggestions(catalog, "/spec p");

        Assert.Contains(suggestions, suggestion => suggestion.Value == "spec pull");
        Assert.Contains(suggestions, suggestion => suggestion.Value == "spec push");
        Assert.DoesNotContain(suggestions, suggestion => suggestion.Value == "status");
    }

    [Fact]
    public void GetTuiSuggestions_AllowsBareCommandInput()
    {
        var catalog = Program.BuildTuiCommandCatalog(Program.CreateRootCommand("felix.ps1"));

        var suggestions = Program.GetTuiSuggestions(catalog, "spec p");

        Assert.Contains(suggestions, suggestion => suggestion.Value == "spec pull");
        Assert.Contains(suggestions, suggestion => suggestion.Value == "spec push");
    }

    [Fact]
    public void GetTuiSuggestions_SuggestsNestedCommandOptions()
    {
        var catalog = Program.BuildTuiCommandCatalog(Program.CreateRootCommand("felix.ps1"));

        var suggestions = Program.GetTuiSuggestions(catalog, "/spec pull --");

        Assert.Contains(suggestions, suggestion => suggestion.Value == "--dry-run");
        Assert.Contains(suggestions, suggestion => suggestion.Value == "--delete");
        Assert.Contains(suggestions, suggestion => suggestion.Value == "--force");
    }

    [Fact]
    public void GetTuiSuggestions_SuggestsDynamicStatusesForSpecStatus()
    {
        var catalog = Program.BuildTuiCommandCatalog(Program.CreateRootCommand("felix.ps1"));

        var suggestions = Program.GetTuiSuggestions(catalog, "/spec status S-0001 ");

        Assert.Contains(suggestions, suggestion => suggestion.Value == "planned");
        Assert.Contains(suggestions, suggestion => suggestion.Value == "done");
    }

    [Fact]
    public void ResolveFinalInput_UsesSelectedCommandSuggestion()
    {
        var result = Program.ResolveFinalInput("/sp", new List<Program.TuiSuggestion>
        {
            new("spec pull", "Download changed specs from server", true)
        }, 0);

        Assert.Equal("/spec pull", result);
    }

    [Fact]
    public void ResolveFinalInput_ReplacesTrailingArgumentWithSelection()
    {
        var result = Program.ResolveFinalInput("/spec status S-0", new List<Program.TuiSuggestion>
        {
            new("S-0001", "requirement id", false)
        }, 0);

        Assert.Equal("/spec status S-0001", result);
    }

    [Fact]
    public void AcceptSelectedSuggestionIntoInput_AddsTrailingSpaceForExactCommand()
    {
        var catalog = Program.BuildTuiCommandCatalog(Program.CreateRootCommand("felix.ps1"));

        var accepted = Program.AcceptSelectedSuggestionIntoInput(catalog, "/sp", new List<Program.TuiSuggestion>
        {
            new("spec list", "List requirements", true)
        }, 0);

        Assert.Equal("/spec list ", accepted);
    }

    [Fact]
    public void AcceptSelectedSuggestionIntoInput_ReplacesTrailingArgument()
    {
        var catalog = Program.BuildTuiCommandCatalog(Program.CreateRootCommand("felix.ps1"));

        var accepted = Program.AcceptSelectedSuggestionIntoInput(catalog, "/spec status S-0", new List<Program.TuiSuggestion>
        {
            new("S-0001", "requirement id", false)
        }, 0);

        Assert.Equal("/spec status S-0001", accepted);
    }

    [Fact]
    public void AcceptSelectedSuggestionIntoInput_PreservesInputForBlankRow()
    {
        var catalog = Program.BuildTuiCommandCatalog(Program.CreateRootCommand("felix.ps1"));

        var accepted = Program.AcceptSelectedSuggestionIntoInput(catalog, "/list", new List<Program.TuiSuggestion>
        {
            new(string.Empty, "run as typed", false),
            new("--status", "option", false)
        }, 0);

        Assert.Equal("/list", accepted);
    }

    [Fact]
    public void EnterAcceptsHighlightedSuggestion_WhenSelectionIsNotBlank()
    {
        var stateType = typeof(Program).GetNestedType("TuiShellState", BindingFlags.NonPublic)!;
        var state = Activator.CreateInstance(stateType)!;
        stateType.GetProperty("Suggestions")!.SetValue(state, new List<Program.TuiSuggestion>
        {
            new(string.Empty, "run as typed", false),
            new("--status", "option", false)
        });
        stateType.GetProperty("SelectedSuggestion")!.SetValue(state, 1);

        var shouldAccept = typeof(Program)
            .GetMethod("ShouldAcceptSelectedSuggestionOnEnter", BindingFlags.NonPublic | BindingFlags.Static)!
            .Invoke(null, new[] { state });

        Assert.Equal(true, shouldAccept);
    }

    [Fact]
    public void EnterRunsTextbox_WhenBlankRunAsTypedRowIsSelected()
    {
        var stateType = typeof(Program).GetNestedType("TuiShellState", BindingFlags.NonPublic)!;
        var state = Activator.CreateInstance(stateType)!;
        stateType.GetProperty("Suggestions")!.SetValue(state, new List<Program.TuiSuggestion>
        {
            new(string.Empty, "run as typed", false),
            new("--status", "option", false)
        });
        stateType.GetProperty("SelectedSuggestion")!.SetValue(state, 0);

        var shouldAccept = typeof(Program)
            .GetMethod("ShouldAcceptSelectedSuggestionOnEnter", BindingFlags.NonPublic | BindingFlags.Static)!
            .Invoke(null, new[] { state });

        Assert.Equal(false, shouldAccept);
    }

    [Fact]
    public void MoveSelectionToRunAsTypedRow_SelectsBlankSuggestionWhenPresent()
    {
        var stateType = typeof(Program).GetNestedType("TuiShellState", BindingFlags.NonPublic)!;
        var state = Activator.CreateInstance(stateType)!;
        stateType.GetProperty("Suggestions")!.SetValue(state, new List<Program.TuiSuggestion>
        {
            new(string.Empty, "run as typed", false),
            new("--status", "option", false),
            new("--format", "option", false)
        });
        stateType.GetProperty("SelectedSuggestion")!.SetValue(state, 2);

        typeof(Program)
            .GetMethod("MoveSelectionToRunAsTypedRow", BindingFlags.NonPublic | BindingFlags.Static)!
            .Invoke(null, new[] { state });

        Assert.Equal(0, stateType.GetProperty("SelectedSuggestion")!.GetValue(state));
    }

    [Fact]
    public void ArgumentSuggestions_StartWithBlankRunAsTypedRow()
    {
        var catalog = Program.BuildTuiCommandCatalog(Program.CreateRootCommand("felix.ps1"));

        var suggestions = Program.GetTuiSuggestions(catalog, "/list");

        Assert.NotEmpty(suggestions);
        Assert.Equal(string.Empty, suggestions[0].Value);
        Assert.Equal("run as typed", suggestions[0].Description);
    }

    [Fact]
    public void CompleteNestedCommand_IsReadyToExecute()
    {
        var catalog = Program.BuildTuiCommandCatalog(Program.CreateRootCommand("felix.ps1"));

        var ready = typeof(Program)
            .GetMethod("IsTuiInputReadyToExecute", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)!
            .Invoke(null, new object[] { catalog, "/spec pull --dry-run" });

        Assert.Equal(true, ready);
    }

    [Fact]
    public void RunNextCommand_IsSupportedButStagesBeforeExecution()
    {
        var catalog = Program.BuildTuiCommandCatalog(Program.CreateRootCommand("felix.ps1"));

        var shouldStage = typeof(Program)
            .GetMethod("ShouldStageCommandBeforeExecution", BindingFlags.NonPublic | BindingFlags.Static)!
            .Invoke(null, new object[] { catalog, "/run-next" });

        Assert.Equal(true, shouldStage);
    }

    [Theory]
    [InlineData(120, 40, "Normal")]
    [InlineData(90, 40, "Compact")]
    [InlineData(90, 12, "Minimal")]
    public void GetTuiLayoutMode_UsesExpectedThresholds(int width, int height, string expected)
    {
        Assert.Equal(expected, Program.GetTuiLayoutMode(width, height).ToString());
    }

    [Theory]
    [InlineData("Normal", 6)]
    [InlineData("Compact", 4)]
    [InlineData("Minimal", 1)]
    public void GetSuggestionLimit_IsBoundedByLayoutMode(string layoutModeName, int expected)
    {
        var layoutMode = Enum.Parse<Program.TuiLayoutMode>(layoutModeName);
        Assert.Equal(expected, Program.GetSuggestionLimit(layoutMode));
    }

    [Fact]
    public void TranscriptWindow_DefaultsToLatestEntries()
    {
        var state = CreateTranscriptState(count: 20, Program.TuiLayoutMode.Normal, scrollOffset: 0);
        var visible = InvokeVisibleTranscriptEntries(state);

        Assert.Equal(16, visible.Count);
        Assert.Equal("/cmd 5", GetTranscriptCommand(visible[0]));
        Assert.Equal("/cmd 20", GetTranscriptCommand(visible[^1]));
    }

    [Fact]
    public void TranscriptWindow_PageUpShowsOlderEntries()
    {
        var state = CreateTranscriptState(count: 20, Program.TuiLayoutMode.Normal, scrollOffset: 4);
        var visible = InvokeVisibleTranscriptEntries(state);

        Assert.Equal(16, visible.Count);
        Assert.Equal("/cmd 1", GetTranscriptCommand(visible[0]));
        Assert.Equal("/cmd 16", GetTranscriptCommand(visible[^1]));
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
    public void GetStandaloneResumePrompt_ReturnsExpectedMessage()
    {
        Assert.Equal("Press any key to return to Felix TUI...", Program.GetStandaloneResumePrompt());
    }

    [Fact]
    public void NormalizeTuiOutput_TrimsWhitespaceAndCollapsesBlankRuns()
    {
        var normalized = Program.NormalizeTuiOutput("alpha\t\r\n\r\n\r\n beta  \r\n");

        Assert.Equal("alpha\n\n beta", normalized);
    }

    private static object CreateTranscriptState(int count, Program.TuiLayoutMode layoutMode, int scrollOffset)
    {
        var stateType = typeof(Program).GetNestedType("TuiShellState", BindingFlags.NonPublic)!;
        var transcriptEntryType = typeof(Program).GetNestedType("TuiTranscriptEntry", BindingFlags.NonPublic)!;
        var state = Activator.CreateInstance(stateType)!;

        stateType.GetProperty("LayoutMode")!.SetValue(state, layoutMode);
        stateType.GetProperty("TranscriptScrollOffset")!.SetValue(state, scrollOffset);

        var transcript = stateType.GetProperty("Transcript")!.GetValue(state);
        var addMethod = transcript!.GetType().GetMethod("Add")!;
        for (var index = 1; index <= count; index++)
        {
            var entry = Activator.CreateInstance(transcriptEntryType, $"/cmd {index}", $"out {index}", false)!;
            addMethod.Invoke(transcript, new[] { entry });
        }

        return state;
    }

    private static IReadOnlyList<object> InvokeVisibleTranscriptEntries(object state)
    {
        var method = typeof(Program).GetMethod("GetVisibleTranscriptEntries", BindingFlags.NonPublic | BindingFlags.Static)!;
        var result = (System.Collections.IEnumerable)method.Invoke(null, new[] { state })!;
        return result.Cast<object>().ToList();
    }

    private static string GetTranscriptCommand(object transcriptEntry)
    {
        return (string)transcriptEntry.GetType().GetProperty("Command")!.GetValue(transcriptEntry)!;
    }
}
