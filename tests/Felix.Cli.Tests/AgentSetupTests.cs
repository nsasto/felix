using System.Collections.Generic;
using System.IO;
using System.Text.Json.Nodes;
using Felix.Cli;
using Xunit;

namespace Felix.Cli.Tests;

public sealed class AgentSetupTests
{
    [Fact]
    public void EnsureFelixProjectScaffold_CreatesProjectFilesIdempotently()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName());
        Directory.CreateDirectory(tempRoot);

        var installRoot = Path.Combine(tempRoot, "install");
        Directory.CreateDirectory(installRoot);
        Directory.CreateDirectory(Path.Combine(installRoot, "policies"));
        File.WriteAllText(Path.Combine(installRoot, "config.json.example"), "{\"sync\":{}}\n");
        File.WriteAllText(Path.Combine(installRoot, "policies", "allowlist.json"), "[]\n");
        File.WriteAllText(Path.Combine(installRoot, "policies", "denylist.json"), "[]\n");

        var projectRoot = Path.Combine(tempRoot, "project");
        Directory.CreateDirectory(projectRoot);

        try
        {
            var first = Program.EnsureFelixProjectScaffold(projectRoot, installRoot);
            var second = Program.EnsureFelixProjectScaffold(projectRoot, installRoot);

            Assert.True(first.IsNewProject);
            Assert.Contains("requirements.json", first.Created);
            Assert.Contains("runs/", first.Created);
            Assert.False(second.IsNewProject);
            Assert.Contains("requirements.json", second.Skipped);
            Assert.True(File.Exists(Path.Combine(projectRoot, ".felix", "config.json")));
            Assert.True(File.Exists(Path.Combine(projectRoot, ".gitignore")));
        }
        finally
        {
            Directory.Delete(tempRoot, true);
        }
    }

    [Fact]
    public void EnsureSetupConfigDefaults_FillsMissingSectionsWithoutRemovingExistingFields()
    {
        var config = JsonNode.Parse("{\"sync\":{\"enabled\":true},\"custom\":{\"value\":1}}")!.AsObject();

        Program.EnsureSetupConfigDefaults(config);

        Assert.True(config["sync"]!["enabled"]!.GetValue<bool>());
        Assert.Equal("https://api.runfelix.io", config["sync"]!["base_url"]!.GetValue<string>());
        Assert.Equal(1, config["custom"]!["value"]!.GetValue<int>());
        Assert.NotNull(config["backpressure"]);
        Assert.NotNull(config["executor"]);
        Assert.NotNull(config["agent"]);
    }

    [Fact]
    public void NewAgentKey_IsStableAcrossDictionaryOrderAndGitRemoteFormats()
    {
        var settingsA = new Dictionary<string, object?>
        {
            ["working_directory"] = ".",
            ["executable"] = "copilot",
            ["allow_all"] = true,
            ["environment"] = new Dictionary<string, object?>(),
            ["max_autopilot_continues"] = 10,
            ["custom_agent"] = "",
            ["no_ask_user"] = true
        };

        var settingsB = new Dictionary<string, object?>
        {
            ["custom_agent"] = "",
            ["no_ask_user"] = true,
            ["max_autopilot_continues"] = 10,
            ["environment"] = new Dictionary<string, object?>(),
            ["allow_all"] = true,
            ["executable"] = "copilot",
            ["working_directory"] = "."
        };

        var sshKey = Program.NewAgentKey(
            "copilot",
            "gpt-5.4",
            settingsA,
            @"C:\repo",
            machineNameOverride: "WORKSTATION",
            gitRemoteOverride: "git@github.com:nsasto/felix.git");

        var httpsKey = Program.NewAgentKey(
            "copilot",
            "gpt-5.4",
            settingsB,
            @"C:\repo",
            machineNameOverride: "WORKSTATION",
            gitRemoteOverride: "https://github.com/nsasto/felix");

        Assert.Equal(sshKey, httpsKey);
        Assert.StartsWith("ag_", sshKey);
    }

    [Fact]
    public void UpsertAgentProfiles_ReplacesMatchingNameAndKeepsOthers()
    {
        var existing = new List<Program.AgentProfileDocument>
        {
            new() { Name = "claude", Provider = "claude", Adapter = "claude", Model = "sonnet", Key = "ag_oldclaude", Id = "ag_oldclaude" },
            new() { Name = "copilot", Provider = "copilot", Adapter = "copilot", Model = "gpt-5.4", Key = "ag_oldcopilot", Id = "ag_oldcopilot" }
        };

        var selected = new List<Program.AgentProfileDocument>
        {
            new() { Name = "copilot", Provider = "copilot", Adapter = "copilot", Model = "gpt-5.3-codex", Key = "ag_newcopilot", Id = "ag_newcopilot" },
            new() { Name = "codex", Provider = "codex", Adapter = "codex", Model = "gpt-5.4-codex", Key = "ag_newcodex", Id = "ag_newcodex" }
        };

        var merged = Program.UpsertAgentProfiles(existing, selected);

        Assert.Collection(merged,
            agent => Assert.Equal("claude", agent.Name),
            agent =>
            {
                Assert.Equal("copilot", agent.Name);
                Assert.Equal("gpt-5.3-codex", agent.Model);
                Assert.Equal("ag_newcopilot", agent.Key);
            },
            agent => Assert.Equal("codex", agent.Name));
    }

    [Fact]
    public void GetCopilotExecutableCandidates_UsesProvidedRoots()
    {
        var candidates = Program.GetCopilotExecutableCandidates(
            appDataOverride: null,
            rootsOverride: @"C:\tools\copilot;D:\apps\copilot");

        Assert.Contains(@"C:\tools\copilot\copilot.cmd", candidates);
        Assert.Contains(@"D:\apps\copilot\copilot.ps1", candidates);
    }
}
