using System.Text;
using Felix.Cli;
using Xunit;

namespace Felix.Cli.Tests;

public sealed class CopilotBridgeTests
{
    [Fact]
    public void BuildArguments_IncludesConfiguredCopilotOptionsAndPrompt()
    {
        var request = new CopilotBridgeCommand.CopilotBridgeRequest
        {
            Prompt = "test prompt",
            Model = "gpt-5.4",
            AllowAll = true,
            NoAskUser = true,
            MaxAutopilotContinues = 2,
            CustomAgent = "general-purpose"
        };

        var args = CopilotBridgeCommand.BuildArguments(request, includeModel: true);

        Assert.Contains("--autopilot", args);
        Assert.Contains("--yolo", args);
        Assert.Contains("--no-ask-user", args);
        Assert.Contains("--max-autopilot-continues", args);
        Assert.Contains("2", args);
        Assert.Contains("--agent", args);
        Assert.Contains("general-purpose", args);
        Assert.Contains("--model", args);
        Assert.Contains("gpt-5.4", args);
        Assert.Equal("-p", args[^2]);
        Assert.Equal("test prompt", args[^1]);
    }

    [Fact]
    public void ExtractCompletionSignal_UsesExactStandaloneTags()
    {
        Assert.Null(CopilotBridgeCommand.ExtractCompletionSignal("status: <promise>TASK_COMPLETE</promise>"));
        Assert.Equal("PLAN_COMPLETE", CopilotBridgeCommand.ExtractCompletionSignal("<promise>PLANNING_COMPLETE</promise>"));
        Assert.Equal("ALL_COMPLETE", CopilotBridgeCommand.ExtractCompletionSignal("<promise>TASK_COMPLETE</promise>\n<promise>ALL_COMPLETE</promise>"));
    }

    [Fact]
    public void IsModelUnavailable_MatchesKnownCopilotFailureText()
    {
        Assert.True(CopilotBridgeCommand.IsModelUnavailable("Model \"auto\" from --model flag is not available"));
        Assert.False(CopilotBridgeCommand.IsModelUnavailable("some other stderr"));
    }

    [Fact]
    public async Task RunAsync_RetriesWithoutModelWhenCopilotRejectsConfiguredModel()
    {
        var tempRoot = CreateTempDirectory();
        try
        {
            var shimPath = Path.Combine(tempRoot, "copilot-retry-shim.ps1");
            var statePath = Path.Combine(tempRoot, "retry-state.txt");
            File.WriteAllText(shimPath, "param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)\n$joined = $Args -join ' '\nif ($joined -match '--model') { 'Model \"gpt-5.4\" from --model flag is not available'; exit 1 }\n'**Task Completed:** Retry succeeded'\n'<promise>TASK_COMPLETE</promise>'\n", new UTF8Encoding(false));

            var request = new CopilotBridgeCommand.CopilotBridgeRequest
            {
                Executable = shimPath,
                Prompt = "test prompt",
                WorkingDirectory = tempRoot,
                Model = "gpt-5.4"
            };

            var result = await CopilotBridgeCommand.RunAsync(request);

            Assert.True(result.RetriedWithoutModel);
            Assert.True(result.Succeeded);
            Assert.Equal(0, result.ExitCode);
            Assert.Equal("TASK_COMPLETE", result.Signal);
            Assert.DoesNotContain("--model", result.Arguments);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public async Task RunAsync_ExecutesCmdShimAndCapturesOutput()
    {
        var repoRoot = FindRepoRoot();
        var shimPath = Path.Combine(repoRoot, ".felix", "tests", "agent-shim-argv.cmd");
        var tempRoot = CreateTempDirectory();

        try
        {
            var agentWorkDir = Path.Combine(tempRoot, "agent-workdir");
            var runsDir = Path.Combine(tempRoot, "runs", "run-1");
            Directory.CreateDirectory(agentWorkDir);
            Directory.CreateDirectory(runsDir);
            var planPath = Path.Combine(runsDir, "plan-S-0001.md");

            var request = new CopilotBridgeCommand.CopilotBridgeRequest
            {
                Executable = shimPath,
                Prompt = $"write the plan to **{planPath}**",
                WorkingDirectory = agentWorkDir,
                Model = "gpt-5.4",
                Environment = new Dictionary<string, string?>
                {
                    ["FELIX_AGENT_TEST"] = "1"
                }
            };

            var result = await CopilotBridgeCommand.RunAsync(request);

            Assert.True(result.UsedBridge);
            Assert.True(result.Succeeded);
            Assert.Contains("__AGENT_SHIM__=1", result.Output);
            Assert.Contains("__AGENT_ENV__=1", result.Output);
            Assert.Contains("__AGENT_PROMPT_LEN__=0", result.Output);
            Assert.Equal("PLAN_COMPLETE", result.Signal);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public async Task RunAsync_PrefersBatchWrapperOverPowerShellShim()
    {
        if (!OperatingSystem.IsWindows())
            return;

        var tempRoot = CreateTempDirectory();
        try
        {
            var shimDir = Path.Combine(tempRoot, "copilotCli");
            Directory.CreateDirectory(shimDir);

            var ps1Path = Path.Combine(shimDir, "copilot.ps1");
            var batPath = Path.Combine(shimDir, "copilot.bat");

            File.WriteAllText(ps1Path, "Write-Output 'ps1 shim should not run'", new UTF8Encoding(false));
            File.WriteAllText(batPath, "@echo off\r\necho batch wrapper ran\r\n", new UTF8Encoding(false));

            var request = new CopilotBridgeCommand.CopilotBridgeRequest
            {
                Executable = ps1Path,
                Prompt = "test prompt",
                WorkingDirectory = tempRoot
            };

            var result = await CopilotBridgeCommand.RunAsync(request);

            Assert.True(result.Succeeded);
            Assert.EndsWith("copilot.bat", result.ResolvedExecutable, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("batch wrapper ran", result.Output);
            Assert.DoesNotContain("ps1 shim should not run", result.Output);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    private static string CreateTempDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), $"felix-copilot-bridge-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

    private static string FindRepoRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null && !Directory.Exists(Path.Combine(current.FullName, ".felix")))
            current = current.Parent;

        return current?.FullName ?? throw new InvalidOperationException("Could not locate repo root from test output directory.");
    }
}