using System.Text.Json;
using Felix.Cli;
using Xunit;

namespace Felix.Cli.Tests;

public sealed class DashboardHtmlTests
{
    [Fact]
    public void DashboardCommand_HasHtmlAndNoOpenOptions()
    {
        var root = Program.CreateRootCommand(@"C:\fake\felix.ps1");
        var dashboard = root.Subcommands.Single(c => c.Name == "dashboard");
        var options = dashboard.Options.Select(o => o.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);

        Assert.Contains("html", options);
        Assert.Contains("no-open", options);
    }

    [Fact]
    public void BuildDashboardReport_HandlesEmptyRepo()
    {
        var root = CreateTempDirectory();
        try
        {
            Directory.CreateDirectory(Path.Combine(root, ".felix"));

            var report = Program.BuildDashboardReport(root, new DateTimeOffset(2026, 6, 24, 12, 0, 0, TimeSpan.Zero), graphifyAvailableOverride: false, trackedFileCountOverride: 0);

            Assert.Empty(report.Requirements);
            Assert.Empty(report.RecentRuns);
            Assert.Contains(report.Recommendations, rec => rec.Command == "felix graphify setup --local");
            Assert.Contains(report.Recommendations, rec => rec.Command.Contains("graphifyy"));
            Assert.Contains(report.Recommendations, rec => rec.Command.Contains("felix review --learnings"));
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public void BuildDashboardReport_ReadsPopulatedRepoAndUsage()
    {
        var root = CreateTempDirectory();
        try
        {
            var felix = Path.Combine(root, ".felix");
            var runs = Path.Combine(root, "runs", "S-0001-20260624-120000-it1");
            Directory.CreateDirectory(felix);
            Directory.CreateDirectory(runs);
            File.WriteAllText(Path.Combine(felix, "requirements.json"), """
                {
                  "requirements": [
                    { "id": "S-0001", "title": "Build dashboard", "status": "planned", "priority": "high" },
                    { "id": "S-0002", "title": "Ship release", "status": "complete", "priority": "medium" }
                  ]
                }
                """);
            File.WriteAllText(Path.Combine(felix, "config.json"), """
                {
                  "sync": { "enabled": true, "base_url": "https://api.runfelix.io" },
                  "backpressure": { "commands": [ { "name": "test", "cmd": "dotnet test" } ] },
                  "explore": { "enabled": true },
                  "graphify": { "enabled": true, "mode": "local", "out_dir": ".felix/graphify" }
                }
                """);
            File.WriteAllText(Path.Combine(felix, "state.json"), """
                { "last_review": "2026-06-01T00:00:00Z" }
                """);
            File.WriteAllText(Path.Combine(felix, "agents.json"), """
                { "agents": [ { "key": "ag_one", "name": "codex", "provider": "codex", "adapter": "codex", "model": "gpt-5.5" } ] }
                """);
            File.WriteAllText(Path.Combine(runs, "usage.json"), """
                {
                  "_v": 1,
                  "run_id": "S-0001-20260624-120000-it1",
                  "succeeded": true,
                  "usage_available": true,
                  "agent": { "provider": "codex" },
                  "model": { "effective": "gpt-5.5" },
                  "usage": { "input_tokens": 100, "output_tokens": 50, "total_tokens": 150 }
                }
                """);

            var report = Program.BuildDashboardReport(root, new DateTimeOffset(2026, 6, 24, 12, 0, 0, TimeSpan.Zero), graphifyAvailableOverride: true, trackedFileCountOverride: 100);

            Assert.Equal(2, report.Requirements.Count);
            Assert.Equal(1, report.StatusCounts["planned"]);
            Assert.Single(report.RecentRuns);
            Assert.Equal(150, report.Usage.TotalTokens);
            Assert.Single(report.Agents);
            Assert.DoesNotContain(report.Recommendations, rec => rec.Command.Contains("felix review --learnings"));
            Assert.DoesNotContain(report.Recommendations, rec => rec.Command.Contains("felix migrate --apply"));
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public void Recommendations_CoverGraphifyTeamPricingReviewAndExplore()
    {
        var root = CreateTempDirectory();
        try
        {
            var felix = Path.Combine(root, ".felix");
            var runs = Path.Combine(root, "runs", "S-0001-20260624-120000-it1");
            Directory.CreateDirectory(felix);
            Directory.CreateDirectory(Path.Combine(root, "graphify-out"));
            Directory.CreateDirectory(runs);
            File.WriteAllText(Path.Combine(root, "graphify-out", "graph.json"), "{}");
            File.WriteAllText(Path.Combine(felix, "config.json"), """
                {
                  "graphify": { "enabled": false, "mode": "team", "team_out_dir": "graphify-out" },
                  "backpressure": { "commands": [] },
                  "explore": { "enabled": false },
                  "sync": { "enabled": false }
                }
                """);
            File.WriteAllText(Path.Combine(felix, "state.json"), "{}");
            File.WriteAllText(Path.Combine(runs, "usage.json"), """
                {
                  "_v": 1,
                  "usage_available": true,
                  "agent": { "provider": "codex" },
                  "model": { "effective": "gpt-5.5" },
                  "usage": { "total_tokens": 12 }
                }
                """);

            var report = Program.BuildDashboardReport(root, new DateTimeOffset(2026, 6, 24, 12, 0, 0, TimeSpan.Zero), graphifyAvailableOverride: true, trackedFileCountOverride: 750);
            var commands = report.Recommendations.Select(rec => rec.Command).ToArray();

            Assert.Contains("felix graphify setup --team", commands);
            Assert.Contains("Copy .felix/model-pricing.json.example to .felix/model-pricing.json", commands);
            Assert.Contains("felix review --learnings; felix review --acknowledge", commands);
            Assert.Contains("Add backpressure.commands to .felix/config.json", commands);
            Assert.Contains("felix migrate --apply", commands);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public void RenderDashboardHtml_IncludesMajorSections()
    {
        var root = CreateTempDirectory();
        try
        {
            Directory.CreateDirectory(Path.Combine(root, ".felix"));
            var report = Program.BuildDashboardReport(root, new DateTimeOffset(2026, 6, 24, 12, 0, 0, TimeSpan.Zero), graphifyAvailableOverride: false, trackedFileCountOverride: 0);
            var html = Program.RenderDashboardHtml(report);

            Assert.Contains("Progress", html);
            Assert.Contains("Current/Next Work", html);
            Assert.Contains("Recent Runs", html);
            Assert.Contains("Usage and Models", html);
            Assert.Contains("Agents", html);
            Assert.Contains("Settings", html);
            Assert.Contains("Health", html);
            Assert.Contains("Recommended Next Steps", html);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public void WriteDashboardHtmlReport_WritesHtmlToRequestedDirectory()
    {
        var root = CreateTempDirectory();
        var output = CreateTempDirectory();
        try
        {
            Directory.CreateDirectory(Path.Combine(root, ".felix"));

            var path = Program.WriteDashboardHtmlReport(root, output, new DateTimeOffset(2026, 6, 24, 12, 0, 0, TimeSpan.Zero));

            Assert.True(File.Exists(path));
            Assert.Equal(output, Path.GetDirectoryName(path));
            Assert.Contains("Felix Local Report", File.ReadAllText(path));
        }
        finally
        {
            Directory.Delete(root, true);
            Directory.Delete(output, true);
        }
    }

    private static string CreateTempDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), $"felix-dashboard-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }
}
