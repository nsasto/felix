using System.CommandLine;
using System.Diagnostics;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    static Command CreateAgentCommand(string felixPs1)
    {
        var cmd = new Command("agent", "Manage and switch agents");

        var listCmd = new Command("list", "List all available agents");
        listCmd.SetHandler(async () =>
        {
            ShowAgentListUI();
            await Task.CompletedTask;
        });

        var currentCmd = new Command("current", "Show current active agent");
        currentCmd.SetHandler(async () =>
        {
            ShowCurrentAgentUI();
            await Task.CompletedTask;
        });

        var targetArg = new Argument<string?>("target", "Agent ID or name")
        {
            Arity = ArgumentArity.ZeroOrOne
        };
        var useModelOpt = new Option<string?>("--model", "Model to use with the selected agent")
        {
            Arity = ArgumentArity.ZeroOrOne
        };
        var useCmd = new Command("use", "Switch to a different agent")
        {
            targetArg
        };
        useCmd.AddOption(useModelOpt);
        useCmd.SetHandler(async (target, model) =>
        {
            if (string.IsNullOrEmpty(target))
                await UseAgentInteractive("use");
            else
                await UseAgentSelectionUI(target, model, setDefault: false);
        }, targetArg, useModelOpt);

        var setDefaultTargetArg = new Argument<string?>("target", "Agent ID or name to set as default")
        {
            Arity = ArgumentArity.ZeroOrOne
        };
        var setDefaultModelOpt = new Option<string?>("--model", "Model to use with the selected default agent")
        {
            Arity = ArgumentArity.ZeroOrOne
        };
        var setDefaultCmd = new Command("set-default", "Set the persistent default agent")
        {
            setDefaultTargetArg
        };
        setDefaultCmd.AddOption(setDefaultModelOpt);
        setDefaultCmd.SetHandler(async (target, model) =>
        {
            if (string.IsNullOrEmpty(target))
                await UseAgentInteractive("set-default");
            else
                await UseAgentSelectionUI(target, model, setDefault: true);
        }, setDefaultTargetArg, setDefaultModelOpt);

        var testTargetArg = new Argument<string>("target", "Agent ID or name to test");
        var testCmd = new Command("test", "Test agent connectivity")
        {
            testTargetArg
        };
        testCmd.SetHandler(async (target) =>
        {
            await ShowAgentTestUI(target);
        }, testTargetArg);

        var setupCmd = new Command("setup", "Configure agents for this project");
        setupCmd.SetHandler(async () =>
        {
            await UseAgentSetupInteractive(felixPs1);
        });

        var installHelpTargetArg = new Argument<string?>("target", "Agent name to show install guidance for")
        {
            Arity = ArgumentArity.ZeroOrOne
        };
        var installHelpCmd = new Command("install-help", "Show install/login guidance for one or all agents")
        {
            installHelpTargetArg
        };
        installHelpCmd.SetHandler(async (target) =>
        {
            ShowAgentInstallHelpUI(target);
            await Task.CompletedTask;
        }, installHelpTargetArg);

        var registerCmd = new Command("register", "Register the current agent with the sync server");
        registerCmd.SetHandler(async () =>
        {
            await RegisterCurrentAgentUI();
        });

        cmd.AddCommand(listCmd);
        cmd.AddCommand(currentCmd);
        cmd.AddCommand(useCmd);
        cmd.AddCommand(setDefaultCmd);
        cmd.AddCommand(testCmd);
        cmd.AddCommand(setupCmd);
        cmd.AddCommand(installHelpCmd);
        cmd.AddCommand(registerCmd);

        return cmd;
    }

    static async Task UseAgentInteractive(string subCommand = "use")
    {
        var agents = ReadConfiguredAgents();
        if (agents == null || agents.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No configured agents found. Run `felix agent setup` first.[/]");
            return;
        }

        AnsiConsole.Clear();
        var title = string.Equals(subCommand, "set-default", StringComparison.OrdinalIgnoreCase)
            ? "[cyan]Set Default Agent[/]"
            : "[cyan]Select Active Agent[/]";
        var rule = new Rule(title).RuleStyle(Style.Parse("cyan dim"));
        AnsiConsole.Write(rule);
        AnsiConsole.WriteLine();

        var selected = AnsiConsole.Prompt(
            new SelectionPrompt<ConfiguredAgent>()
                .Title(string.Equals(subCommand, "set-default", StringComparison.OrdinalIgnoreCase)
                    ? "[cyan]Choose the default agent Felix should use:[/]"
                    : "[cyan]Choose the agent Felix should use:[/]")
                .PageSize(10)
                .EnableSearch()
                .SearchPlaceholderText("[grey](type to filter agents or models)[/]")
                .UseConverter(agent => agent.Key == "__back__"
                    ? "< Back>"
                    : agent.IsCurrent
                        ? $"[green]*[/] {agent.Name.EscapeMarkup()} [grey](model: {agent.ModelDisplay.EscapeMarkup()}, key: {agent.Key.EscapeMarkup()})[/]"
                        : $"{agent.Name.EscapeMarkup()} [grey](model: {agent.ModelDisplay.EscapeMarkup()}, key: {agent.Key.EscapeMarkup()})[/]")
                .AddChoices(new[] { ConfiguredAgent.Back }.Concat(agents)));

        if (selected.Key == ConfiguredAgent.Back.Key)
            return;

        var selectedModel = await PromptAgentModel(selected);

        AnsiConsole.Clear();
        var requestedModel = string.Equals(selectedModel, selected.ModelDisplay, StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(selectedModel)
            ? null
            : selectedModel;
        await UseAgentSelectionUI(selected.Key, requestedModel, string.Equals(subCommand, "set-default", StringComparison.OrdinalIgnoreCase));
    }

    static Task UseAgentSetupInteractive(string felixPs1)
    {
        var felixDir = Path.Combine(_felixProjectRoot, ".felix");
        if (!Directory.Exists(felixDir))
        {
            AnsiConsole.MarkupLine("[yellow]No .felix directory found in the current project. Run 'felix setup' first.[/]");
            return Task.CompletedTask;
        }

        var templates = ReadAgentTemplates();
        if (templates == null || templates.Count == 0)
        {
            AnsiConsole.MarkupLine("[red]No agent templates were found. Reinstall Felix or verify the installation files.[/]");
            return Task.CompletedTask;
        }

        var existingProfiles = ReadAgentProfiles();
        var existingByName = existingProfiles.Agents
            .Where(profile => !string.IsNullOrWhiteSpace(profile.Name))
            .GroupBy(profile => profile.Name!, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);

        var choices = templates
            .Select(template =>
            {
                existingByName.TryGetValue(template.Name, out var existingProfile);
                var installed = TestExecutableInstalled(ResolveExecutableName(template));
                var currentModel = existingProfile?.Model;
                if (string.IsNullOrWhiteSpace(currentModel))
                    currentModel = template.Model;
                if (string.IsNullOrWhiteSpace(currentModel))
                    currentModel = GetAgentDefaults(template.Adapter).Model;

                return new AgentSetupChoice(template, installed, existingProfile != null, currentModel ?? "default");
            })
            .OrderByDescending(choice => choice.IsConfigured)
            .ThenByDescending(choice => choice.Installed)
            .ThenBy(choice => choice.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();

        AnsiConsole.Clear();
        var rule = new Rule("[cyan]Configure Agent Profiles[/]").RuleStyle(Style.Parse("cyan dim"));
        AnsiConsole.Write(rule);
        AnsiConsole.WriteLine();

        var table = new Table().Border(TableBorder.Rounded).BorderColor(Color.Grey);
        table.AddColumn("Agent");
        table.AddColumn("Status");
        table.AddColumn("Current");

        foreach (var choice in choices)
        {
            var currentLabel = choice.IsConfigured
                ? $"[grey]{choice.ModelDisplay.EscapeMarkup()}[/]"
                : "[grey]not configured[/]";
            var statusLabel = choice.Installed ? "[green]installed[/]" : "[yellow]install needed[/]";
            table.AddRow(choice.Name.EscapeMarkup(), statusLabel, currentLabel);
        }

        AnsiConsole.Write(table);
        AnsiConsole.WriteLine();

        var selectableChoices = choices.Where(choice => choice.Installed).ToList();
        if (selectableChoices.Count == 0)
        {
            RenderAgentInstallGuidance(choices.Where(choice => !choice.Installed).Select(choice => choice.Template));
            return Task.CompletedTask;
        }

        var prompt = new MultiSelectionPrompt<AgentSetupChoice>()
            .Title("[cyan]Select the agent profiles to create or update:[/]")
            .NotRequired()
            .InstructionsText("[grey](Space to toggle, Enter to confirm)[/]")
            .PageSize(10)
            .UseConverter(choice =>
            {
                var configuredTag = choice.IsConfigured ? " [green](configured)[/]" : "";
                return $"{choice.Name.EscapeMarkup()} [grey](model: {choice.ModelDisplay.EscapeMarkup()})[/]{configuredTag}";
            });

        prompt.AddChoices(selectableChoices);
        foreach (var choice in selectableChoices.Where(choice => choice.IsConfigured))
            prompt.Select(choice);

        var selectedChoices = AnsiConsole.Prompt(prompt);
        if (selectedChoices.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No agent profiles were selected. Nothing changed.[/]");
            return Task.CompletedTask;
        }

        var selectedProfiles = new List<AgentProfileDocument>();
        var summaryRows = new List<(string Name, string Model, string Key)>();
        foreach (var choice in selectedChoices.OrderBy(choice => choice.Name, StringComparer.OrdinalIgnoreCase))
        {
            var selectedModel = PromptAgentSetupModel(choice);
            var profile = BuildConfiguredAgentProfile(choice.Template, selectedModel);
            selectedProfiles.Add(profile);
            summaryRows.Add((choice.Name, profile.Model ?? "default", profile.Key ?? ""));
        }

        var updatedProfiles = UpsertAgentProfiles(existingProfiles.Agents, selectedProfiles);
        WriteAgentProfiles(updatedProfiles);

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Agent Profiles Saved[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var summaryTable = new Table().Border(TableBorder.Rounded).BorderColor(Color.Green3);
        summaryTable.AddColumn("Agent");
        summaryTable.AddColumn("Model");
        summaryTable.AddColumn("Key");
        foreach (var row in summaryRows)
            summaryTable.AddRow(row.Name.EscapeMarkup(), row.Model.EscapeMarkup(), row.Key.EscapeMarkup());

        AnsiConsole.Write(summaryTable);
        AnsiConsole.WriteLine();

        var skipped = choices.Where(choice => !choice.Installed).Select(choice => choice.Template).ToList();
        if (skipped.Count > 0)
            AnsiConsole.MarkupLine("[grey]Some providers remain uninstalled. Use 'felix agent install-help <name>' for setup guidance if needed.[/]");

        AnsiConsole.MarkupLine("[green]Saved profiles to .felix/agents.json[/]");
        return Task.CompletedTask;
    }

    static async Task RunSetupInteractive(string felixPs1)
    {
        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Felix Setup[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var selectedProjectRoot = PromptSetupProjectRoot();
        _felixProjectRoot = selectedProjectRoot;

        var scaffoldResult = EnsureFelixProjectScaffold(selectedProjectRoot);
        RenderScaffoldSummary(scaffoldResult);

        var configPath = Path.Combine(selectedProjectRoot, ".felix", "config.json");
        var config = LoadSetupConfig(configPath);
        EnsureSetupConfigDefaults(config);

        await EnsureAgentsGuideAsync(selectedProjectRoot);

        if (AnsiConsole.Confirm("Configure or update agent profiles in [cyan].felix/agents.json[/]?", true))
            await UseAgentSetupInteractive(felixPs1);

        RenderDetectedDependencies(selectedProjectRoot);
        SelectActiveAgent(config);
        ConfigureBackpressureCommand(config);
        await ConfigureSyncModeAsync(config);

        SaveSetupConfig(configPath, config);

        if (IsSyncEnabled(config) && AnsiConsole.Confirm("Pull specs from the backend now?", false))
        {
            await ExecutePowerShell(felixPs1, "spec", "pull");
            if (Environment.ExitCode == 0)
                await ExecutePowerShell(felixPs1, "spec", "fix");
        }

        AnsiConsole.WriteLine();
        AnsiConsole.Write(new Rule("[green]Setup Complete[/]").RuleStyle(Style.Parse("green dim")));
        AnsiConsole.WriteLine();
        if (IsSyncEnabled(config))
            AnsiConsole.MarkupLine("[green]Sync enabled.[/] Runs and specs will use the configured backend.");
        else
            AnsiConsole.MarkupLine("[yellow]Sync disabled.[/] Runs will stay local until you re-run setup or use --sync.");
    }

    static Task<string?> PromptAgentModel(ConfiguredAgent agent)
    {
        var availableModels = ReadAgentModels(agent.Provider);
        if (availableModels == null || availableModels.Count <= 1)
            return Task.FromResult<string?>(agent.ModelDisplay);

        var choices = new List<string>();
        if (!string.IsNullOrWhiteSpace(agent.ModelDisplay) && !string.Equals(agent.ModelDisplay, "default", StringComparison.OrdinalIgnoreCase))
            choices.Add(agent.ModelDisplay);
        choices.AddRange(availableModels.Where(model => !choices.Contains(model, StringComparer.OrdinalIgnoreCase)));

        var selectedModel = AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .Title($"[cyan]Select model for {agent.Name.EscapeMarkup()}[/] [grey](Enter keeps {agent.ModelDisplay.EscapeMarkup()})[/]")
                .PageSize(12)
                .EnableSearch()
                .SearchPlaceholderText("[grey](type to filter models)[/]")
                .AddChoices(choices));

        return Task.FromResult<string?>(selectedModel);
    }

    sealed record ConfiguredAgent(string Key, string Name, string Provider, string ModelDisplay, bool IsCurrent)
    {
        internal static readonly ConfiguredAgent Back = new("__back__", "< Back>", "", "", false);
    }

    sealed record ConfiguredAgentDetails(string Key, string Name, string Provider, string Adapter, string ModelDisplay, bool IsCurrent, string Executable);

    internal sealed record AgentTemplateEntry(string Name, string Provider, string Adapter, string? Model, string? Executable);

    internal sealed record AgentSetupChoice(AgentTemplateEntry Template, bool Installed, bool IsConfigured, string ModelDisplay)
    {
        public string Name => Template.Name;
    }

    internal sealed class AgentProfilesDocument
    {
        [JsonPropertyName("agents")]
        public List<AgentProfileDocument> Agents { get; set; } = new();
    }

    internal sealed record ScaffoldResult(bool IsNewProject, List<string> Created, List<string> Skipped, string FelixRoot);

    internal sealed class AgentProfileDocument
    {
        [JsonPropertyName("name")]
        public string? Name { get; set; }

        [JsonPropertyName("provider")]
        public string? Provider { get; set; }

        [JsonPropertyName("adapter")]
        public string? Adapter { get; set; }

        [JsonPropertyName("model")]
        public string? Model { get; set; }

        [JsonPropertyName("key")]
        public string? Key { get; set; }

        [JsonPropertyName("id")]
        public string? Id { get; set; }
    }

    internal sealed record AgentDefaults(string Adapter, string Executable, string Model, string WorkingDirectory, IReadOnlyDictionary<string, object?> AdditionalKeySettings);

    static string PromptAgentSetupModel(AgentSetupChoice choice)
    {
        var provider = string.IsNullOrWhiteSpace(choice.Template.Provider) ? choice.Template.Adapter : choice.Template.Provider;
        var availableModels = ReadAgentModels(provider);
        var selectedModel = choice.ModelDisplay;
        if (availableModels == null || availableModels.Count <= 1)
            return selectedModel;

        var modelChoices = new List<string>();
        if (!string.IsNullOrWhiteSpace(selectedModel) && !string.Equals(selectedModel, "default", StringComparison.OrdinalIgnoreCase))
            modelChoices.Add(selectedModel);
        modelChoices.AddRange(availableModels.Where(model => !modelChoices.Contains(model, StringComparer.OrdinalIgnoreCase)));

        return AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .Title($"[cyan]Select model for {choice.Name.EscapeMarkup()}[/] [grey](Enter keeps {selectedModel.EscapeMarkup()})[/]")
                .PageSize(12)
                .EnableSearch()
                .SearchPlaceholderText("[grey](type to filter models)[/]")
                .AddChoices(modelChoices));
    }

    static void RenderAgentInstallGuidance(IEnumerable<AgentTemplateEntry> templates)
    {
        foreach (var template in templates.OrderBy(template => template.Name, StringComparer.OrdinalIgnoreCase))
        {
            var panelBody = string.Join(Environment.NewLine, GetAgentInstallGuidance(template.Name));
            var panel = new Panel($"[grey]{panelBody.EscapeMarkup()}[/]")
            {
                Header = new PanelHeader($"[yellow]{template.Name.EscapeMarkup()}[/]"),
                Border = BoxBorder.Rounded
            };
            AnsiConsole.Write(panel);
            AnsiConsole.WriteLine();
        }
    }

    static List<AgentTemplateEntry>? ReadAgentTemplates()
    {
        var candidatePaths = new[]
        {
            Path.Combine(_felixProjectRoot, ".felix", "agent-templates.json"),
            Path.Combine(_felixInstallDir, "agent-templates.json"),
            Path.Combine(_felixInstallDir, ".felix", "agent-templates.json")
        };

        var templatePath = candidatePaths.FirstOrDefault(File.Exists);
        if (templatePath == null)
            return null;

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(templatePath));
            if (!doc.RootElement.TryGetProperty("agents", out var agentsElement) || agentsElement.ValueKind != JsonValueKind.Array)
                return null;

            return agentsElement.EnumerateArray()
                .Select(agent => new AgentTemplateEntry(
                    agent.TryGetProperty("name", out var nameProp) ? nameProp.GetString() ?? "" : "",
                    agent.TryGetProperty("provider", out var providerProp) ? providerProp.GetString() ?? "" : "",
                    agent.TryGetProperty("adapter", out var adapterProp) ? adapterProp.GetString() ?? "" : "",
                    agent.TryGetProperty("model", out var modelProp) ? modelProp.GetString() : null,
                    agent.TryGetProperty("executable", out var executableProp) ? executableProp.GetString() : null))
                .Where(agent => !string.IsNullOrWhiteSpace(agent.Name))
                .ToList();
        }
        catch
        {
            return null;
        }
    }

    static AgentProfilesDocument ReadAgentProfiles()
    {
        var agentsPath = Path.Combine(_felixProjectRoot, ".felix", "agents.json");
        if (!File.Exists(agentsPath))
            return new AgentProfilesDocument();

        try
        {
            return JsonSerializer.Deserialize<AgentProfilesDocument>(File.ReadAllText(agentsPath)) ?? new AgentProfilesDocument();
        }
        catch
        {
            return new AgentProfilesDocument();
        }
    }

    static void WriteAgentProfiles(IEnumerable<AgentProfileDocument> agents)
    {
        var agentsPath = Path.Combine(_felixProjectRoot, ".felix", "agents.json");
        var payload = new AgentProfilesDocument { Agents = agents.ToList() };
        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(agentsPath, json + Environment.NewLine);
    }

    static JsonObject LoadAgentProfilesJson()
    {
        var agentsPath = Path.Combine(_felixProjectRoot, ".felix", "agents.json");
        if (!File.Exists(agentsPath))
            return new JsonObject { ["agents"] = new JsonArray() };

        try
        {
            return JsonNode.Parse(File.ReadAllText(agentsPath))?.AsObject() ?? new JsonObject { ["agents"] = new JsonArray() };
        }
        catch
        {
            return new JsonObject { ["agents"] = new JsonArray() };
        }
    }

    static JsonArray EnsureAgentProfilesArray(JsonObject document)
    {
        if (document["agents"] is JsonArray agents)
            return agents;

        var created = new JsonArray();
        document["agents"] = created;
        return created;
    }

    static void SaveAgentProfilesJson(JsonObject document)
    {
        var agentsPath = Path.Combine(_felixProjectRoot, ".felix", "agents.json");
        File.WriteAllText(agentsPath, document.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine);
    }

    internal static List<AgentProfileDocument> UpsertAgentProfiles(IEnumerable<AgentProfileDocument> existingAgents, IEnumerable<AgentProfileDocument> selectedAgents)
    {
        var merged = existingAgents.ToList();
        foreach (var selected in selectedAgents)
        {
            if (string.IsNullOrWhiteSpace(selected.Name))
                continue;

            var existingIndex = merged.FindIndex(agent => string.Equals(agent.Name, selected.Name, StringComparison.OrdinalIgnoreCase));
            if (existingIndex >= 0)
                merged[existingIndex] = selected;
            else
                merged.Add(selected);
        }

        return merged;
    }

    static AgentProfileDocument BuildConfiguredAgentProfile(AgentTemplateEntry template, string selectedModel)
    {
        var provider = string.IsNullOrWhiteSpace(template.Provider) ? template.Adapter : template.Provider;
        var defaults = GetAgentDefaults(template.Adapter);
        var key = NewAgentKey(provider, selectedModel, BuildAgentKeySettings(defaults), _felixProjectRoot);

        return new AgentProfileDocument
        {
            Name = template.Name,
            Provider = provider,
            Adapter = template.Adapter,
            Model = selectedModel,
            Key = key,
            Id = key
        };
    }

    static Dictionary<string, object?> BuildAgentKeySettings(AgentDefaults defaults)
    {
        var settings = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["executable"] = defaults.Executable,
            ["working_directory"] = defaults.WorkingDirectory,
            ["environment"] = new Dictionary<string, object?>(StringComparer.Ordinal)
        };

        foreach (var pair in defaults.AdditionalKeySettings)
            settings[pair.Key] = pair.Value;

        return settings;
    }

    static Dictionary<string, object?> BuildAgentKeySettings(JsonObject agentNode, AgentDefaults defaults)
    {
        var settings = new Dictionary<string, object?>(StringComparer.Ordinal);

        var executable = GetOptionalJsonString(agentNode, "executable");
        if (string.IsNullOrWhiteSpace(executable))
            executable = defaults.Executable;
        if (!string.IsNullOrWhiteSpace(executable))
            settings["executable"] = executable;

        var workingDirectory = GetOptionalJsonString(agentNode, "working_directory");
        if (string.IsNullOrWhiteSpace(workingDirectory))
            workingDirectory = defaults.WorkingDirectory;
        if (!string.IsNullOrWhiteSpace(workingDirectory))
            settings["working_directory"] = workingDirectory;

        settings["environment"] = ConvertJsonNodeToObject(agentNode["environment"]) ?? new Dictionary<string, object?>(StringComparer.Ordinal);

        foreach (var pair in defaults.AdditionalKeySettings)
        {
            var value = agentNode.ContainsKey(pair.Key) ? ConvertJsonNodeToObject(agentNode[pair.Key]) : pair.Value;
            if (value is string stringValue && string.IsNullOrWhiteSpace(stringValue))
                continue;
            if (value != null)
                settings[pair.Key] = value;
        }

        return settings;
    }

    internal static AgentDefaults GetAgentDefaults(string adapterType)
    {
        return adapterType.ToLowerInvariant() switch
        {
            "droid" => new AgentDefaults("droid", "droid", "claude-opus-4-5-20251101", ".", new Dictionary<string, object?>()),
            "claude" => new AgentDefaults("claude", "claude", "sonnet", ".", new Dictionary<string, object?>()),
            "codex" => new AgentDefaults("codex", "codex", "gpt-5.2-codex", ".", new Dictionary<string, object?>()),
            "gemini" => new AgentDefaults("gemini", "gemini", "auto", ".", new Dictionary<string, object?>()),
            "copilot" => new AgentDefaults(
                "copilot",
                "copilot",
                "auto",
                ".",
                new Dictionary<string, object?>
                {
                    ["allow_all"] = true,
                    ["custom_agent"] = "",
                    ["max_autopilot_continues"] = 10,
                    ["no_ask_user"] = true
                }),
            _ => new AgentDefaults(adapterType, adapterType, "", ".", new Dictionary<string, object?>())
        };
    }

    static string ResolveExecutableName(AgentTemplateEntry template)
    {
        if (!string.IsNullOrWhiteSpace(template.Executable))
            return template.Executable;

        return GetAgentDefaults(template.Adapter).Executable;
    }

    internal static bool TestExecutableInstalled(string executableName)
    {
        if (string.IsNullOrWhiteSpace(executableName))
            return false;

        if (FindExecutableOnPath(executableName) != null)
            return true;

        if (string.Equals(executableName, "copilot", StringComparison.OrdinalIgnoreCase))
            return GetCopilotExecutableCandidates().Any(File.Exists);

        return false;
    }

    static string? FindExecutableOnPath(string executableName)
    {
        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
            return null;

        var candidateNames = GetExecutableCandidates(executableName);
        foreach (var path in pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            foreach (var candidate in candidateNames)
            {
                var fullPath = Path.Combine(path, candidate);
                if (File.Exists(fullPath))
                    return fullPath;
            }
        }

        return null;
    }

    static IEnumerable<string> GetExecutableCandidates(string executableName)
    {
        if (!OperatingSystem.IsWindows())
            return new[] { executableName };

        if (!string.IsNullOrWhiteSpace(Path.GetExtension(executableName)))
            return new[] { executableName };

        return new[] { executableName + ".exe", executableName + ".cmd", executableName + ".bat", executableName + ".ps1", executableName };
    }

    internal static IReadOnlyList<string> GetCopilotExecutableCandidates(string? appDataOverride = null, string? rootsOverride = null)
    {
        var candidates = new List<string>();
        var candidateDirs = new List<string>();

        var roots = rootsOverride ?? Environment.GetEnvironmentVariable("FELIX_COPILOT_CLI_ROOTS");
        if (!string.IsNullOrWhiteSpace(roots))
            candidateDirs.AddRange(roots.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));

        var appData = appDataOverride ?? Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (!string.IsNullOrWhiteSpace(appData))
        {
            var globalStorage = Path.Combine(appData, "Code", "User", "globalStorage");
            if (Directory.Exists(globalStorage))
            {
                candidateDirs.AddRange(Directory.EnumerateDirectories(globalStorage, "github.copilot*")
                    .Select(path => Path.Combine(path, "copilotCli")));
            }

            candidateDirs.Add(Path.Combine(appData, ".vscode-copilot"));
            candidateDirs.Add(Path.Combine(appData, ".vscode-copilot", "bin"));
        }

        foreach (var dir in candidateDirs.Where(path => !string.IsNullOrWhiteSpace(path)).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            // Prefer .ps1 so we invoke via 'pwsh -File copilot.ps1' which correctly
            // populates $MyInvocation.MyCommand.Path inside the Copilot shim.
            // .bat/.cmd shims use 'powershell -Command' which leaves that variable empty.
            candidates.Add(Path.Combine(dir, "copilot.ps1"));
            candidates.Add(Path.Combine(dir, "copilot.exe"));
            candidates.Add(Path.Combine(dir, "copilot.cmd"));
            candidates.Add(Path.Combine(dir, "copilot.bat"));
        }

        return candidates.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    static IEnumerable<string> GetAgentInstallGuidance(string agentName)
    {
        return agentName.ToLowerInvariant() switch
        {
            "droid" => new[]
            {
                "Install with: npm install -g @factory-ai/droid-cli",
                "Then verify with: droid --version"
            },
            "claude" => new[]
            {
                "Install with: npm install -g @anthropic-ai/claude-code",
                "Then run: claude auth login"
            },
            "codex" => new[]
            {
                "Install with: npm install -g @openai/codex-cli",
                "Then run: codex auth"
            },
            "gemini" => new[]
            {
                "Install with: pip install google-gemini-cli",
                "Then run: gemini auth login"
            },
            "copilot" => new[]
            {
                "Install the GitHub Copilot Chat extension in VS Code and allow it to install the Copilot CLI when prompted.",
                "Or run 'copilot' once in a terminal to trigger the CLI install flow.",
                "Then run: copilot login"
            },
            _ => new[] { "Install via your package manager and ensure the executable is on PATH." }
        };
    }

    internal static string NewAgentKey(string provider, string model, IReadOnlyDictionary<string, object?>? agentSettings, string? projectRoot, string? machineNameOverride = null, string? gitRemoteOverride = null)
    {
        var machineId = (machineNameOverride ?? Environment.MachineName ?? "unknown").ToLowerInvariant();
        var projectId = ResolveProjectIdentity(projectRoot, gitRemoteOverride);
        var settingsString = string.Empty;
        if (agentSettings != null && agentSettings.Count > 0)
        {
            var normalizedSettings = NormalizeForHash(agentSettings);
            settingsString = JsonSerializer.Serialize(normalizedSettings).Replace(" ", string.Empty, StringComparison.Ordinal);
        }

        var hashInput = string.Join("::", new[]
        {
            provider.ToLowerInvariant(),
            model.ToLowerInvariant(),
            settingsString,
            machineId,
            projectId
        });

        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(hashInput));
        return $"ag_{Convert.ToHexString(hash).ToLowerInvariant()[..9]}";
    }

    static string ResolveProjectIdentity(string? projectRoot, string? gitRemoteOverride)
    {
        var basePath = string.IsNullOrWhiteSpace(projectRoot) ? Directory.GetCurrentDirectory() : projectRoot;
        var gitRemote = string.IsNullOrWhiteSpace(gitRemoteOverride) ? TryReadGitRemoteOrigin(basePath) : gitRemoteOverride;
        if (!string.IsNullOrWhiteSpace(gitRemote))
            return NormalizeGitRemote(gitRemote);

        return NormalizeProjectPath(basePath);
    }

    static string? TryReadGitRemoteOrigin(string projectRoot)
    {
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = $"-C \"{projectRoot}\" config --get remote.origin.url",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            using var process = Process.Start(startInfo);
            if (process == null)
                return null;

            var output = process.StandardOutput.ReadToEnd().Trim();
            process.WaitForExit();
            return process.ExitCode == 0 && !string.IsNullOrWhiteSpace(output) ? output : null;
        }
        catch
        {
            return null;
        }
    }

    static string NormalizeGitRemote(string gitRemote)
    {
        var normalized = gitRemote.Trim().ToLowerInvariant();
        if (normalized.EndsWith(".git", StringComparison.Ordinal))
            normalized = normalized[..^4];

        if (normalized.StartsWith("git@", StringComparison.Ordinal))
        {
            var separatorIndex = normalized.IndexOf(':');
            if (separatorIndex > 4)
            {
                var host = normalized[4..separatorIndex];
                var path = normalized[(separatorIndex + 1)..];
                normalized = $"https://{host}/{path}";
            }
        }

        return normalized;
    }

    static string NormalizeProjectPath(string path)
        => path.Trim().TrimEnd('\\', '/').ToLowerInvariant();

    static object? NormalizeForHash(object? value)
    {
        if (value == null)
            return null;

        if (value is JsonElement jsonElement)
            return NormalizeJsonElement(jsonElement);

        if (value is IReadOnlyDictionary<string, object?> readOnlyDictionary)
        {
            var sorted = new SortedDictionary<string, object?>(StringComparer.Ordinal);
            foreach (var pair in readOnlyDictionary)
                sorted[pair.Key] = NormalizeForHash(pair.Value);
            return sorted;
        }

        if (value is IDictionary<string, object?> dictionary)
        {
            var sorted = new SortedDictionary<string, object?>(StringComparer.Ordinal);
            foreach (var pair in dictionary)
                sorted[pair.Key] = NormalizeForHash(pair.Value);
            return sorted;
        }

        if (value is System.Collections.IDictionary nonGenericDictionary)
        {
            var sorted = new SortedDictionary<string, object?>(StringComparer.Ordinal);
            foreach (System.Collections.DictionaryEntry entry in nonGenericDictionary)
                sorted[Convert.ToString(entry.Key) ?? string.Empty] = NormalizeForHash(entry.Value);
            return sorted;
        }

        if (value is System.Collections.IEnumerable enumerable && value is not string)
        {
            var items = new List<object?>();
            foreach (var item in enumerable)
                items.Add(NormalizeForHash(item));
            return items;
        }

        return value;
    }

    static object? NormalizeJsonElement(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.Object => element.EnumerateObject()
                .OrderBy(property => property.Name, StringComparer.Ordinal)
                .ToDictionary(property => property.Name, property => NormalizeJsonElement(property.Value), StringComparer.Ordinal),
            JsonValueKind.Array => element.EnumerateArray().Select(NormalizeJsonElement).ToList(),
            JsonValueKind.String => element.GetString(),
            JsonValueKind.Number => element.GetRawText(),
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => null
        };
    }

    static string PromptSetupProjectRoot()
    {
        var defaultRoot = _felixProjectRoot;
        var input = AnsiConsole.Prompt(
            new TextPrompt<string>($"[cyan]Project directory[/] [grey](Enter keeps {defaultRoot.EscapeMarkup()})[/]")
                .AllowEmpty());

        if (string.IsNullOrWhiteSpace(input))
            return defaultRoot;

        try
        {
            var fullPath = Path.GetFullPath(input.Trim());
            if (Directory.Exists(fullPath))
                return fullPath;
        }
        catch
        {
        }

        AnsiConsole.MarkupLine($"[yellow]Path not found.[/] Using [grey]{defaultRoot.EscapeMarkup()}[/].");
        return defaultRoot;
    }

    internal static ScaffoldResult EnsureFelixProjectScaffold(string projectRoot, string? installRootOverride = null)
    {
        var installRoot = installRootOverride ?? _felixInstallDir;
        var felixDir = Path.Combine(projectRoot, ".felix");
        var created = new List<string>();
        var skipped = new List<string>();
        var isNewProject = !Directory.Exists(felixDir);

        if (isNewProject)
            Directory.CreateDirectory(felixDir);

        WriteIfMissing(Path.Combine(felixDir, "requirements.json"), "{ \"requirements\": [] }" + Environment.NewLine, "requirements.json", created, skipped);
        WriteIfMissing(Path.Combine(felixDir, "state.json"), "{}" + Environment.NewLine, "state.json", created, skipped);

        var configPath = Path.Combine(felixDir, "config.json");
        if (!File.Exists(configPath))
        {
            var configTemplatePath = Path.Combine(installRoot, "config.json.example");
            if (File.Exists(configTemplatePath))
            {
                File.Copy(configTemplatePath, configPath);
                created.Add("config.json (from engine template)");
            }
            else
            {
                File.WriteAllText(configPath, BuildDefaultSetupConfigJson());
                created.Add("config.json");
            }
        }
        else
        {
            skipped.Add("config.json");
        }

        CopyIfMissing(Path.Combine(installRoot, "config.json.example"), Path.Combine(felixDir, "config.json.example"), "config.json.example (template)", created, skipped);
        CopyIfMissing(Path.Combine(installRoot, "policies", "allowlist.json"), Path.Combine(felixDir, "policies", "allowlist.json"), "policies/allowlist.json", created, skipped);
        CopyIfMissing(Path.Combine(installRoot, "policies", "denylist.json"), Path.Combine(felixDir, "policies", "denylist.json"), "policies/denylist.json", created, skipped);

        EnsureDirectory(Path.Combine(projectRoot, "specs"), "specs/", created, skipped);
        EnsureDirectory(Path.Combine(projectRoot, "runs"), "runs/", created, skipped);
        EnsureGitIgnore(projectRoot, created, skipped);

        return new ScaffoldResult(isNewProject, created, skipped, installRoot);
    }

    static void RenderScaffoldSummary(ScaffoldResult scaffold)
    {
        var title = scaffold.IsNewProject ? "Initialized new Felix project" : "Project files";
        var table = new Table().Border(TableBorder.Rounded).BorderColor(Color.Grey);
        table.Title = new TableTitle($"[cyan]{title.EscapeMarkup()}[/]");
        table.AddColumn("Status");
        table.AddColumn("Path");

        foreach (var item in scaffold.Created)
            table.AddRow("[green]+ created[/]", item.EscapeMarkup());
        foreach (var item in scaffold.Skipped)
            table.AddRow("[grey]- kept[/]", item.EscapeMarkup());

        AnsiConsole.Write(table);
        AnsiConsole.MarkupLine($"[grey]Engine:[/] {scaffold.FelixRoot.EscapeMarkup()}");
        AnsiConsole.WriteLine();
    }

    static JsonObject LoadSetupConfig(string configPath)
    {
        if (!File.Exists(configPath))
            return JsonNode.Parse(BuildDefaultSetupConfigJson())?.AsObject() ?? new JsonObject();

        try
        {
            return JsonNode.Parse(File.ReadAllText(configPath))?.AsObject() ?? new JsonObject();
        }
        catch
        {
            AnsiConsole.MarkupLine("[yellow]Existing config.json could not be parsed. Rebuilding with defaults.[/]");
            return JsonNode.Parse(BuildDefaultSetupConfigJson())?.AsObject() ?? new JsonObject();
        }
    }

    static string BuildDefaultSetupConfigJson()
    {
        var config = new JsonObject
        {
            ["agent"] = new JsonObject { ["agent_id"] = null },
            ["sync"] = new JsonObject
            {
                ["enabled"] = false,
                ["provider"] = "http",
                ["base_url"] = "https://api.runfelix.io",
                ["api_key"] = null
            }
        };
        return config.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine;
    }

    internal static void EnsureSetupConfigDefaults(JsonObject config)
    {
        var agent = EnsureObject(config, "agent");
        if (!agent.ContainsKey("agent_id"))
            agent["agent_id"] = null;

        var sync = EnsureObject(config, "sync");
        if (!sync.ContainsKey("enabled")) sync["enabled"] = false;
        if (!sync.ContainsKey("provider")) sync["provider"] = "http";
        if (!sync.ContainsKey("base_url") || string.IsNullOrWhiteSpace(sync["base_url"]?.GetValue<string>())) sync["base_url"] = "https://api.runfelix.io";
        if (!sync.ContainsKey("api_key")) sync["api_key"] = null;

        var backpressure = EnsureObject(config, "backpressure");
        if (!backpressure.ContainsKey("enabled")) backpressure["enabled"] = false;
        if (!backpressure.ContainsKey("commands")) backpressure["commands"] = new JsonArray();
        if (!backpressure.ContainsKey("max_retries")) backpressure["max_retries"] = 3;

        var executor = EnsureObject(config, "executor");
        if (!executor.ContainsKey("max_iterations")) executor["max_iterations"] = 20;
        if (!executor.ContainsKey("default_mode")) executor["default_mode"] = "planning";
        if (!executor.ContainsKey("commit_on_complete")) executor["commit_on_complete"] = true;
    }

    static async Task EnsureAgentsGuideAsync(string projectRoot)
    {
        var agentsPath = Path.Combine(projectRoot, "AGENTS.md");
        if (File.Exists(agentsPath))
        {
            AnsiConsole.MarkupLine("[green]AGENTS.md found.[/] Project guidance is already present.");
            AnsiConsole.WriteLine();
            return;
        }

        var panel = new Panel("Felix works better when AGENTS.md explains how to install dependencies, run tests, build, and start the project.")
        {
            Header = new PanelHeader("[yellow]AGENTS.md missing[/]"),
            Border = BoxBorder.Rounded
        };
        AnsiConsole.Write(panel);

        if (AnsiConsole.Confirm("Create a starter AGENTS.md now?", true))
        {
            var content = "# Agents - How to Operate This Repository\n\n## Install Dependencies\n\n<!-- Describe how to install project dependencies -->\n\n## Run Tests\n\n<!-- Describe how to run the test suite -->\n\n## Build the Project\n\n<!-- Describe how to build the project -->\n\n## Start the Application\n\n<!-- Describe how to start the application -->\n";
            File.WriteAllText(agentsPath, content);
            AnsiConsole.MarkupLine("[green]Created AGENTS.md[/]");
        }
        else
        {
            AnsiConsole.MarkupLine("[yellow]Skipped AGENTS.md creation.[/] Agents will have less project context until you add it.");
        }

        AnsiConsole.WriteLine();
        await Task.CompletedTask;
    }

    static void RenderDetectedDependencies(string projectRoot)
    {
        var checks = new[]
        {
            (File: "requirements.txt", Label: "Python (requirements.txt)"),
            (File: "pyproject.toml", Label: "Python (pyproject.toml)"),
            (File: "package.json", Label: "Node.js (package.json)"),
            (File: "go.mod", Label: "Go (go.mod)"),
            (File: "Cargo.toml", Label: "Rust (Cargo.toml)"),
            (File: "Gemfile", Label: "Ruby (Gemfile)"),
            (File: "pom.xml", Label: "Java/Maven (pom.xml)"),
            (File: "build.gradle", Label: "Java/Gradle (build.gradle)")
        };

        var found = checks.Where(check => File.Exists(Path.Combine(projectRoot, check.File))).Select(check => check.Label).ToList();
        if (found.Count == 0)
            AnsiConsole.MarkupLine("[yellow]No recognized dependency file found in the project root.[/]");
        else
            AnsiConsole.MarkupLine($"[grey]Detected:[/] {string.Join(", ", found.Select(item => item.EscapeMarkup()))}");

        AnsiConsole.WriteLine();
    }

    static void SelectActiveAgent(JsonObject config)
    {
        var agents = ReadConfiguredAgents();
        var agentNode = EnsureObject(config, "agent");
        var currentAgentId = agentNode["agent_id"]?.GetValue<string>();

        if (agents == null || agents.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No configured agent profiles found.[/] Run 'felix agent setup' later if needed.");
            AnsiConsole.WriteLine();
            return;
        }

        if (agents.Count == 1)
        {
            agentNode["agent_id"] = agents[0].Key;
            AnsiConsole.MarkupLine($"[green]Active agent:[/] {agents[0].Name.EscapeMarkup()} [grey]({agents[0].Key.EscapeMarkup()})[/]");
            AnsiConsole.WriteLine();
            return;
        }

        var choices = new List<ConfiguredAgent>();
        if (!string.IsNullOrWhiteSpace(currentAgentId))
            choices.Add(new ConfiguredAgent("__keep__", "Keep current", "", "", false));
        choices.AddRange(agents);

        var selected = AnsiConsole.Prompt(
            new SelectionPrompt<ConfiguredAgent>()
                .Title("[cyan]Select the active agent Felix should use:[/]")
                .PageSize(10)
                .EnableSearch()
                .SearchPlaceholderText("[grey](type to filter agents or models)[/]")
                .UseConverter(agent => agent.Key == "__keep__"
                    ? $"[grey]{agent.Name.EscapeMarkup()}[/]"
                    : agent.IsCurrent
                        ? $"[green]*[/] {agent.Name.EscapeMarkup()} [grey](model: {agent.ModelDisplay.EscapeMarkup()}, key: {agent.Key.EscapeMarkup()})[/]"
                        : $"{agent.Name.EscapeMarkup()} [grey](model: {agent.ModelDisplay.EscapeMarkup()}, key: {agent.Key.EscapeMarkup()})[/]")
                .AddChoices(choices));

        if (selected.Key != "__keep__")
            agentNode["agent_id"] = selected.Key;

        AnsiConsole.WriteLine();
    }

    static void ConfigureBackpressureCommand(JsonObject config)
    {
        var backpressure = EnsureObject(config, "backpressure");
        var commands = backpressure["commands"] as JsonArray ?? new JsonArray();
        backpressure["commands"] = commands;
        var currentCommand = commands.Count > 0 ? commands[0]?.GetValue<string>() : null;

        var prompt = new TextPrompt<string>($"[cyan]Test command[/] [grey](Enter keeps {(currentCommand ?? "current empty").EscapeMarkup()})[/]")
            .AllowEmpty();
        var value = AnsiConsole.Prompt(prompt);

        if (!string.IsNullOrWhiteSpace(value))
        {
            backpressure["enabled"] = true;
            backpressure["commands"] = new JsonArray(value.Trim());
        }

        AnsiConsole.WriteLine();
    }

    static async Task ConfigureSyncModeAsync(JsonObject config)
    {
        var sync = EnsureObject(config, "sync");
        var currentMode = IsSyncEnabled(config) ? "remote" : "local";
        var mode = AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .Title($"[cyan]Execution mode[/] [grey](current: {currentMode.EscapeMarkup()})[/]")
                .AddChoices("local", "remote"));

        if (mode == "local")
        {
            sync["enabled"] = false;
            AnsiConsole.MarkupLine("[grey]Local mode selected.[/] Runs will only be saved locally.");
            AnsiConsole.WriteLine();
            return;
        }

        var currentUrl = sync["base_url"]?.GetValue<string>() ?? "https://api.runfelix.io";
        var newUrl = AnsiConsole.Prompt(
            new TextPrompt<string>($"[cyan]Backend URL[/] [grey](Enter keeps {currentUrl.EscapeMarkup()})[/]")
                .AllowEmpty());
        if (!string.IsNullOrWhiteSpace(newUrl))
            sync["base_url"] = newUrl.Trim().TrimEnd('/');

        currentUrl = sync["base_url"]?.GetValue<string>() ?? currentUrl;
        var currentKey = sync["api_key"]?.GetValue<string>();
        var keyPrompt = currentKey is { Length: > 0 }
            ? $"[cyan]API key[/] [grey](Enter keeps {currentKey[..Math.Min(12, currentKey.Length)].EscapeMarkup()}...)[/]"
            : "[cyan]API key[/] [grey](starts with fsk_)[/]";
        var newKey = AnsiConsole.Prompt(new TextPrompt<string>(keyPrompt).AllowEmpty());
        if (string.IsNullOrWhiteSpace(newKey))
            newKey = currentKey;
        else
            newKey = newKey.Trim();

        if (string.IsNullOrWhiteSpace(newKey))
        {
            sync["enabled"] = false;
            sync["api_key"] = null;
            AnsiConsole.MarkupLine("[yellow]No API key provided.[/] Sync stays disabled.");
            AnsiConsole.WriteLine();
            return;
        }

        if (!newKey.StartsWith("fsk_", StringComparison.Ordinal))
        {
            sync["enabled"] = false;
            sync["api_key"] = null;
            AnsiConsole.MarkupLine("[yellow]Invalid API key format.[/] Expected a key starting with fsk_.");
            AnsiConsole.WriteLine();
            return;
        }

        var validation = await ValidateApiKeyAsync(currentUrl, newKey);
        if (!validation.IsValid)
        {
            sync["enabled"] = false;
            sync["api_key"] = null;
            AnsiConsole.MarkupLine($"[yellow]API key validation failed:[/] {validation.ErrorMessage?.EscapeMarkup()}");
            AnsiConsole.WriteLine();
            return;
        }

        sync["api_key"] = newKey;
        sync["enabled"] = true;
        sync["provider"] = "http";
        AnsiConsole.MarkupLine("[green]Valid API key.[/]");
        if (!string.IsNullOrWhiteSpace(validation.ProjectName))
            AnsiConsole.MarkupLine($"[grey]Project:[/] {validation.ProjectName!.EscapeMarkup()} [grey][{validation.ProjectId?.EscapeMarkup()}][/] ");
        if (!string.IsNullOrWhiteSpace(validation.OrganizationId))
            AnsiConsole.MarkupLine($"[grey]Organization:[/] {validation.OrganizationId!.EscapeMarkup()}");
        if (!string.IsNullOrWhiteSpace(validation.ExpiresAt))
            AnsiConsole.MarkupLine($"[grey]Expires:[/] {validation.ExpiresAt!.EscapeMarkup()}");
        AnsiConsole.WriteLine();
    }

    static async Task<ApiKeyValidationResult> ValidateApiKeyAsync(string baseUrl, string apiKey)
    {
        try
        {
            using var client = new HttpClient();
            using var request = new HttpRequestMessage(HttpMethod.Get, baseUrl.TrimEnd('/') + "/api/keys/validate");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            using var response = await client.SendAsync(request);
            if (!response.IsSuccessStatusCode)
            {
                return new ApiKeyValidationResult(false, $"HTTP {(int)response.StatusCode} {response.ReasonPhrase}", null, null, null, null);
            }

            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            var root = document.RootElement;
            return new ApiKeyValidationResult(
                true,
                null,
                root.TryGetProperty("project_name", out var projectName) ? projectName.GetString() : null,
                root.TryGetProperty("project_id", out var projectId) ? projectId.GetRawText().Trim('"') : null,
                root.TryGetProperty("org_id", out var orgId) ? orgId.GetString() : null,
                root.TryGetProperty("expires_at", out var expiresAt) ? expiresAt.GetString() : null);
        }
        catch (Exception ex)
        {
            return new ApiKeyValidationResult(false, ex.Message, null, null, null, null);
        }
    }

    static void SaveSetupConfig(string configPath, JsonObject config)
    {
        File.WriteAllText(configPath, config.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine);
        AnsiConsole.MarkupLine("[green]Configuration saved to .felix/config.json[/]");
        AnsiConsole.WriteLine();
    }

    static bool IsSyncEnabled(JsonObject config)
    {
        var sync = EnsureObject(config, "sync");
        return sync["enabled"]?.GetValue<bool>() ?? false;
    }

    static JsonObject EnsureObject(JsonObject root, string propertyName)
    {
        if (root[propertyName] is JsonObject existing)
            return existing;

        var created = new JsonObject();
        root[propertyName] = created;
        return created;
    }

    static void WriteIfMissing(string path, string content, string label, List<string> created, List<string> skipped)
    {
        if (File.Exists(path))
        {
            skipped.Add(label);
            return;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content);
        created.Add(label);
    }

    static void CopyIfMissing(string sourcePath, string destinationPath, string label, List<string> created, List<string> skipped)
    {
        if (!File.Exists(sourcePath) || File.Exists(destinationPath))
        {
            skipped.Add(label);
            return;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
        File.Copy(sourcePath, destinationPath);
        created.Add(label);
    }

    static void EnsureDirectory(string path, string label, List<string> created, List<string> skipped)
    {
        if (Directory.Exists(path))
        {
            skipped.Add(label);
            return;
        }

        Directory.CreateDirectory(path);
        created.Add(label);
    }

    static void EnsureGitIgnore(string projectRoot, List<string> created, List<string> skipped)
    {
        var gitignorePath = Path.Combine(projectRoot, ".gitignore");
        var felixIgnoreLines = new[]
        {
            string.Empty,
            "# Felix local files (machine-specific, may contain API keys)",
            ".felix/config.json",
            ".felix/state.json",
            ".felix/outbox/",
            ".felix/sync.log",
            ".felix/spec-manifest.json",
            "# Felix .meta.json sidecars (server-generated cache, gitignored)",
            "specs/*.meta.json"
        };
        var block = string.Join(Environment.NewLine, felixIgnoreLines) + Environment.NewLine;

        if (File.Exists(gitignorePath))
        {
            var existing = File.ReadAllText(gitignorePath);
            if (existing.Contains(".felix/config.json", StringComparison.Ordinal))
            {
                skipped.Add(".gitignore");
                return;
            }

            File.AppendAllText(gitignorePath, block);
            created.Add(".gitignore (updated)");
            return;
        }

        File.WriteAllText(gitignorePath, string.Join(Environment.NewLine, felixIgnoreLines.Skip(1)) + Environment.NewLine);
        created.Add(".gitignore (created)");
    }

    static List<string>? ReadAgentModels(string provider)
    {
        var catalogPath = Path.Combine(_felixProjectRoot, ".felix", "agent-models.json");
        if (!File.Exists(catalogPath))
            catalogPath = Path.Combine(_felixInstallDir, "agent-models.json");
        if (!File.Exists(catalogPath))
            return null;

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(catalogPath));
            if (!doc.RootElement.TryGetProperty("providers", out var providersElement))
                return null;
            if (!providersElement.TryGetProperty(provider, out var modelsElement) || modelsElement.ValueKind != JsonValueKind.Array)
                return null;

            return modelsElement.EnumerateArray()
                .Where(model => model.ValueKind == JsonValueKind.String)
                .Select(model => model.GetString())
                .Where(model => !string.IsNullOrWhiteSpace(model))
                .Cast<string>()
                .ToList();
        }
        catch
        {
            return null;
        }
    }

    static List<ConfiguredAgent>? ReadConfiguredAgents()
    {
        var detailedAgents = ReadConfiguredAgentDetails();
        if (detailedAgents == null)
            return null;

        return detailedAgents
            .Select(agent => new ConfiguredAgent(agent.Key, agent.Name, agent.Provider, agent.ModelDisplay, agent.IsCurrent))
            .ToList();
    }

    static List<ConfiguredAgentDetails>? ReadConfiguredAgentDetails()
    {
        var agentsPath = Path.Combine(_felixProjectRoot, ".felix", "agents.json");
        if (!File.Exists(agentsPath))
            return null;

        string? currentAgentId = null;
        var configPath = Path.Combine(_felixProjectRoot, ".felix", "config.json");
        if (File.Exists(configPath))
        {
            try
            {
                using var configDoc = JsonDocument.Parse(File.ReadAllText(configPath));
                if (configDoc.RootElement.TryGetProperty("agent", out var agentObj) &&
                    agentObj.TryGetProperty("agent_id", out var agentIdValue))
                {
                    currentAgentId = agentIdValue.ValueKind switch
                    {
                        JsonValueKind.String => agentIdValue.GetString(),
                        JsonValueKind.Number => agentIdValue.GetRawText(),
                        _ => null
                    };
                }
            }
            catch { }
        }

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(agentsPath));
            if (!doc.RootElement.TryGetProperty("agents", out var agentsElement) || agentsElement.ValueKind != JsonValueKind.Array)
                return null;

            return agentsElement.EnumerateArray()
                .Select(agent =>
                {
                    var key = agent.TryGetProperty("key", out var keyProp)
                        ? keyProp.GetString()
                        : agent.TryGetProperty("id", out var idProp)
                            ? idProp.GetRawText().Trim('"')
                            : null;
                    var name = agent.TryGetProperty("name", out var nameProp) ? nameProp.GetString() : null;
                    var adapter = agent.TryGetProperty("adapter", out var adapterProp) ? adapterProp.GetString() : null;
                    var provider = agent.TryGetProperty("provider", out var providerProp)
                        ? providerProp.GetString()
                        : !string.IsNullOrWhiteSpace(adapter)
                            ? adapter
                            : name;
                    var model = agent.TryGetProperty("model", out var modelProp) ? modelProp.GetString() : null;
                    var executable = agent.TryGetProperty("executable", out var executableProp) ? executableProp.GetString() : null;

                    if (string.IsNullOrWhiteSpace(key) || string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(provider))
                        return null;

                    return new ConfiguredAgentDetails(
                        key!,
                        name!,
                        provider!,
                        string.IsNullOrWhiteSpace(adapter) ? provider! : adapter!,
                        string.IsNullOrWhiteSpace(model) ? "default" : model!,
                        string.Equals(key, currentAgentId, StringComparison.OrdinalIgnoreCase),
                        string.IsNullOrWhiteSpace(executable) ? GetAgentDefaults(string.IsNullOrWhiteSpace(adapter) ? provider! : adapter!).Executable : executable!);
                })
                .Where(agent => agent != null)
                .Cast<ConfiguredAgentDetails>()
                .OrderByDescending(agent => agent.IsCurrent)
                .ThenBy(agent => agent.Name, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }
        catch
        {
            return null;
        }
    }

    static async Task UseAgentSelectionUI(string target, string? requestedModel, bool setDefault)
    {
        var profilesDocument = LoadAgentProfilesJson();
        var agents = EnsureAgentProfilesArray(profilesDocument);
        if (agents.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No configured agents found. Run 'felix agent setup' first.[/]");
            Environment.ExitCode = 1;
            return;
        }

        var selectedAgent = FindAgentProfileNode(agents, target);
        if (selectedAgent == null)
        {
            AnsiConsole.MarkupLine($"[red]Agent not found: {target.EscapeMarkup()}[/]");
            Environment.ExitCode = 1;
            return;
        }

        var selectedAgentKey = GetAgentProfileKey(selectedAgent);
        var selectedAgentName = GetOptionalJsonString(selectedAgent, "name") ?? target;
        var selectedModel = GetOptionalJsonString(selectedAgent, "model") ?? string.Empty;
        var profilesChanged = false;

        if (!string.IsNullOrWhiteSpace(requestedModel) && !string.Equals(selectedModel, requestedModel, StringComparison.OrdinalIgnoreCase))
        {
            var adapterType = GetOptionalJsonString(selectedAgent, "adapter")
                ?? GetOptionalJsonString(selectedAgent, "provider")
                ?? GetOptionalJsonString(selectedAgent, "name")
                ?? string.Empty;
            var provider = GetOptionalJsonString(selectedAgent, "provider")
                ?? adapterType;

            var defaults = GetAgentDefaults(adapterType);
            var keySettings = BuildAgentKeySettings(selectedAgent, defaults);
            var newKey = NewAgentKey(provider, requestedModel, keySettings, _felixProjectRoot);
            var existingAgent = FindAgentProfileNode(agents, newKey);

            if (existingAgent != null)
            {
                selectedAgent = existingAgent;
                selectedAgentKey = GetAgentProfileKey(selectedAgent);
                selectedAgentName = GetOptionalJsonString(selectedAgent, "name") ?? selectedAgentName;
                selectedModel = GetOptionalJsonString(selectedAgent, "model") ?? requestedModel;
            }
            else
            {
                selectedAgent["model"] = requestedModel;
                selectedAgent["key"] = newKey;
                if (selectedAgent.ContainsKey("id"))
                    selectedAgent["id"] = newKey;

                selectedAgentKey = newKey;
                selectedModel = requestedModel;
                profilesChanged = true;
            }
        }

        if (string.IsNullOrWhiteSpace(selectedAgentKey))
        {
            AnsiConsole.MarkupLine($"[red]Agent '{selectedAgentName.EscapeMarkup()}' is missing a key in agents.json.[/]");
            Environment.ExitCode = 1;
            return;
        }

        if (profilesChanged)
            SaveAgentProfilesJson(profilesDocument);

        var configPath = Path.Combine(_felixProjectRoot, ".felix", "config.json");
        var config = LoadSetupConfig(configPath);
        EnsureSetupConfigDefaults(config);
        EnsureObject(config, "agent")["agent_id"] = selectedAgentKey;
        File.WriteAllText(configPath, config.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine);

        AnsiConsole.Write(new Panel($"[white]{selectedAgentName.EscapeMarkup()}[/]\n[grey]Key:[/] {selectedAgentKey.EscapeMarkup()}\n[grey]Model:[/] {(string.IsNullOrWhiteSpace(selectedModel) ? "default" : selectedModel).EscapeMarkup()}")
        {
            Header = new PanelHeader(setDefault ? "[green]Default Agent Updated[/]" : "[green]Active Agent Updated[/]"),
            Border = BoxBorder.Rounded,
            BorderStyle = Style.Parse("green")
        });
        AnsiConsole.WriteLine();
        Environment.ExitCode = 0;
        await Task.CompletedTask;
    }

    static JsonObject? FindAgentProfileNode(JsonArray agents, string target)
    {
        foreach (var node in agents)
        {
            if (node is not JsonObject agent)
                continue;

            if (target.StartsWith("ag_", StringComparison.OrdinalIgnoreCase))
            {
                var key = GetAgentProfileKey(agent);
                if (string.Equals(key, target, StringComparison.OrdinalIgnoreCase))
                    return agent;
            }
            else
            {
                var name = GetOptionalJsonString(agent, "name");
                if (string.Equals(name, target, StringComparison.OrdinalIgnoreCase))
                    return agent;
            }
        }

        return null;
    }

    static string? GetAgentProfileKey(JsonObject agent)
        => GetOptionalJsonString(agent, "key")
            ?? GetOptionalJsonString(agent, "id");

    static string? GetOptionalJsonString(JsonObject obj, string propertyName)
    {
        if (obj[propertyName] is JsonValue value && value.TryGetValue<string>(out var stringValue) && !string.IsNullOrWhiteSpace(stringValue))
            return stringValue;

        return null;
    }

    static object? ConvertJsonNodeToObject(JsonNode? node)
    {
        return node switch
        {
            null => null,
            JsonObject jsonObject => jsonObject.ToDictionary(pair => pair.Key, pair => ConvertJsonNodeToObject(pair.Value), StringComparer.Ordinal),
            JsonArray jsonArray => jsonArray.Select(ConvertJsonNodeToObject).ToList(),
            JsonValue jsonValue => jsonValue.GetValue<object?>(),
            _ => node.ToJsonString()
        };
    }

    static void ShowAgentListUI()
    {
        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Configured Agents[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var agents = ReadConfiguredAgentDetails();
        if (agents == null || agents.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No configured agents found. Run 'felix agent setup' first.[/]");
            Environment.ExitCode = 1;
            return;
        }

        var table = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Current[/]").Centered().NoWrap())
            .AddColumn(new TableColumn("[yellow]Key[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Name[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Provider[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Model[/]"))
            .AddColumn(new TableColumn("[yellow]Executable[/]"));

        foreach (var agent in agents)
        {
            var installed = TestExecutableInstalled(agent.Executable);
            table.AddRow(
                agent.IsCurrent ? "[green]*[/]" : "[grey]-[/]",
                agent.Key.EscapeMarkup(),
                agent.Name.EscapeMarkup(),
                agent.Provider.EscapeMarkup(),
                agent.ModelDisplay.EscapeMarkup(),
                installed ? $"[green]{agent.Executable.EscapeMarkup()}[/]" : $"[yellow]{agent.Executable.EscapeMarkup()}[/]");
        }

        AnsiConsole.Write(table);
        AnsiConsole.WriteLine();
        Environment.ExitCode = 0;
    }

    static void ShowCurrentAgentUI()
    {
        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Current Agent[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var current = ReadConfiguredAgentDetails()?.FirstOrDefault(agent => agent.IsCurrent);
        if (current == null)
        {
            AnsiConsole.MarkupLine("[red]No current agent configured.[/]");
            Environment.ExitCode = 1;
            return;
        }

        var details = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Field[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Value[/]"));
        details.AddRow("Key", current.Key.EscapeMarkup());
        details.AddRow("Name", current.Name.EscapeMarkup());
        details.AddRow("Provider", current.Provider.EscapeMarkup());
        details.AddRow("Adapter", current.Adapter.EscapeMarkup());
        details.AddRow("Model", current.ModelDisplay.EscapeMarkup());
        details.AddRow("Executable", TestExecutableInstalled(current.Executable)
            ? $"[green]{current.Executable.EscapeMarkup()}[/]"
            : $"[yellow]{current.Executable.EscapeMarkup()}[/]");

        AnsiConsole.Write(new Panel(details)
        {
            Header = new PanelHeader("[cyan]Agent Details[/]"),
            Border = BoxBorder.Rounded,
            BorderStyle = Style.Parse("cyan")
        });
        AnsiConsole.WriteLine();
        Environment.ExitCode = 0;
    }

    static void ShowAgentInstallHelpUI(string? target)
    {
        var templates = ReadAgentTemplates()
            ?? new List<AgentTemplateEntry>
            {
                new("droid", "droid", "droid", null, null),
                new("claude", "claude", "claude", null, null),
                new("codex", "codex", "codex", null, null),
                new("gemini", "gemini", "gemini", null, null),
                new("copilot", "copilot", "copilot", null, null)
            };

        if (!string.IsNullOrWhiteSpace(target))
        {
            templates = templates
                .Where(template => string.Equals(template.Name, target, StringComparison.OrdinalIgnoreCase))
                .ToList();

            if (templates.Count == 0)
            {
                AnsiConsole.MarkupLine($"[red]Unknown agent: {target.EscapeMarkup()}[/]");
                Environment.ExitCode = 1;
                return;
            }
        }

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Agent Install Help[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var table = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Agent[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Executable[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Status[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Guidance[/]"));

        foreach (var template in templates.OrderBy(template => template.Name, StringComparer.OrdinalIgnoreCase))
        {
            var executable = ResolveExecutableName(template);
            var installed = TestExecutableInstalled(executable);
            table.AddRow(
                template.Name.EscapeMarkup(),
                executable.EscapeMarkup(),
                installed ? "[green]installed[/]" : "[yellow]not installed[/]",
                string.Join(Environment.NewLine, GetAgentInstallGuidance(template.Name)).EscapeMarkup());
        }

        AnsiConsole.Write(table);
        AnsiConsole.WriteLine();
        Environment.ExitCode = 0;
    }

    static async Task ShowAgentTestUI(string target)
    {
        var agents = ReadConfiguredAgentDetails();
        if (agents == null || agents.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No configured agents found. Run 'felix agent setup' first.[/]");
            Environment.ExitCode = 1;
            return;
        }

        var agent = target.StartsWith("ag_", StringComparison.OrdinalIgnoreCase)
            ? agents.FirstOrDefault(candidate => string.Equals(candidate.Key, target, StringComparison.OrdinalIgnoreCase))
            : agents.FirstOrDefault(candidate => string.Equals(candidate.Name, target, StringComparison.OrdinalIgnoreCase));

        if (agent == null)
        {
            AnsiConsole.MarkupLine($"[red]Agent not found: {target.EscapeMarkup()}[/]");
            Environment.ExitCode = 1;
            return;
        }

        var executablePath = ResolveAgentExecutablePath(agent.Executable);
        var executableOk = executablePath != null;
        string versionStatus;
        string versionBody;

        if (!executableOk)
        {
            versionStatus = "[grey]not run[/]";
            versionBody = "Executable not found on PATH.";
        }
        else
        {
            var versionResult = await TryRunProcessCaptureAsync(executablePath!, "--version", 5000);
            if (versionResult.Success)
            {
                versionStatus = "[green]ok[/]";
                versionBody = string.IsNullOrWhiteSpace(versionResult.Output) ? "Version command returned no output." : versionResult.Output.Trim();
            }
            else
            {
                versionStatus = "[yellow]skipped[/]";
                versionBody = versionResult.TimedOut
                    ? "Version check timed out."
                    : "Version check not supported or returned a non-zero exit code.";
            }
        }

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule($"[cyan]Test Agent: {agent.Name.EscapeMarkup()}[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var table = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Check[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Result[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Details[/]"));
        table.AddRow(
            "Executable",
            executableOk ? "[green]ok[/]" : "[red]failed[/]",
            executableOk ? executablePath!.EscapeMarkup() : $"Executable '{agent.Executable.EscapeMarkup()}' not found on PATH");
        table.AddRow("Version", versionStatus, versionBody.EscapeMarkup());

        AnsiConsole.Write(table);
        AnsiConsole.WriteLine();
        if (executableOk)
            AnsiConsole.MarkupLine("[green]Agent test passed.[/]");

        Environment.ExitCode = executableOk ? 0 : 1;
    }

    static async Task RegisterCurrentAgentUI()
    {
        var configPath = Path.Combine(_felixProjectRoot, ".felix", "config.json");
        var config = LoadSetupConfig(configPath);
        EnsureSetupConfigDefaults(config);
        var interactiveInput = !Console.IsInputRedirected;

        var profilesDocument = LoadAgentProfilesJson();
        var agents = EnsureAgentProfilesArray(profilesDocument);
        var currentAgentId = GetOptionalJsonString(EnsureObject(config, "agent"), "agent_id");
        if (string.IsNullOrWhiteSpace(currentAgentId))
        {
            AnsiConsole.MarkupLine("[red]No current agent configured.[/]");
            Environment.ExitCode = 1;
            return;
        }

        var currentAgent = FindAgentProfileNode(agents, currentAgentId);
        if (currentAgent == null)
        {
            AnsiConsole.MarkupLine($"[red]Current agent (ID: {currentAgentId.EscapeMarkup()}) not found in agents.json.[/]");
            Environment.ExitCode = 1;
            return;
        }

        var sync = EnsureObject(config, "sync");
        var syncEnabled = IsSyncEnabled(config);
        var targetUrl = syncEnabled
            ? GetOptionalJsonString(sync, "base_url") ?? "https://api.runfelix.io"
            : Environment.GetEnvironmentVariable("FELIX_SYNC_URL")
                ?? GetOptionalJsonString(sync, "base_url")
                ?? "https://api.runfelix.io";

        var apiKey = syncEnabled
            ? GetOptionalJsonString(sync, "api_key")
            : Environment.GetEnvironmentVariable("FELIX_SYNC_KEY")
                ?? GetOptionalJsonString(sync, "api_key");

        if (!syncEnabled)
        {
            var disabledPanel = new Panel($"[yellow]Sync is not enabled in this project.[/]\n[grey]Target URL:[/] {targetUrl.EscapeMarkup()}\n[grey]API key:[/] {MaskApiKey(apiKey).EscapeMarkup()}")
            {
                Header = new PanelHeader("[yellow]Registration Warning[/]"),
                Border = BoxBorder.Rounded,
                BorderStyle = Style.Parse("yellow")
            };
            AnsiConsole.Write(disabledPanel);
            if (interactiveInput && !AnsiConsole.Confirm("Attempt registration anyway?", false))
            {
                AnsiConsole.MarkupLine("[grey]Cancelled.[/]");
                Environment.ExitCode = 0;
                return;
            }

            if (!interactiveInput)
                AnsiConsole.MarkupLine("[grey]Non-interactive input detected. Continuing with the current sync settings.[/]");
        }

        AnsiConsole.MarkupLine($"[grey]URL:[/] {targetUrl.EscapeMarkup()}");
        AnsiConsole.MarkupLine($"[grey]Key:[/] {MaskApiKey(apiKey).EscapeMarkup()}");
        if (interactiveInput)
        {
            var overrideKey = AnsiConsole.Prompt(
                new TextPrompt<string>("[cyan]Press Enter to use the current key, or paste a new API key[/]")
                    .AllowEmpty());
            if (!string.IsNullOrWhiteSpace(overrideKey))
                apiKey = overrideKey.Trim();
        }

        var payload = BuildAgentRegistrationPayload(currentAgent, "felix agent register");
        var gitUrl = GetOptionalJsonString(payload, "git_url");

        if (string.IsNullOrWhiteSpace(gitUrl))
            AnsiConsole.MarkupLine("[yellow]No git remote 'origin' found. Registration may fail with API key auth.[/]");

        var agentName = GetOptionalJsonString(currentAgent, "name") ?? currentAgentId;
        AnsiConsole.MarkupLine($"[cyan]Registering agent '{agentName.EscapeMarkup()}'...[/]");

        var result = await SendJsonRequestWithStatusAsync(targetUrl, "/api/agents/register-sync", payload, apiKey);
        if (result.Success)
        {
            AnsiConsole.MarkupLine($"[green]Agent registered successfully.[/] [grey](key: {(GetOptionalJsonString(payload, "key") ?? currentAgentId).EscapeMarkup()})[/]");
            Environment.ExitCode = 0;
            return;
        }

        AnsiConsole.MarkupLine("[red]Registration failed.[/]");
        if (!string.IsNullOrWhiteSpace(result.Error))
            AnsiConsole.MarkupLine($"[red]{result.Error.EscapeMarkup()}[/]");
        AnsiConsole.MarkupLine("[grey]Run 'felix agent register' again to supply a different key.[/]");
        Environment.ExitCode = 1;
    }

    static JsonObject BuildAgentRegistrationPayload(JsonObject agentConfig, string source)
    {
        var provider = GetOptionalJsonString(agentConfig, "adapter")
            ?? GetOptionalJsonString(agentConfig, "name")
            ?? string.Empty;
        var model = GetOptionalJsonString(agentConfig, "model") ?? string.Empty;
        var agentKey = NewAgentKey(provider, model, new Dictionary<string, object?>(), _felixProjectRoot);
        var hostname = Environment.MachineName;
        if (string.IsNullOrWhiteSpace(hostname))
        {
            try
            {
                hostname = System.Net.Dns.GetHostName();
            }
            catch
            {
                hostname = "unknown";
            }
        }

        var payload = new JsonObject
        {
            ["key"] = agentKey,
            ["provider"] = provider,
            ["model"] = model,
            ["agent_settings"] = new JsonObject(),
            ["machine_id"] = hostname,
            ["name"] = GetOptionalJsonString(agentConfig, "name") ?? provider,
            ["type"] = "cli",
            ["metadata"] = new JsonObject
            {
                ["hostname"] = hostname,
                ["adapter"] = provider,
                ["source"] = source
            }
        };

        if (!string.IsNullOrWhiteSpace(model))
            ((JsonObject)payload["metadata"]!)["model"] = model;

        var gitUrl = TryReadGitRemoteOrigin(_felixProjectRoot);
        if (!string.IsNullOrWhiteSpace(gitUrl))
            payload["git_url"] = gitUrl;

        return payload;
    }

    internal sealed record ApiKeyValidationResult(bool IsValid, string? ErrorMessage, string? ProjectName, string? ProjectId, string? OrganizationId, string? ExpiresAt);

    sealed record HttpRequestResult(bool Success, int StatusCode, string? Error);

    static async Task<HttpRequestResult> SendJsonRequestWithStatusAsync(string baseUrl, string endpoint, JsonObject payload, string? apiKey)
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
            using var request = new HttpRequestMessage(HttpMethod.Post, baseUrl.TrimEnd('/') + endpoint)
            {
                Content = new StringContent(payload.ToJsonString(), Encoding.UTF8, "application/json")
            };
            if (!string.IsNullOrWhiteSpace(apiKey))
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);

            using var response = await client.SendAsync(request);
            if (response.IsSuccessStatusCode)
                return new HttpRequestResult(true, (int)response.StatusCode, null);

            var responseBody = await response.Content.ReadAsStringAsync();
            return new HttpRequestResult(false, (int)response.StatusCode, ExtractApiErrorMessage(responseBody) ?? $"HTTP {(int)response.StatusCode} {response.ReasonPhrase}");
        }
        catch (Exception ex)
        {
            return new HttpRequestResult(false, 0, ex.Message);
        }
    }
}
