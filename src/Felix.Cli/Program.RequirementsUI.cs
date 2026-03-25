using System.Text.Json;
using System.Text.Json.Nodes;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    static Task ShowListUI(string felixPs1, string? statusFilter, string? priorityFilter, string? tagFilter, string? blockedByFilter, bool withDeps)
    {
        var rule = new Rule("[cyan]Requirements List[/]").RuleStyle(Style.Parse("cyan dim"));
        AnsiConsole.Write(rule);
        AnsiConsole.WriteLine();

        List<JsonElement> filtered;
        Dictionary<string, string> requirementStatusesById;
        int totalCount;
        try
        {
            var requirements = ParseRequirementsJson(ReadRequirementsJson()) ?? new List<JsonElement>();
            if (requirements.Count == 0)
            {
                AnsiConsole.MarkupLine("[yellow]No requirements found. Run felix setup in a project directory.[/]");
                return Task.CompletedTask;
            }

            requirementStatusesById = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var req in requirements)
            {
                var id = GetJsonString(req, "id");
                if (string.IsNullOrWhiteSpace(id))
                    continue;

                requirementStatusesById[id] = GetJsonString(req, "status") ?? "unknown";
            }

            totalCount = requirements.Count;
            filtered = requirements.Where(req =>
            {
                var status = GetJsonString(req, "status") ?? "unknown";
                var priority = GetJsonString(req, "priority") ?? "medium";
                if (statusFilter != null && !string.Equals(status, statusFilter, StringComparison.OrdinalIgnoreCase)) return false;
                if (priorityFilter != null && !string.Equals(priority, priorityFilter, StringComparison.OrdinalIgnoreCase)) return false;
                if (!string.IsNullOrWhiteSpace(tagFilter))
                {
                    var requestedTags = tagFilter.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                    if (requestedTags.Length > 0)
                    {
                        var requirementTags = GetRequirementTags(req);
                        if (!requestedTags.Any(tag => requirementTags.Contains(tag, StringComparer.OrdinalIgnoreCase)))
                            return false;
                    }
                }

                if (string.Equals(blockedByFilter, "incomplete-deps", StringComparison.OrdinalIgnoreCase))
                {
                    var dependencies = GetRequirementDependencies(req);
                    if (dependencies.Count == 0)
                        return false;

                    var hasIncompleteDependency = dependencies.Any(depId =>
                    {
                        if (!requirementStatusesById.TryGetValue(depId, out var depStatus))
                            return true;

                        return !string.Equals(depStatus, "done", StringComparison.OrdinalIgnoreCase)
                            && !string.Equals(depStatus, "complete", StringComparison.OrdinalIgnoreCase);
                    });

                    if (!hasIncompleteDependency)
                        return false;
                }

                return true;
            }).OrderBy(req => GetJsonString(req, "id"), StringComparer.OrdinalIgnoreCase).ToList();
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Error: {ex.Message}[/]");
            return Task.CompletedTask;
        }

        var filters = new List<string>();
        if (!string.IsNullOrWhiteSpace(statusFilter)) filters.Add($"status={statusFilter}");
        if (!string.IsNullOrWhiteSpace(priorityFilter)) filters.Add($"priority={priorityFilter}");
        if (!string.IsNullOrWhiteSpace(tagFilter)) filters.Add($"tags={tagFilter}");
        if (!string.IsNullOrWhiteSpace(blockedByFilter)) filters.Add($"blocked-by={blockedByFilter}");
        if (withDeps) filters.Add("with-deps");

        if (filters.Count > 0)
        {
            AnsiConsole.Write(new Panel($"[grey]{string.Join("   ", filters.Select(filter => filter.EscapeMarkup()))}[/]")
            {
                Header = new PanelHeader("[cyan]Active Filters[/]"),
                Border = BoxBorder.Rounded,
                BorderStyle = Style.Parse("grey")
            });
            AnsiConsole.WriteLine();
        }

        if (filtered.Count == 0)
        {
            AnsiConsole.MarkupLine(totalCount == 0
                ? "[yellow]No requirements found. Run felix setup in a project directory.[/]"
                : "[yellow]No requirements matched the current filters.[/]");
            AnsiConsole.MarkupLine($"[grey]Showing 0 of {totalCount} requirements[/]");
            return Task.CompletedTask;
        }

        var table = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]ID[/]"))
            .AddColumn(new TableColumn("[yellow]Title[/]").Width(60))
            .AddColumn(new TableColumn("[yellow]Status[/]").Centered())
            .AddColumn(new TableColumn("[yellow]Priority[/]").Centered());

        if (withDeps)
            table.AddColumn(new TableColumn("[yellow]Dependencies[/]").Width(36));

        foreach (var req in filtered)
        {
            var id = req.GetProperty("id").GetString() ?? string.Empty;
            var title = req.TryGetProperty("title", out var titleProp) ? titleProp.GetString() ?? string.Empty
                      : req.TryGetProperty("spec_path", out var spProp) ? spProp.GetString() ?? string.Empty
                      : string.Empty;
            var status = req.GetProperty("status").GetString() ?? string.Empty;
            var priority = req.TryGetProperty("priority", out var priorityProp) ? priorityProp.GetString() : "medium";
            var dependencies = GetRequirementDependencies(req);

            var statusColor = status switch
            {
                "complete" => "green",
                "done" => "blue",
                "in_progress" => "yellow",
                "in-progress" => "yellow",
                "planned" => "cyan",
                "blocked" => "red",
                _ => "white"
            };

            var priorityColor = priority switch
            {
                "critical" => "red bold",
                "high" => "yellow",
                "medium" => "blue",
                "low" => "grey",
                _ => "white"
            };

            if (title.Length > 57) title = title[..54] + "...";

            var cells = new List<string>
            {
                $"[cyan]{id}[/]",
                $"[white]{title.EscapeMarkup()}[/]",
                $"[{statusColor}]{status.EscapeMarkup()}[/]",
                $"[{priorityColor}]{priority.EscapeMarkup()}[/]"
            };

            if (withDeps)
            {
                var dependencyText = dependencies.Count == 0
                    ? "[grey]-[/]"
                    : string.Join(", ",
                        dependencies.Select(depId =>
                        {
                            if (!requirementStatusesById.TryGetValue(depId, out var depStatus))
                                return $"[red]{depId.EscapeMarkup()} (missing)[/]";

                            var depColor = string.Equals(depStatus, "done", StringComparison.OrdinalIgnoreCase)
                                || string.Equals(depStatus, "complete", StringComparison.OrdinalIgnoreCase)
                                ? "green"
                                : "yellow";
                            return $"[{depColor}]{depId.EscapeMarkup()} ({depStatus.EscapeMarkup()})[/]";
                        }));
                cells.Add(dependencyText);
            }

            table.AddRow(cells.ToArray());
        }

        AnsiConsole.Write(table);
        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine($"[grey]Showing {filtered.Count} of {totalCount} requirements[/]");
        return Task.CompletedTask;
    }

    static List<string> GetRequirementTags(JsonElement requirement)
    {
        if (!requirement.TryGetProperty("tags", out var tagsElement) || tagsElement.ValueKind != JsonValueKind.Array)
            return new List<string>();

        return tagsElement
            .EnumerateArray()
            .Where(tag => tag.ValueKind == JsonValueKind.String)
            .Select(tag => tag.GetString())
            .Where(tag => !string.IsNullOrWhiteSpace(tag))
            .Select(tag => tag!)
            .ToList();
    }

    static List<string> GetRequirementDependencies(JsonElement requirement)
    {
        if (!requirement.TryGetProperty("depends_on", out var depsElement) || depsElement.ValueKind != JsonValueKind.Array)
            return new List<string>();

        return depsElement
            .EnumerateArray()
            .Where(dep => dep.ValueKind == JsonValueKind.String)
            .Select(dep => dep.GetString())
            .Where(dep => !string.IsNullOrWhiteSpace(dep))
            .Select(dep => dep!)
            .ToList();
    }

    static async Task ShowValidateUI(string felixPs1, string requirementId)
    {
        var output = await ExecutePowerShellCapture(felixPs1, "validate", requirementId, "--json");
        var trimmed = output.Trim();
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            AnsiConsole.MarkupLine("[red]Validation returned no output.[/]");
            Environment.ExitCode = 1;
            return;
        }

        try
        {
            using var doc = JsonDocument.Parse(trimmed);
            var root = doc.RootElement;
            var success = GetJsonBool(root, "success") == true;
            var exitCode = GetJsonInt(root, "exitCode") ?? 1;
            var reason = GetJsonString(root, "reason") ?? string.Empty;
            var color = success ? "green" : "red";

            AnsiConsole.Write(new Rule("[cyan]Requirement Validation[/]").RuleStyle(Style.Parse("cyan dim")));
            AnsiConsole.WriteLine();

            var summary = new Table()
                .Border(TableBorder.Rounded)
                .BorderColor(Color.Grey)
                .AddColumn(new TableColumn("[yellow]Field[/]").NoWrap())
                .AddColumn(new TableColumn("[yellow]Value[/]"));
            summary.AddRow("Requirement", $"[white]{requirementId.EscapeMarkup()}[/]");
            summary.AddRow("Status", $"[{color}]{(success ? "passed" : "failed")}[/]");
            summary.AddRow("Exit Code", $"[{color}]{exitCode}[/]");
            summary.AddRow("Reason", $"[white]{reason.EscapeMarkup()}[/]");

            AnsiConsole.Write(new Panel(summary)
            {
                Header = new PanelHeader($"[{color}]Validation Summary[/]"),
                Border = BoxBorder.Rounded,
                BorderStyle = Style.Parse(color)
            });
            AnsiConsole.WriteLine();

            if (root.TryGetProperty("output", out var outputLines) && outputLines.ValueKind == JsonValueKind.Array && outputLines.GetArrayLength() > 0)
            {
                var body = string.Join(Environment.NewLine, outputLines.EnumerateArray().Select(line => line.ToString().EscapeMarkup()));
                AnsiConsole.Write(new Panel($"[grey]{body}[/]")
                {
                    Header = new PanelHeader("[cyan]Validator Output[/]"),
                    Border = BoxBorder.Rounded,
                    BorderStyle = Style.Parse("grey")
                });
                AnsiConsole.WriteLine();
            }

            Environment.ExitCode = exitCode;
        }
        catch (JsonException)
        {
            await ExecutePowerShell(felixPs1, "validate", requirementId);
        }
    }

    static void ShowDependencyOverviewUI()
    {
        var requirements = ParseRequirementsJson(ReadRequirementsJson()) ?? new List<JsonElement>();
        var lookup = requirements
            .Where(req => GetJsonString(req, "id") is not null)
            .ToDictionary(req => GetJsonString(req, "id")!, req => req, StringComparer.OrdinalIgnoreCase);

        AnsiConsole.Write(new Rule("[cyan]Incomplete Dependencies[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var rows = new List<(string id, string title, string status, string deps)>();
        foreach (var requirement in requirements)
        {
            var deps = GetRequirementDependencies(requirement);
            if (deps.Count == 0)
                continue;

            var incompleteDeps = new List<string>();
            foreach (var depId in deps)
            {
                if (!lookup.TryGetValue(depId, out var depReq))
                {
                    incompleteDeps.Add($"{depId} (missing)");
                    continue;
                }

                var depStatus = GetJsonString(depReq, "status") ?? "unknown";
                if (!IsCompletedStatus(depStatus))
                    incompleteDeps.Add($"{depId} ({depStatus})");
            }

            if (incompleteDeps.Count == 0)
                continue;

            rows.Add((
                GetJsonString(requirement, "id") ?? "-",
                GetJsonString(requirement, "title") ?? "-",
                GetJsonString(requirement, "status") ?? "unknown",
                string.Join(", ", incompleteDeps)));
        }

        if (rows.Count == 0)
        {
            AnsiConsole.MarkupLine("[green]All requirements have complete dependencies.[/]");
            AnsiConsole.WriteLine();
            Environment.ExitCode = 0;
            return;
        }

        var table = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Requirement[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Status[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Title[/]"))
            .AddColumn(new TableColumn("[yellow]Incomplete Dependencies[/]"));

        foreach (var row in rows.OrderBy(r => r.id, StringComparer.OrdinalIgnoreCase))
        {
            table.AddRow(
                row.id.EscapeMarkup(),
                RenderStatusMarkup(row.status),
                row.title.EscapeMarkup(),
                row.deps.EscapeMarkup());
        }

        AnsiConsole.Write(table);
        AnsiConsole.WriteLine();
        Environment.ExitCode = 1;
    }

    static void ShowRequirementDependenciesUI(string requirementId, bool checkOnly, bool showTree)
    {
        var requirements = ParseRequirementsJson(ReadRequirementsJson()) ?? new List<JsonElement>();
        var lookup = requirements
            .Where(req => GetJsonString(req, "id") is not null)
            .ToDictionary(req => GetJsonString(req, "id")!, req => req, StringComparer.OrdinalIgnoreCase);

        if (!lookup.TryGetValue(requirementId, out var requirement))
        {
            AnsiConsole.MarkupLine($"[red]Requirement {requirementId.EscapeMarkup()} not found.[/]");
            Environment.ExitCode = 1;
            return;
        }

        var dependencies = GetRequirementDependencies(requirement);
        var incompleteDeps = new List<string>();
        var missingDeps = new List<string>();

        foreach (var depId in dependencies)
        {
            if (!lookup.TryGetValue(depId, out var depReq))
            {
                missingDeps.Add(depId);
                incompleteDeps.Add(depId);
                continue;
            }

            var depStatus = GetJsonString(depReq, "status") ?? "unknown";
            if (!IsCompletedStatus(depStatus))
                incompleteDeps.Add(depId);
        }

        var allComplete = incompleteDeps.Count == 0;
        var borderColor = allComplete ? "green" : "yellow";

        AnsiConsole.Write(new Rule($"[cyan]Dependency Analysis: {requirementId.EscapeMarkup()}[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var summary = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Field[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Value[/]"));
        summary.AddRow("Requirement", $"[white]{requirementId.EscapeMarkup()}[/]");
        summary.AddRow("Title", $"[white]{(GetJsonString(requirement, "title") ?? "-").EscapeMarkup()}[/]");
        summary.AddRow("Status", RenderStatusMarkup(GetJsonString(requirement, "status") ?? "unknown"));
        summary.AddRow("Dependencies", $"[white]{dependencies.Count}[/]");
        summary.AddRow("Result", allComplete ? "[green]all complete[/]" : "[yellow]incomplete dependencies detected[/]");

        AnsiConsole.Write(new Panel(summary)
        {
            Header = new PanelHeader("[cyan]Summary[/]"),
            Border = BoxBorder.Rounded,
            BorderStyle = Style.Parse(borderColor)
        });
        AnsiConsole.WriteLine();

        if (dependencies.Count == 0)
        {
            AnsiConsole.MarkupLine("[green]No dependencies.[/]");
            AnsiConsole.WriteLine();
            Environment.ExitCode = 0;
            return;
        }

        if (!checkOnly)
        {
            var table = new Table()
                .Border(TableBorder.Rounded)
                .BorderColor(Color.Grey)
                .AddColumn(new TableColumn("[yellow]Dependency[/]").NoWrap())
                .AddColumn(new TableColumn("[yellow]Status[/]").NoWrap())
                .AddColumn(new TableColumn("[yellow]Priority[/]").NoWrap())
                .AddColumn(new TableColumn("[yellow]Title[/]"));

            foreach (var depId in dependencies)
            {
                if (!lookup.TryGetValue(depId, out var depReq))
                {
                    table.AddRow(depId.EscapeMarkup(), "[red]missing[/]", "-", "[grey]Missing from requirements.json[/]");
                    continue;
                }

                table.AddRow(
                    depId.EscapeMarkup(),
                    RenderStatusMarkup(GetJsonString(depReq, "status") ?? "unknown"),
                    (GetJsonString(depReq, "priority") ?? "-").EscapeMarkup(),
                    (GetJsonString(depReq, "title") ?? "-").EscapeMarkup());
            }

            AnsiConsole.Write(table);
            AnsiConsole.WriteLine();
        }

        if (showTree)
        {
            var tree = new Tree($"[cyan]{requirementId.EscapeMarkup()}[/]");
            var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { requirementId };
            AddDependencyTreeNodes(tree, requirement, lookup, visited);
            AnsiConsole.Write(tree);
            AnsiConsole.WriteLine();
        }

        if (!allComplete)
        {
            if (missingDeps.Count > 0)
                AnsiConsole.MarkupLine($"[red]Missing:[/] {string.Join(", ", missingDeps.Select(dep => dep.EscapeMarkup()))}");
            if (incompleteDeps.Count > 0)
                AnsiConsole.MarkupLine($"[yellow]Incomplete:[/] {string.Join(", ", incompleteDeps.Select(dep => dep.EscapeMarkup()))}");
        }

        Environment.ExitCode = allComplete ? 0 : 1;
    }

    static void AddDependencyTreeNodes(Tree tree, JsonElement requirement, Dictionary<string, JsonElement> lookup, HashSet<string> visited)
    {
        foreach (var depId in GetRequirementDependencies(requirement))
        {
            AddDependencyTreeNode(tree, depId, lookup, visited);
        }
    }

    static void AddDependencyTreeNode(IHasTreeNodes parent, string depId, Dictionary<string, JsonElement> lookup, HashSet<string> visited)
    {
        if (!lookup.TryGetValue(depId, out var depReq))
        {
            parent.AddNode($"[red]{depId.EscapeMarkup()} (missing)[/]");
            return;
        }

        var status = GetJsonString(depReq, "status") ?? "unknown";
        var title = GetJsonString(depReq, "title") ?? "-";
        var color = IsCompletedStatus(status) ? "green" : "yellow";
        var currentNode = parent.AddNode($"[{color}]{depId.EscapeMarkup()}[/] [grey]{title.EscapeMarkup()} ({status.EscapeMarkup()})[/]");

        if (!visited.Add(depId))
        {
            currentNode.AddNode("[grey]cycle detected[/]");
            return;
        }

        foreach (var childDepId in GetRequirementDependencies(depReq))
        {
            AddDependencyTreeNode(currentNode, childDepId, lookup, visited);
        }

        visited.Remove(depId);
    }

    static bool IsCompletedStatus(string? status)
        => string.Equals(status, "done", StringComparison.OrdinalIgnoreCase)
        || string.Equals(status, "complete", StringComparison.OrdinalIgnoreCase);

    static string RenderStatusMarkup(string status)
    {
        var color = status.ToLowerInvariant() switch
        {
            "done" or "complete" => "green",
            "in_progress" or "reserved" => "yellow",
            "blocked" => "red",
            _ => "grey"
        };
        return $"[{color}]{status.EscapeMarkup()}[/]";
    }

    static (string Color, string Icon, string Label) GetRequirementStatusStyle(string status)
    {
        return status switch
        {
            "draft" => ("grey", ".", "Draft"),
            "complete" => ("green", "*", "Complete"),
            "done" => ("blue", "+", "Done"),
            "in_progress" => ("yellow", ">", "In Progress"),
            "planned" => ("cyan1", "o", "Planned"),
            "blocked" => ("red", "x", "Blocked"),
            _ => ("grey", "?", status)
        };
    }

    static void RenderRequirementDistribution(int total, IReadOnlyDictionary<string, int> statusCounts)
    {
        if (total <= 0)
            return;

        var draft = statusCounts.GetValueOrDefault("draft", 0);
        var complete = statusCounts.GetValueOrDefault("complete", 0);
        var done = statusCounts.GetValueOrDefault("done", 0);
        var inProgress = statusCounts.GetValueOrDefault("in_progress", 0);
        var planned = statusCounts.GetValueOrDefault("planned", 0);
        var blocked = statusCounts.GetValueOrDefault("blocked", 0);

        var barWidth = 64;
        var draftWidth = (int)Math.Round((draft / (double)total) * barWidth);
        var completeWidth = (int)Math.Round((complete / (double)total) * barWidth);
        var doneWidth = (int)Math.Round((done / (double)total) * barWidth);
        var inProgressWidth = (int)Math.Round((inProgress / (double)total) * barWidth);
        var plannedWidth = (int)Math.Round((planned / (double)total) * barWidth);
        var usedWidth = draftWidth + completeWidth + doneWidth + inProgressWidth + plannedWidth;
        var blockedWidth = Math.Max(0, barWidth - usedWidth);

        AnsiConsole.MarkupLine(
            $"[grey]{"".PadRight(draftWidth, '#')}[/]" +
            $"[green]{"".PadRight(completeWidth, '#')}[/]" +
            $"[blue]{"".PadRight(doneWidth, '#')}[/]" +
            $"[yellow]{"".PadRight(inProgressWidth, '#')}[/]" +
            $"[cyan1]{"".PadRight(plannedWidth, '#')}[/]" +
            $"[red]{"".PadRight(blockedWidth, '#')}[/]");
        AnsiConsole.WriteLine();
    }

    static void AddSettingsRow(Table table, string label, string value)
    {
        table.AddRow($"[grey]{label.EscapeMarkup()}[/]", value);
    }

    static string GetJsonString(JsonObject obj, string propertyName, string fallback = "-")
    {
        var value = obj[propertyName];
        if (value == null)
            return fallback;

        return value switch
        {
            JsonValue jsonValue => jsonValue.TryGetValue<string>(out var stringValue) && !string.IsNullOrWhiteSpace(stringValue)
                ? stringValue
                : jsonValue.ToJsonString(),
            _ => value.ToJsonString()
        };
    }

    static int GetJsonInt(JsonObject obj, string propertyName, int fallback)
    {
        var value = obj[propertyName];
        if (value is JsonValue jsonValue && jsonValue.TryGetValue<int>(out var intValue))
            return intValue;

        return fallback;
    }

    static bool GetJsonBool(JsonObject obj, string propertyName, bool fallback)
    {
        var value = obj[propertyName];
        if (value is JsonValue jsonValue && jsonValue.TryGetValue<bool>(out var boolValue))
            return boolValue;

        return fallback;
    }

    static string FormatBoolSetting(bool value)
    {
        return value ? "[green]enabled[/]" : "[grey]disabled[/]";
    }

    static string FormatApiKeyStatus(JsonObject sync)
    {
        var apiKey = sync["api_key"] as JsonValue;
        return apiKey != null && apiKey.TryGetValue<string>(out var value) && !string.IsNullOrWhiteSpace(value)
            ? "[green]set[/]"
            : "[grey]not set[/]";
    }

    static string FormatCommandsSummary(JsonObject backpressure)
    {
        var commands = backpressure["commands"] as JsonArray;
        if (commands == null || commands.Count == 0)
            return "[grey]0 commands[/]";

        return $"[white]{commands.Count} command{(commands.Count == 1 ? string.Empty : "s")}[/]";
    }

    static string FormatDisabledPluginsSummary(JsonObject plugins)
    {
        var disabled = plugins["disabled"] as JsonArray;
        if (disabled == null || disabled.Count == 0)
            return "[grey]0 disabled[/]";

        return $"[white]{disabled.Count} disabled[/]";
    }

    static Task ShowStatusUI(string felixPs1)
    {
        ClearIfStandalone();
        AnsiConsole.Write(new Rule("[cyan]Felix Status[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        Dictionary<string, int> statusCounts;
        int total;
        try
        {
            var output = ReadRequirementsJson();
            var trimmed = output.Trim();
            if (string.IsNullOrEmpty(trimmed) || !trimmed.StartsWith("["))
            {
                AnsiConsole.MarkupLine("[yellow]No requirements found. Run felix setup in a project directory.[/]");
                return Task.CompletedTask;
            }

            using var doc = JsonDocument.Parse(trimmed);
            var requirements = doc.RootElement;
            if (requirements.ValueKind != JsonValueKind.Array)
            {
                AnsiConsole.MarkupLine("[yellow]No requirements found. Run felix setup in a project directory.[/]");
                return Task.CompletedTask;
            }

            total = requirements.GetArrayLength();
            statusCounts = new Dictionary<string, int>();
            foreach (var req in requirements.EnumerateArray())
            {
                var status = req.GetProperty("status").GetString() ?? "unknown";
                statusCounts[status] = statusCounts.GetValueOrDefault(status, 0) + 1;
            }
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Error: {ex.Message.EscapeMarkup()}[/]");
            return Task.CompletedTask;
        }

        var configuredAgents = ReadConfiguredAgents() ?? new List<ConfiguredAgent>();
        var currentAgent = configuredAgents.FirstOrDefault(agent => agent.IsCurrent);

        var configPath = Path.Combine(_felixProjectRoot, ".felix", "config.json");
        var config = LoadSetupConfig(configPath);
        EnsureSetupConfigDefaults(config);

        var agentConfig = EnsureObject(config, "agent");
        var sync = EnsureObject(config, "sync");
        var backpressure = EnsureObject(config, "backpressure");
        var executor = EnsureObject(config, "executor");
        var plugins = EnsureObject(config, "plugins");
        var paths = EnsureObject(config, "paths");

        var statusTable = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Status[/]").NoWrap().Width(16))
            .AddColumn(new TableColumn("[yellow]Count[/]").RightAligned().NoWrap().Width(7))
            .AddColumn(new TableColumn("[yellow]Share[/]").RightAligned().NoWrap().Width(7));

        foreach (var status in new[] { "draft", "in_progress", "planned", "blocked", "done", "complete" })
        {
            var count = statusCounts.GetValueOrDefault(status, 0);
            if (count == 0)
                continue;

            var style = GetRequirementStatusStyle(status);
            var percent = total == 0 ? 0 : (int)Math.Round((count / (double)total) * 100);
            statusTable.AddRow(
                $"[{style.Color}]{style.Icon} {style.Label.EscapeMarkup()}[/]",
                $"[{style.Color} bold]{count}[/]",
                $"[{style.Color}]{percent}%[/]");
        }

        var settingsTable = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .Expand()
            .AddColumn(new TableColumn("[yellow]Setting[/]").RightAligned().NoWrap().Width(24))
            .AddColumn(new TableColumn("[yellow]Value[/]"));

        var activeAgentLabel = currentAgent == null
            ? $"[grey]{GetJsonString(agentConfig, "agent_id", "not set").EscapeMarkup()}[/]"
            : $"[white]{currentAgent.Name.EscapeMarkup()}[/] [grey](provider: {currentAgent.Provider.EscapeMarkup()}, model: {currentAgent.ModelDisplay.EscapeMarkup()}, key: {currentAgent.Key.EscapeMarkup()})[/]";

        AddSettingsRow(settingsTable, "Active Agent", activeAgentLabel);
        AddSettingsRow(settingsTable, "Executor Mode", $"[white]{GetJsonString(executor, "mode", "local").EscapeMarkup()}[/]");
        AddSettingsRow(settingsTable, "Max Iterations", $"[white]{GetJsonInt(executor, "max_iterations", 20)}[/]");
        AddSettingsRow(settingsTable, "Default Mode", $"[white]{GetJsonString(executor, "default_mode", "planning").EscapeMarkup()}[/]");
        AddSettingsRow(settingsTable, "Commit On Complete", FormatBoolSetting(GetJsonBool(executor, "commit_on_complete", true)));
        AddSettingsRow(settingsTable, "Sync", FormatBoolSetting(GetJsonBool(sync, "enabled", false)));
        AddSettingsRow(settingsTable, "Sync Provider", $"[white]{GetJsonString(sync, "provider", "http").EscapeMarkup()}[/]");
        AddSettingsRow(settingsTable, "Sync Base URL", $"[grey]{GetJsonString(sync, "base_url", "https://api.runfelix.io").EscapeMarkup()}[/]");
        AddSettingsRow(settingsTable, "Sync API Key", FormatApiKeyStatus(sync));
        AddSettingsRow(settingsTable, "Backpressure", FormatBoolSetting(GetJsonBool(backpressure, "enabled", false)));
        AddSettingsRow(settingsTable, "Backpressure Retries", $"[white]{GetJsonInt(backpressure, "max_retries", 3)}[/]");
        AddSettingsRow(settingsTable, "Backpressure Commands", FormatCommandsSummary(backpressure));
        AddSettingsRow(settingsTable, "Plugins", FormatBoolSetting(GetJsonBool(plugins, "enabled", false)));
        AddSettingsRow(settingsTable, "Disabled Plugins", FormatDisabledPluginsSummary(plugins));
        AddSettingsRow(settingsTable, "Plugin Discovery", $"[grey]{GetJsonString(plugins, "discovery_path", ".felix/plugins").EscapeMarkup()}[/]");
        AddSettingsRow(settingsTable, "Specs Path", $"[grey]{GetJsonString(paths, "specs", "specs").EscapeMarkup()}[/]");
        AddSettingsRow(settingsTable, "Runs Path", $"[grey]{GetJsonString(paths, "runs", "runs").EscapeMarkup()}[/]");
        AddSettingsRow(settingsTable, "Agents Guide", $"[grey]{GetJsonString(paths, "agents", "AGENTS.md").EscapeMarkup()}[/]");

        var requirementsConfigured = statusCounts.Keys.Count(status => statusCounts.GetValueOrDefault(status, 0) > 0);
        var activeAgentSummary = currentAgent == null
            ? "[grey]not set[/]"
            : $"[white]{currentAgent.Name.EscapeMarkup()}[/] [grey]({currentAgent.ModelDisplay.EscapeMarkup()})[/]";

        var overviewTable = new Table()
            .Border(TableBorder.None)
            .HideHeaders()
            .Expand()
            .AddColumn(new TableColumn(string.Empty).NoWrap().Width(22))
            .AddColumn(new TableColumn(string.Empty));

        overviewTable.AddRow("[grey]Project[/]", $"[white]{_felixProjectRoot.EscapeMarkup()}[/]");
        overviewTable.AddRow("[grey]Total Requirements[/]", $"[white]{total}[/]");
        overviewTable.AddRow("[grey]Statuses In Use[/]", $"[white]{requirementsConfigured}[/]");
        overviewTable.AddRow("[grey]Configured Agents[/]", $"[white]{configuredAgents.Count}[/]");
        overviewTable.AddRow("[grey]Active Agent[/]", activeAgentSummary);

        var summaryPanel = new Panel(overviewTable)
        {
            Header = new PanelHeader("Overview", Justify.Left),
            Border = BoxBorder.Rounded,
            BorderStyle = new Style(Color.Grey),
            Expand = true,
            Padding = new Padding(1, 0, 1, 0)
        };

        AnsiConsole.Write(summaryPanel);
        AnsiConsole.WriteLine();
        RenderRequirementDistribution(total, statusCounts);
        AnsiConsole.Write(statusTable);
        AnsiConsole.WriteLine();
        AnsiConsole.Write(settingsTable);
        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine($"[grey]Configured agents:[/] {configuredAgents.Count}");
        return Task.CompletedTask;
    }
}
