using System.Diagnostics;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    internal sealed record DashboardReport(
        string ProjectRoot,
        DateTimeOffset GeneratedAt,
        IReadOnlyList<DashboardRequirement> Requirements,
        IReadOnlyDictionary<string, int> StatusCounts,
        IReadOnlyList<DashboardRun> RecentRuns,
        DashboardUsageSummary Usage,
        IReadOnlyList<DashboardAgentSummary> Agents,
        string? ActiveAgentId,
        DashboardSettingsSummary Settings,
        IReadOnlyList<DashboardRecommendation> Recommendations);

    internal sealed record DashboardRequirement(string Id, string Title, string Status, string Priority, string? SpecPath, string? LastRunId);

    internal sealed record DashboardRun(string Id, DateTimeOffset UpdatedAt, string? RequirementId, string? EffectiveModel, bool? Succeeded);

    internal sealed record DashboardUsageSummary(int Records, int AvailableRecords, long InputTokens, long OutputTokens, long TotalTokens, IReadOnlyDictionary<string, int> Models);

    internal sealed record DashboardAgentSummary(string Name, string Provider, string Adapter, string Model, string Key, bool IsActive);

    internal sealed record DashboardSettingsSummary(
        bool SyncEnabled,
        string SyncBaseUrl,
        bool GraphifyConfigured,
        bool GraphifyEnabled,
        bool GraphifyAvailable,
        string GraphifyMode,
        string GraphifyOutDir,
        bool GraphifyGraphExists,
        bool GraphifyTeamGraphExists,
        bool GraphifyHookInstalled,
        bool BackpressureHasCommands,
        bool ExploreEnabled,
        int TrackedFileCount,
        bool PricingConfigured,
        bool ReviewRecorded,
        bool ReviewStale);

    internal sealed record DashboardRecommendation(string Impact, string Title, string Reason, string Command);

    internal static DashboardReport BuildDashboardReport(
        string projectRoot,
        DateTimeOffset? generatedAt = null,
        bool? graphifyAvailableOverride = null,
        int? trackedFileCountOverride = null)
    {
        var now = generatedAt ?? DateTimeOffset.Now;
        var felixDir = Path.Combine(projectRoot, ".felix");
        var configPath = Path.Combine(felixDir, "config.json");
        var rawConfig = LoadDashboardJsonObject(configPath);
        var graphifyConfigured = rawConfig["graphify"] is JsonObject;
        var config = rawConfig.DeepClone().AsObject();
        EnsureSetupConfigDefaults(config);

        var requirements = ReadDashboardRequirements(Path.Combine(felixDir, "requirements.json"));
        var statusCounts = requirements
            .GroupBy(req => req.Status, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.Count(), StringComparer.OrdinalIgnoreCase);

        var runsRelative = GetRunsDirectoryRelativePath(config);
        var runsDir = Path.Combine(projectRoot, runsRelative.Replace('/', Path.DirectorySeparatorChar));
        var recentRuns = ReadDashboardRuns(runsDir);
        var usage = ReadDashboardUsage(runsDir);

        var activeAgentId = GetString(config["agent"]?["agent_id"]);
        var agents = ReadDashboardAgents(Path.Combine(felixDir, "agents.json"), activeAgentId);
        var settings = BuildDashboardSettings(
            projectRoot,
            felixDir,
            config,
            graphifyConfigured,
            now,
            graphifyAvailableOverride,
            trackedFileCountOverride);
        var recommendations = BuildDashboardRecommendations(settings, usage);

        return new DashboardReport(
            projectRoot,
            now,
            requirements,
            statusCounts,
            recentRuns,
            usage,
            agents,
            activeAgentId,
            settings,
            recommendations);
    }

    internal static string RenderDashboardHtml(DashboardReport report)
    {
        var total = report.Requirements.Count;
        var planned = CountStatus(report, "planned");
        var inProgress = CountStatus(report, "in_progress") + CountStatus(report, "in-progress");
        var blocked = CountStatus(report, "blocked");
        var done = CountStatus(report, "done");
        var complete = CountStatus(report, "complete");
        var finished = done + complete;
        var percent = total == 0 ? 0 : (int)Math.Round((finished / (double)total) * 100);

        var nextWork = report.Requirements
            .Where(req => req.Status.Equals("in_progress", StringComparison.OrdinalIgnoreCase)
                       || req.Status.Equals("in-progress", StringComparison.OrdinalIgnoreCase)
                       || req.Status.Equals("planned", StringComparison.OrdinalIgnoreCase)
                       || req.Status.Equals("blocked", StringComparison.OrdinalIgnoreCase))
            .Take(8)
            .ToList();

        var html = new StringBuilder();
        html.AppendLine("<!doctype html>");
        html.AppendLine("<html lang=\"en\">");
        html.AppendLine("<head>");
        html.AppendLine("<meta charset=\"utf-8\">");
        html.AppendLine("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">");
        html.AppendLine("<title>Felix Local Report</title>");
        html.AppendLine("<style>");
        html.AppendLine("""
            :root { color-scheme: light; --bg:#f5f6f8; --panel:#ffffff; --ink:#1b1f24; --muted:#68707d; --line:#d9dee7; --accent:#0f6f68; --warn:#9a5b00; --bad:#b42318; --good:#137333; }
            * { box-sizing: border-box; }
            body { margin: 0; font-family: "Segoe UI", Arial, sans-serif; background: var(--bg); color: var(--ink); }
            header { padding: 28px 32px 18px; border-bottom: 1px solid var(--line); background: #ffffff; }
            main { padding: 24px 32px 40px; max-width: 1280px; margin: 0 auto; }
            h1 { margin: 0 0 6px; font-size: 28px; font-weight: 650; }
            h2 { margin: 0 0 14px; font-size: 18px; }
            p { margin: 0; color: var(--muted); }
            .grid { display: grid; grid-template-columns: repeat(12, 1fr); gap: 16px; }
            .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 18px; }
            .span-3 { grid-column: span 3; } .span-4 { grid-column: span 4; } .span-6 { grid-column: span 6; } .span-8 { grid-column: span 8; } .span-12 { grid-column: span 12; }
            .metric { font-size: 28px; font-weight: 700; margin-top: 4px; }
            .label { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .06em; }
            .bar { height: 12px; background: #e8edf2; border-radius: 999px; overflow: hidden; margin: 14px 0 10px; }
            .bar > div { height: 100%; background: var(--accent); }
            table { width: 100%; border-collapse: collapse; }
            th, td { padding: 9px 8px; text-align: left; border-bottom: 1px solid var(--line); vertical-align: top; }
            th { color: var(--muted); font-size: 12px; font-weight: 600; text-transform: uppercase; }
            code { background: #eef1f5; border: 1px solid var(--line); border-radius: 5px; padding: 2px 5px; }
            .pill { display: inline-block; border-radius: 999px; padding: 3px 8px; font-size: 12px; border: 1px solid var(--line); background: #f8fafc; }
            .impact-high { color: var(--bad); font-weight: 650; }
            .impact-medium { color: var(--warn); font-weight: 650; }
            .impact-low { color: var(--accent); font-weight: 650; }
            .muted { color: var(--muted); }
            .good { color: var(--good); } .bad { color: var(--bad); } .warn { color: var(--warn); }
            @media (max-width: 900px) { main, header { padding-left: 16px; padding-right: 16px; } .span-3, .span-4, .span-6, .span-8 { grid-column: span 12; } }
            """);
        html.AppendLine("</style>");
        html.AppendLine("</head>");
        html.AppendLine("<body>");
        html.AppendLine("<header>");
        html.AppendLine("<h1>Felix Local Report</h1>");
        html.Append("<p>").Append(H(report.ProjectRoot)).Append(" - generated ").Append(H(report.GeneratedAt.ToString("yyyy-MM-dd HH:mm:ss zzz"))).AppendLine("</p>");
        html.AppendLine("</header>");
        html.AppendLine("<main class=\"grid\">");

        AppendMetric(html, "Requirements", total.ToString(), "span-3");
        AppendMetric(html, "Finished", $"{finished} ({percent}%)", "span-3");
        AppendMetric(html, "Blocked", blocked.ToString(), "span-3");
        AppendMetric(html, "Usage records", report.Usage.Records.ToString(), "span-3");

        html.AppendLine("<section class=\"panel span-8\"><h2>Progress</h2>");
        html.Append("<div class=\"bar\"><div style=\"width:").Append(percent).AppendLine("%\"></div></div>");
        html.Append("<p>")
            .Append($"Planned {planned} | In progress {inProgress} | Blocked {blocked} | Done {done} | Complete {complete}")
            .AppendLine("</p></section>");

        html.AppendLine("<section class=\"panel span-4\"><h2>Health</h2><table>");
        AppendKeyValue(html, "Sync", report.Settings.SyncEnabled ? "enabled" : "disabled");
        AppendKeyValue(html, "Graphify", report.Settings.GraphifyEnabled ? $"{report.Settings.GraphifyMode}, graph {(report.Settings.GraphifyGraphExists ? "present" : "missing")}" : "disabled");
        AppendKeyValue(html, "Backpressure", report.Settings.BackpressureHasCommands ? "commands configured" : "no commands");
        AppendKeyValue(html, "Explore", report.Settings.ExploreEnabled ? "enabled" : "disabled");
        html.AppendLine("</table></section>");

        AppendRequirementsSection(html, "Current/Next Work", nextWork);
        AppendRunsSection(html, report.RecentRuns);
        AppendUsageSection(html, report.Usage);
        AppendAgentsSection(html, report.Agents, report.ActiveAgentId);
        AppendSettingsSection(html, report.Settings);
        AppendRecommendationsSection(html, report.Recommendations);

        html.AppendLine("</main></body></html>");
        return html.ToString();
    }

    internal static string WriteDashboardHtmlReport(string projectRoot, string? outputDirectory = null, DateTimeOffset? generatedAt = null)
    {
        var report = BuildDashboardReport(projectRoot, generatedAt);
        var html = RenderDashboardHtml(report);
        var dir = outputDirectory ?? Path.Combine(Path.GetTempPath(), "felix-dashboard");
        Directory.CreateDirectory(dir);
        var file = Path.Combine(dir, $"felix-dashboard-{DateTimeOffset.Now:yyyyMMdd-HHmmss}.html");
        File.WriteAllText(file, html, Encoding.UTF8);
        return file;
    }

    static async Task GenerateDashboardHtmlReport(bool noOpen)
    {
        var path = WriteDashboardHtmlReport(_felixProjectRoot);
        AnsiConsole.MarkupLine($"[green]Generated local Felix report:[/] [cyan]{path.EscapeMarkup()}[/]");

        if (!noOpen)
        {
            OpenDashboardHtml(path);
        }

        await Task.CompletedTask;
    }

    static void OpenDashboardHtml(string path)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = path,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[yellow]Could not open browser automatically:[/] {ex.Message.EscapeMarkup()}");
        }
    }

    static IReadOnlyList<DashboardRequirement> ReadDashboardRequirements(string requirementsPath)
    {
        var results = new List<DashboardRequirement>();
        var root = LoadDashboardJsonObject(requirementsPath);
        if (root["requirements"] is not JsonArray requirements)
            return results;

        foreach (var item in requirements.OfType<JsonObject>())
        {
            var id = GetString(item["id"]) ?? "-";
            results.Add(new DashboardRequirement(
                id,
                GetString(item["title"]) ?? GetString(item["spec_path"]) ?? id,
                NormalizeStatus(GetString(item["status"]) ?? "unknown"),
                GetString(item["priority"]) ?? "-",
                GetString(item["spec_path"]),
                GetString(item["last_run_id"])));
        }

        return results.OrderBy(req => req.Id, StringComparer.OrdinalIgnoreCase).ToList();
    }

    static IReadOnlyList<DashboardRun> ReadDashboardRuns(string runsDir)
    {
        if (!Directory.Exists(runsDir))
            return Array.Empty<DashboardRun>();

        return Directory.GetDirectories(runsDir)
            .Select(dir => BuildDashboardRun(dir))
            .OrderByDescending(run => run.UpdatedAt)
            .Take(10)
            .ToList();
    }

    static DashboardRun BuildDashboardRun(string runDir)
    {
        var id = Path.GetFileName(runDir);
        var updated = Directory.GetLastWriteTimeUtc(runDir);
        var usagePath = Directory.GetFiles(runDir, "usage.json", SearchOption.AllDirectories).FirstOrDefault();
        string? requirementId = null;
        string? model = null;
        bool? succeeded = null;

        if (usagePath != null)
        {
            var usage = LoadDashboardJsonObject(usagePath);
            requirementId = GetString(usage["run_id"]);
            model = GetString(usage["model"]?["effective"]) ?? GetString(usage["model"]?["configured"]);
            succeeded = GetBool(usage["succeeded"]);
        }

        return new DashboardRun(id, new DateTimeOffset(updated), requirementId, model, succeeded);
    }

    static DashboardUsageSummary ReadDashboardUsage(string runsDir)
    {
        if (!Directory.Exists(runsDir))
            return new DashboardUsageSummary(0, 0, 0, 0, 0, new Dictionary<string, int>());

        var files = Directory.GetFiles(runsDir, "usage.json", SearchOption.AllDirectories);
        long input = 0;
        long output = 0;
        long total = 0;
        var available = 0;
        var models = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        foreach (var file in files)
        {
            var usageRoot = LoadDashboardJsonObject(file);
            if (GetBool(usageRoot["usage_available"]) == true)
                available++;

            var model = GetString(usageRoot["model"]?["effective"]) ?? GetString(usageRoot["model"]?["configured"]) ?? "unknown";
            var provider = GetString(usageRoot["agent"]?["provider"]) ?? "unknown";
            var key = $"{provider}/{model}";
            models[key] = models.GetValueOrDefault(key) + 1;

            var usage = usageRoot["usage"];
            input += GetLong(usage?["input_tokens"]) ?? 0;
            output += GetLong(usage?["output_tokens"]) ?? 0;
            total += GetLong(usage?["total_tokens"]) ?? GetLong(usage?["observed_tokens"]) ?? 0;
        }

        if (total == 0)
            total = input + output;

        return new DashboardUsageSummary(files.Length, available, input, output, total, models);
    }

    static IReadOnlyList<DashboardAgentSummary> ReadDashboardAgents(string agentsPath, string? activeAgentId)
    {
        var root = LoadDashboardJsonObject(agentsPath);
        if (root["agents"] is not JsonArray agents)
            return Array.Empty<DashboardAgentSummary>();

        var results = new List<DashboardAgentSummary>();
        foreach (var item in agents.OfType<JsonObject>())
        {
            var key = GetString(item["key"]) ?? GetString(item["id"]) ?? "";
            var name = GetString(item["name"]) ?? "-";
            var adapter = GetString(item["adapter"]) ?? name;
            var provider = GetString(item["provider"]) ?? adapter;
            results.Add(new DashboardAgentSummary(
                name,
                provider,
                adapter,
                GetString(item["model"]) ?? "default",
                key,
                !string.IsNullOrWhiteSpace(activeAgentId) && string.Equals(key, activeAgentId, StringComparison.OrdinalIgnoreCase)));
        }

        return results;
    }

    static DashboardSettingsSummary BuildDashboardSettings(
        string projectRoot,
        string felixDir,
        JsonObject config,
        bool graphifyConfigured,
        DateTimeOffset now,
        bool? graphifyAvailableOverride,
        int? trackedFileCountOverride)
    {
        var sync = EnsureObject(config, "sync");
        var graphify = EnsureObject(config, "graphify");
        var backpressure = EnsureObject(config, "backpressure");
        var explore = EnsureObject(config, "explore");
        var state = LoadDashboardJsonObject(Path.Combine(felixDir, "state.json"));

        var graphifyMode = GetString(graphify["mode"]) ?? "local";
        var graphifyOutDir = graphifyMode.Equals("team", StringComparison.OrdinalIgnoreCase)
            ? GetString(graphify["team_out_dir"]) ?? "graphify-out"
            : GetString(graphify["out_dir"]) ?? ".felix/graphify";
        var graphPath = Path.Combine(projectRoot, graphifyOutDir.Replace('/', Path.DirectorySeparatorChar), "graph.json");
        var teamGraphPath = Path.Combine(projectRoot, "graphify-out", "graph.json");

        var lastReviewRaw = GetString(state["last_review"]);
        var reviewRecorded = DateTimeOffset.TryParse(lastReviewRaw, out var lastReview);
        var reviewStale = !reviewRecorded || (now - lastReview).TotalDays > 90;
        var trackedFiles = trackedFileCountOverride ?? CountTrackedFiles(projectRoot);

        return new DashboardSettingsSummary(
            GetBool(sync["enabled"]) == true,
            GetString(sync["base_url"]) ?? "https://api.runfelix.io",
            graphifyConfigured,
            GetBool(graphify["enabled"]) == true,
            graphifyAvailableOverride ?? IsCommandAvailable("graphify"),
            graphifyMode,
            graphifyOutDir,
            File.Exists(graphPath),
            File.Exists(teamGraphPath),
            IsGraphifyHookInstalled(projectRoot),
            backpressure["commands"] is JsonArray commands && commands.Count > 0,
            GetBool(explore["enabled"]) == true,
            trackedFiles,
            File.Exists(Path.Combine(felixDir, "model-pricing.json")),
            reviewRecorded,
            reviewStale);
    }

    static IReadOnlyList<DashboardRecommendation> BuildDashboardRecommendations(DashboardSettingsSummary settings, DashboardUsageSummary usage)
    {
        var recommendations = new List<DashboardRecommendation>();

        if (!settings.GraphifyConfigured || !settings.GraphifyEnabled)
        {
            var hasTeamGraph = settings.GraphifyMode.Equals("team", StringComparison.OrdinalIgnoreCase)
                           || settings.GraphifyTeamGraphExists;
            recommendations.Add(new DashboardRecommendation(
                "high",
                "Enable Graphify investigation",
                hasTeamGraph
                    ? "A team graph appears to be in use; configure Felix to use the shared graph."
                    : "Graphify can reduce broad code searches and repeated file reads during agent investigation.",
                hasTeamGraph ? "felix graphify setup --team" : "felix graphify setup --local"));
        }

        if (!settings.GraphifyAvailable)
        {
            recommendations.Add(new DashboardRecommendation(
                "medium",
                "Install Graphify executable",
                "Felix can configure the skill, but native graph build/query commands need the Graphify CLI on PATH.",
                "uv tool install graphifyy  # or: pipx install graphifyy"));
        }

        if (settings.GraphifyEnabled && !settings.GraphifyGraphExists)
        {
            recommendations.Add(new DashboardRecommendation(
                "high",
                "Build the Graphify graph",
                "Graphify is enabled, but no graph.json exists yet.",
                "felix graphify build"));
        }

        if (settings.GraphifyEnabled
            && settings.GraphifyMode.Equals("team", StringComparison.OrdinalIgnoreCase)
            && !settings.GraphifyHookInstalled)
        {
            recommendations.Add(new DashboardRecommendation(
                "medium",
                "Install Graphify team hooks",
                "Team mode works best with Graphify's post-commit refresh hook and merge driver.",
                "felix graphify setup --team"));
        }

        if (usage.Records > 0 && !settings.PricingConfigured)
        {
            recommendations.Add(new DashboardRecommendation(
                "medium",
                "Configure local model pricing",
                "Usage is being captured, but cost estimates need a local pricing file.",
                "Copy .felix/model-pricing.json.example to .felix/model-pricing.json"));
        }

        if (settings.ReviewStale)
        {
            recommendations.Add(new DashboardRecommendation(
                "medium",
                "Review captured learnings",
                settings.ReviewRecorded ? "The last Felix learning review is more than 90 days old." : "No Felix learning review has been acknowledged yet.",
                "felix review --learnings; felix review --acknowledge"));
        }

        if (!settings.SyncEnabled)
        {
            recommendations.Add(new DashboardRecommendation(
                "low",
                "Optional: enable runfelix.io sync",
                "Sync is not required for local use, but it enables team/cloud workflow tracking.",
                "Set FELIX_SYNC_ENABLED=true and FELIX_SYNC_KEY, or run felix run <id> --sync"));
        }

        if (!settings.BackpressureHasCommands)
        {
            recommendations.Add(new DashboardRecommendation(
                "medium",
                "Add backpressure checks",
                "No project test/build commands are configured, so Felix has less confidence before completing work.",
                "Add backpressure.commands to .felix/config.json"));
        }

        if (settings.TrackedFileCount >= 500 && !settings.ExploreEnabled)
        {
            recommendations.Add(new DashboardRecommendation(
                "medium",
                "Enable exploration for this large repo",
                $"This repo has about {settings.TrackedFileCount} tracked files; explore helps gather context before plan/build.",
                "felix migrate --apply"));
        }

        return recommendations
            .OrderBy(rec => rec.Impact switch { "high" => 0, "medium" => 1, _ => 2 })
            .ToList();
    }

    static JsonObject LoadDashboardJsonObject(string path)
    {
        if (!File.Exists(path))
            return new JsonObject();

        try
        {
            return JsonNode.Parse(File.ReadAllText(path)) as JsonObject ?? new JsonObject();
        }
        catch
        {
            return new JsonObject();
        }
    }

    static int CountTrackedFiles(string projectRoot)
    {
        try
        {
            var psi = new ProcessStartInfo("git", "ls-files")
            {
                WorkingDirectory = projectRoot,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var process = Process.Start(psi);
            if (process == null)
                return 0;

            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit(3000);
            return process.ExitCode == 0
                ? output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).Length
                : 0;
        }
        catch
        {
            return 0;
        }
    }

    static bool IsGraphifyHookInstalled(string projectRoot)
    {
        var hook = Path.Combine(projectRoot, ".git", "hooks", "post-commit");
        if (!File.Exists(hook))
            return false;

        try
        {
            return File.ReadAllText(hook).Contains("graphify", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    static bool IsCommandAvailable(string command)
    {
        var paths = (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
        var extensions = OperatingSystem.IsWindows()
            ? (Environment.GetEnvironmentVariable("PATHEXT") ?? ".EXE;.CMD;.BAT;.COM").Split(';', StringSplitOptions.RemoveEmptyEntries)
            : new[] { string.Empty };

        foreach (var dir in paths)
        {
            foreach (var extension in extensions)
            {
                var candidate = Path.Combine(dir, command + extension.ToLowerInvariant());
                if (File.Exists(candidate))
                    return true;
                candidate = Path.Combine(dir, command + extension.ToUpperInvariant());
                if (File.Exists(candidate))
                    return true;
            }
        }

        return false;
    }

    static int CountStatus(DashboardReport report, string status)
        => report.StatusCounts.TryGetValue(status, out var count) ? count : 0;

    static string NormalizeStatus(string status)
        => status.Equals("in-progress", StringComparison.OrdinalIgnoreCase) ? "in_progress" : status;

    static string? GetString(JsonNode? node)
    {
        if (node is JsonValue value)
        {
            if (value.TryGetValue<string>(out var stringValue))
                return stringValue;
            if (value.TryGetValue<int>(out var intValue))
                return intValue.ToString();
            if (value.TryGetValue<long>(out var longValue))
                return longValue.ToString();
            if (value.TryGetValue<bool>(out var boolValue))
                return boolValue ? bool.TrueString : bool.FalseString;
        }

        return null;
    }

    static bool? GetBool(JsonNode? node)
    {
        if (node is JsonValue value)
        {
            if (value.TryGetValue<bool>(out var boolValue))
                return boolValue;
            if (value.TryGetValue<string>(out var stringValue) && bool.TryParse(stringValue, out var parsed))
                return parsed;
        }

        return null;
    }

    static long? GetLong(JsonNode? node)
    {
        if (node is JsonValue value)
        {
            if (value.TryGetValue<long>(out var longValue))
                return longValue;
            if (value.TryGetValue<int>(out var intValue))
                return intValue;
            if (value.TryGetValue<double>(out var doubleValue))
                return (long)doubleValue;
        }

        return null;
    }

    static string H(string? value) => WebUtility.HtmlEncode(value ?? string.Empty);

    static void AppendMetric(StringBuilder html, string label, string value, string span)
    {
        html.Append("<section class=\"panel ").Append(span).Append("\"><div class=\"label\">")
            .Append(H(label)).Append("</div><div class=\"metric\">")
            .Append(H(value)).AppendLine("</div></section>");
    }

    static void AppendKeyValue(StringBuilder html, string key, string value)
    {
        html.Append("<tr><th>").Append(H(key)).Append("</th><td>").Append(H(value)).AppendLine("</td></tr>");
    }

    static void AppendRequirementsSection(StringBuilder html, string title, IReadOnlyList<DashboardRequirement> requirements)
    {
        html.Append("<section class=\"panel span-12\"><h2>").Append(H(title)).AppendLine("</h2><table><thead><tr><th>ID</th><th>Title</th><th>Status</th><th>Priority</th><th>Last Run</th></tr></thead><tbody>");
        if (requirements.Count == 0)
        {
            html.AppendLine("<tr><td colspan=\"5\" class=\"muted\">No current or planned work found.</td></tr>");
        }
        foreach (var req in requirements)
        {
            html.Append("<tr><td><code>").Append(H(req.Id)).Append("</code></td><td>").Append(H(req.Title)).Append("</td><td><span class=\"pill\">")
                .Append(H(req.Status)).Append("</span></td><td>").Append(H(req.Priority)).Append("</td><td>").Append(H(req.LastRunId ?? "-")).AppendLine("</td></tr>");
        }
        html.AppendLine("</tbody></table></section>");
    }

    static void AppendRunsSection(StringBuilder html, IReadOnlyList<DashboardRun> runs)
    {
        html.AppendLine("<section class=\"panel span-6\"><h2>Recent Runs</h2><table><thead><tr><th>Run</th><th>Updated</th><th>Model</th><th>Status</th></tr></thead><tbody>");
        if (runs.Count == 0)
            html.AppendLine("<tr><td colspan=\"4\" class=\"muted\">No run artifacts found yet.</td></tr>");
        foreach (var run in runs)
        {
            var status = run.Succeeded is null ? "-" : run.Succeeded.Value ? "succeeded" : "failed";
            html.Append("<tr><td><code>").Append(H(run.Id)).Append("</code></td><td>").Append(H(run.UpdatedAt.ToLocalTime().ToString("yyyy-MM-dd HH:mm"))).Append("</td><td>")
                .Append(H(run.EffectiveModel ?? "-")).Append("</td><td>").Append(H(status)).AppendLine("</td></tr>");
        }
        html.AppendLine("</tbody></table></section>");
    }

    static void AppendUsageSection(StringBuilder html, DashboardUsageSummary usage)
    {
        html.AppendLine("<section class=\"panel span-6\"><h2>Usage and Models</h2><table>");
        AppendKeyValue(html, "Records", usage.Records.ToString());
        AppendKeyValue(html, "With token data", usage.AvailableRecords.ToString());
        AppendKeyValue(html, "Input tokens", usage.InputTokens.ToString("N0"));
        AppendKeyValue(html, "Output tokens", usage.OutputTokens.ToString("N0"));
        AppendKeyValue(html, "Total tokens", usage.TotalTokens.ToString("N0"));
        html.AppendLine("</table><h2 style=\"margin-top:18px\">Models</h2><table><tbody>");
        if (usage.Models.Count == 0)
            html.AppendLine("<tr><td class=\"muted\">No model usage recorded yet.</td></tr>");
        foreach (var pair in usage.Models.OrderByDescending(pair => pair.Value).Take(8))
            html.Append("<tr><td>").Append(H(pair.Key)).Append("</td><td>").Append(pair.Value).AppendLine("</td></tr>");
        html.AppendLine("</tbody></table></section>");
    }

    static void AppendAgentsSection(StringBuilder html, IReadOnlyList<DashboardAgentSummary> agents, string? activeAgentId)
    {
        html.AppendLine("<section class=\"panel span-6\"><h2>Agents</h2><table><thead><tr><th>Name</th><th>Provider</th><th>Model</th><th>Active</th></tr></thead><tbody>");
        if (agents.Count == 0)
            html.AppendLine("<tr><td colspan=\"4\" class=\"muted\">No local agent profiles found.</td></tr>");
        foreach (var agent in agents)
        {
            html.Append("<tr><td>").Append(H(agent.Name)).Append("</td><td>").Append(H(agent.Provider)).Append("</td><td>")
                .Append(H(agent.Model)).Append("</td><td>").Append(agent.IsActive ? "yes" : "no").AppendLine("</td></tr>");
        }
        if (!string.IsNullOrWhiteSpace(activeAgentId) && agents.All(agent => !agent.IsActive))
            html.Append("<tr><td colspan=\"4\" class=\"warn\">Configured active agent not found: ").Append(H(activeAgentId)).AppendLine("</td></tr>");
        html.AppendLine("</tbody></table></section>");
    }

    static void AppendSettingsSection(StringBuilder html, DashboardSettingsSummary settings)
    {
        html.AppendLine("<section class=\"panel span-6\"><h2>Settings</h2><table>");
        AppendKeyValue(html, "Sync", settings.SyncEnabled ? $"enabled ({settings.SyncBaseUrl})" : "disabled");
        AppendKeyValue(html, "Graphify mode", settings.GraphifyMode);
        AppendKeyValue(html, "Graphify output", settings.GraphifyOutDir);
        AppendKeyValue(html, "Graphify graph", settings.GraphifyGraphExists ? "present" : "missing");
        AppendKeyValue(html, "Graphify hook", settings.GraphifyHookInstalled ? "installed" : "missing");
        AppendKeyValue(html, "Pricing", settings.PricingConfigured ? "configured" : "not configured");
        AppendKeyValue(html, "Tracked files", settings.TrackedFileCount.ToString("N0"));
        html.AppendLine("</table></section>");
    }

    static void AppendRecommendationsSection(StringBuilder html, IReadOnlyList<DashboardRecommendation> recommendations)
    {
        html.AppendLine("<section class=\"panel span-12\"><h2>Recommended Next Steps</h2><table><thead><tr><th>Impact</th><th>Recommendation</th><th>Reason</th><th>Command</th></tr></thead><tbody>");
        if (recommendations.Count == 0)
            html.AppendLine("<tr><td colspan=\"4\" class=\"good\">No recommendations right now.</td></tr>");
        foreach (var rec in recommendations)
        {
            html.Append("<tr><td class=\"impact-").Append(H(rec.Impact)).Append("\">").Append(H(rec.Impact)).Append("</td><td>")
                .Append(H(rec.Title)).Append("</td><td>").Append(H(rec.Reason)).Append("</td><td><code>")
                .Append(H(rec.Command)).AppendLine("</code></td></tr>");
        }
        html.AppendLine("</tbody></table></section>");
    }
}
