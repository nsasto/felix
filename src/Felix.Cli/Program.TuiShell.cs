using System.Text;
using System.Text.RegularExpressions;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    static bool _shellModeActive;

    internal sealed record TuiCommandDefinition(string Name, string Description, string Usage, Func<string[], Task<bool>> ExecuteAsync);
    internal sealed record TuiSuggestion(string Value, string Description, bool IsCommand);

    static async Task RunCopilotStyleTui(string felixPs1)
    {
        _shellModeActive = true;
        try
        {
            AnsiConsole.Clear();
            RenderTuiWelcomeCard();
            AnsiConsole.WriteLine();
            AnsiConsole.MarkupLine("[grey]Type [cyan]/[/] to open commands. Use [cyan]Esc[/] or [cyan]Backspace[/] on empty input to close suggestions.[/]");
            AnsiConsole.WriteLine();

            var commands = BuildTuiCommands(felixPs1);
            var running = true;
            while (running)
            {
                var input = CaptureTuiInput(commands);
                if (string.IsNullOrWhiteSpace(input))
                    continue;

                AnsiConsole.MarkupLine($"[cyan]>[/] {input.EscapeMarkup()}");
                try
                {
                    running = await ExecuteTuiCommand(commands, input);
                }
                catch (Exception ex)
                {
                    AnsiConsole.MarkupLine($"[red]Error:[/] {ex.Message.EscapeMarkup()}");
                }

                if (running)
                    AnsiConsole.WriteLine();
            }

            AnsiConsole.MarkupLine("[green]Felix TUI exited.[/]");
        }
        finally
        {
            _shellModeActive = false;
        }
    }

    static void ClearIfStandalone()
    {
        if (!_shellModeActive)
            AnsiConsole.Clear();
    }

    static void RenderTuiWelcomeCard()
    {
        var requirements = ParseRequirementsJson(ReadRequirementsJson()) ?? new List<System.Text.Json.JsonElement>();
        var total = requirements.Count;
        var statusCounts = requirements
            .GroupBy(req => GetJsonString(req, "status") ?? "unknown", StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.Count(), StringComparer.OrdinalIgnoreCase);

        var configuredAgents = ReadConfiguredAgents() ?? new List<ConfiguredAgent>();
        var currentAgent = configuredAgents.FirstOrDefault(agent => agent.IsCurrent);
        var currentAgentLabel = currentAgent == null
            ? "not set"
            : $"{currentAgent.Name} ({currentAgent.ModelDisplay})";

        var wordmark = string.Join(Environment.NewLine, new[]
        {
            "FFFFFFFFF EEEEEEEE L        IIIIII  X     X",
            "F         E        L          II     X   X ",
            "FFFFF     EEEEE    L          II      X X  ",
            "F         E        L          II     X   X ",
            "F         EEEEEEEE LLLLLLL  IIIIII  X     X"
        });

        var lines = new List<string>
        {
            $"[green]{wordmark.EscapeMarkup()}[/]",
            string.Empty,
            $"[grey]project[/] [white]{_felixProjectRoot.EscapeMarkup()}[/]",
            $"[grey]requirements[/] [white]{total}[/]  [grey]planned[/] [cyan]{statusCounts.GetValueOrDefault("planned", 0)}[/]  [grey]in progress[/] [yellow]{statusCounts.GetValueOrDefault("in_progress", 0)}[/]  [grey]done[/] [blue]{statusCounts.GetValueOrDefault("done", 0)}[/]  [grey]complete[/] [green]{statusCounts.GetValueOrDefault("complete", 0)}[/]  [grey]blocked[/] [red]{statusCounts.GetValueOrDefault("blocked", 0)}[/]",
            $"[grey]active agent[/] [white]{currentAgentLabel.EscapeMarkup()}[/]  [grey]configured agents[/] [white]{configuredAgents.Count}[/]"
        };

        var panel = new Panel(string.Join(Environment.NewLine, lines))
        {
            Header = new PanelHeader("[grey]Felix TUI[/]", Justify.Left),
            Border = BoxBorder.Rounded,
            BorderStyle = Style.Parse("grey"),
            Expand = true,
            Padding = new Padding(1, 0, 1, 0)
        };

        AnsiConsole.Write(panel);
    }

    static List<TuiCommandDefinition> BuildTuiCommands(string felixPs1)
    {
        return new List<TuiCommandDefinition>
        {
            new("help", "Show shell help", "/help", async _ => { ShowHelp(); return true; }),
            new("version", "Show version information", "/version", async _ => { await ShowVersionUI(); return true; }),
            new("status", "Show requirement status overview", "/status", async _ => { await ShowStatusUI(felixPs1); return true; }),
            new("list", "List requirements", "/list [status] [--with-deps]", async args => { await ExecuteListCommand(felixPs1, args); return true; }),
            new("run-next", "Run next available requirement", "/run-next", async _ => { await ExecuteFelixRichCommand(felixPs1, "Run Next Requirement", "run-next"); return true; }),
            new("run", "Run a planned requirement", "/run <requirement-id>", async args => { if (args.Length == 0) { AnsiConsole.MarkupLine("[yellow]Usage:[/] /run <requirement-id>"); return true; } await ExecuteFelixRichCommand(felixPs1, "Run Requirement", "run", args[0]); return true; }),
            new("loop", "Run in continuous loop mode", "/loop [--max-iterations N]", async args => { await ExecuteFelixRichCommand(felixPs1, "Continuous Loop", new[] { "loop" }.Concat(args).ToArray()); return true; }),
            new("validate", "Validate a completed requirement", "/validate <requirement-id>", async args => { if (args.Length == 0) { AnsiConsole.MarkupLine("[yellow]Usage:[/] /validate <requirement-id>"); return true; } await ShowValidateUI(felixPs1, args[0]); return true; }),
            new("deps", "Show dependency status", "/deps <requirement-id>|--incomplete [--tree] [--check]", async args => { await ExecuteDepsCommand(args); return true; }),
            new("procs", "Show active sessions", "/procs", async _ => { await ShowProcs(felixPs1); return true; }),
            new("setup", "Run Felix setup", "/setup", async _ => { await ExecutePowerShell(felixPs1, "setup"); return true; }),
            new("context", "Run context command", "/context <subcommand>", async args => { await ExecutePowerShell(felixPs1, new[] { "context" }.Concat(args).ToArray()); return true; }),
            new("spec-create", "Create a specification", "/spec-create <description>", async args => { if (args.Length == 0) { AnsiConsole.MarkupLine("[yellow]Usage:[/] /spec-create <description>"); return true; } await ExecutePowerShell(felixPs1, "spec", "create", string.Join(" ", args)); return true; }),
            new("spec-pull", "Pull specs from server", "/spec-pull", async _ => { await ExecutePowerShell(felixPs1, "spec", "pull"); return true; }),
            new("spec-fix", "Fix spec alignment", "/spec-fix", async _ => { await ExecutePowerShell(felixPs1, "spec", "fix"); return true; }),
            new("agent-list", "Show configured agents", "/agent-list", async _ => { ShowAgentListUI(); return true; }),
            new("agent-current", "Show current agent", "/agent-current", async _ => { ShowCurrentAgentUI(); return true; }),
            new("quit", "Exit the TUI", "/quit", async _ => false),
            new("exit", "Exit the TUI", "/exit", async _ => false),
        };
    }

    static async Task ExecuteListCommand(string felixPs1, string[] args)
    {
        string? status = null;
        var withDeps = args.Contains("--with-deps", StringComparer.OrdinalIgnoreCase);
        var firstValueArg = args.FirstOrDefault(arg => !arg.StartsWith("--", StringComparison.Ordinal));
        if (!string.IsNullOrWhiteSpace(firstValueArg))
            status = firstValueArg;

        await ShowListUI(felixPs1, status, null, null, null, withDeps);
    }

    static async Task ExecuteDepsCommand(string[] args)
    {
        if (args.Length == 0 || args.Contains("--incomplete", StringComparer.OrdinalIgnoreCase))
        {
            ShowDependencyOverviewUI();
            await Task.CompletedTask;
            return;
        }

        var requirementId = args.FirstOrDefault(arg => !arg.StartsWith("--", StringComparison.Ordinal));
        if (string.IsNullOrWhiteSpace(requirementId))
        {
            AnsiConsole.MarkupLine("[yellow]Usage:[/] /deps <requirement-id>|--incomplete [--tree] [--check]");
            return;
        }

        var showTree = args.Contains("--tree", StringComparer.OrdinalIgnoreCase);
        var checkOnly = args.Contains("--check", StringComparer.OrdinalIgnoreCase);
        ShowRequirementDependenciesUI(requirementId, checkOnly, showTree);
        await Task.CompletedTask;
    }

    static async Task<bool> ExecuteTuiCommand(List<TuiCommandDefinition> commands, string input)
    {
        if (!input.StartsWith("/", StringComparison.Ordinal))
        {
            AnsiConsole.MarkupLine("[yellow]Commands must start with '/'. Type /help for available commands.[/]");
            return true;
        }

        var tokens = TokenizeShellInput(input);
        if (tokens.Length == 0)
            return true;

        var commandName = tokens[0].TrimStart('/');
        var command = commands.FirstOrDefault(candidate => string.Equals(candidate.Name, commandName, StringComparison.OrdinalIgnoreCase));
        if (command == null)
        {
            AnsiConsole.MarkupLine($"[red]Unknown command:[/] {commandName.EscapeMarkup()}");
            return true;
        }

        return await command.ExecuteAsync(tokens.Skip(1).ToArray());
    }

    internal static string[] TokenizeShellInput(string input)
    {
        return Regex.Matches(input, "\"([^\"]*)\"|(\\S+)")
            .Select(match => match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .ToArray();
    }

    static string? CaptureTuiInput(List<TuiCommandDefinition> commands)
    {
        var buffer = new StringBuilder();
        var suggestions = new List<TuiSuggestion>();
        var selectedIndex = 0;
        var previousLines = 0;
        var originTop = Console.CursorTop;

        while (true)
        {
            suggestions = GetTuiSuggestions(commands, buffer.ToString());
            if (selectedIndex >= suggestions.Count)
                selectedIndex = suggestions.Count == 0 ? 0 : suggestions.Count - 1;

            previousLines = RenderPromptBlock(buffer.ToString(), suggestions, selectedIndex, originTop, previousLines);
            var key = Console.ReadKey(intercept: true);

            if (key.Key == ConsoleKey.Escape)
            {
                ClearPromptBlock(originTop, previousLines);
                return null;
            }

            if (key.Key == ConsoleKey.Enter)
            {
                var finalInput = ResolveFinalInput(buffer.ToString(), suggestions, selectedIndex);
                ClearPromptBlock(originTop, previousLines);
                return string.IsNullOrWhiteSpace(finalInput) ? null : finalInput;
            }

            if (key.Key == ConsoleKey.UpArrow)
            {
                if (suggestions.Count > 0)
                    selectedIndex = (selectedIndex - 1 + suggestions.Count) % suggestions.Count;
                continue;
            }

            if (key.Key == ConsoleKey.DownArrow)
            {
                if (suggestions.Count > 0)
                    selectedIndex = (selectedIndex + 1) % suggestions.Count;
                continue;
            }

            if (key.Key == ConsoleKey.Backspace)
            {
                if (buffer.Length == 0)
                {
                    ClearPromptBlock(originTop, previousLines);
                    return null;
                }

                buffer.Length -= 1;
                if (buffer.Length == 0)
                {
                    ClearPromptBlock(originTop, previousLines);
                    return null;
                }

                continue;
            }

            if (!char.IsControl(key.KeyChar))
            {
                buffer.Append(key.KeyChar);
                selectedIndex = 0;
            }
        }
    }

    static int RenderPromptBlock(string input, List<TuiSuggestion> suggestions, int selectedIndex, int originTop, int previousLines)
    {
        Console.SetCursorPosition(0, originTop);
        var width = Math.Max(40, Console.WindowWidth - 1);
        var innerWidth = Math.Max(10, width - 4);
        var lines = new List<string>
        {
            "+" + new string('-', innerWidth + 2) + "+",
            "| " + TruncatePad(input, innerWidth) + " |",
            "+" + new string('-', innerWidth + 2) + "+"
        };

        foreach (var suggestion in suggestions.Take(6).Select((suggestion, index) => new { suggestion, index }))
        {
            var prefix = suggestion.index == selectedIndex ? ">" : " ";
            var text = $"{prefix} {suggestion.suggestion.Value} - {suggestion.suggestion.Description}";
            lines.Add(TruncatePad(text, width));
        }

        while (lines.Count < previousLines)
            lines.Add(new string(' ', width));

        foreach (var line in lines)
        {
            Console.Write(line.PadRight(width));
            Console.WriteLine();
        }

        Console.SetCursorPosition(Math.Min(innerWidth + 2, input.Length + 2), originTop + 1);
        return lines.Count;
    }

    static void ClearPromptBlock(int originTop, int lineCount)
    {
        var width = Math.Max(40, Console.WindowWidth - 1);
        Console.SetCursorPosition(0, originTop);
        for (var index = 0; index < lineCount; index++)
        {
            Console.Write(new string(' ', width));
            Console.WriteLine();
        }
        Console.SetCursorPosition(0, originTop);
    }

    static string TruncatePad(string value, int width)
    {
        if (value.Length > width)
            return value[..Math.Max(0, width - 3)] + "...";

        return value.PadRight(width);
    }

    internal static string ResolveFinalInput(string input, List<TuiSuggestion> suggestions, int selectedIndex)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            if (suggestions.Count == 0)
                return string.Empty;
            return "/" + suggestions[selectedIndex].Value;
        }

        if (suggestions.Count == 0)
            return input;

        var suggestion = suggestions[Math.Clamp(selectedIndex, 0, suggestions.Count - 1)];
        if (suggestion.IsCommand)
        {
            if (!input.StartsWith('/'))
                return "/" + suggestion.Value;

            if (!input.Contains(' '))
                return "/" + suggestion.Value;
        }
        else if (input.StartsWith('/'))
        {
            var parts = input.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToList();
            if (parts.Count == 1)
                return input + " " + suggestion.Value;

            parts[^1] = suggestion.Value;
            return string.Join(" ", parts);
        }

        return input;
    }

    internal static List<TuiSuggestion> GetTuiSuggestions(List<TuiCommandDefinition> commands, string input)
    {
        var trimmed = input.Trim();
        if (trimmed.Length == 0)
            return new List<TuiSuggestion>();

        if (!trimmed.StartsWith('/'))
            return new List<TuiSuggestion>();

        var body = trimmed[1..];
        var spaceIndex = body.IndexOf(' ');
        if (spaceIndex < 0)
        {
            var exactCommand = commands.FirstOrDefault(command => string.Equals(command.Name, body, StringComparison.OrdinalIgnoreCase));
            if (exactCommand != null)
                return GetDynamicArgumentSuggestions(exactCommand.Name, string.Empty);

            return commands
                .Where(command => command.Name.StartsWith(body, StringComparison.OrdinalIgnoreCase))
                .OrderBy(command => command.Name, StringComparer.OrdinalIgnoreCase)
                .Take(8)
                .Select(command => new TuiSuggestion(command.Name, command.Description, true))
                .ToList();
        }

        var commandName = body[..spaceIndex];
        var partialArg = body[(spaceIndex + 1)..].Trim();
        return GetDynamicArgumentSuggestions(commandName, partialArg);
    }

    static List<TuiSuggestion> GetDynamicArgumentSuggestions(string commandName, string partialArg)
    {
        IEnumerable<TuiSuggestion> suggestions = commandName.ToLowerInvariant() switch
        {
            "run" => GetRequirementSuggestions("planned").Select(id => new TuiSuggestion(id, "planned requirement", false)),
            "validate" => GetRequirementSuggestions("done").Select(id => new TuiSuggestion(id, "done requirement", false)),
            "deps" => GetRequirementSuggestions(null).Select(id => new TuiSuggestion(id, "requirement id", false))
                .Concat(new[] { new TuiSuggestion("--incomplete", "show incomplete dependencies", false), new TuiSuggestion("--tree", "show dependency tree", false), new TuiSuggestion("--check", "quick validation check", false) }),
            "list" => new[]
            {
                new TuiSuggestion("planned", "filter planned requirements", false),
                new TuiSuggestion("in_progress", "filter in progress requirements", false),
                new TuiSuggestion("done", "filter done requirements", false),
                new TuiSuggestion("complete", "filter complete requirements", false),
                new TuiSuggestion("blocked", "filter blocked requirements", false),
                new TuiSuggestion("--with-deps", "show dependencies inline", false)
            },
            _ => Array.Empty<TuiSuggestion>()
        };

        return suggestions
            .Where(suggestion => string.IsNullOrWhiteSpace(partialArg) || suggestion.Value.StartsWith(partialArg, StringComparison.OrdinalIgnoreCase))
            .Take(8)
            .ToList();
    }

    static IEnumerable<string> GetRequirementSuggestions(string? requiredStatus)
    {
        var requirements = ParseRequirementsJson(ReadRequirementsJson()) ?? new List<System.Text.Json.JsonElement>();
        foreach (var requirement in requirements)
        {
            var status = GetJsonString(requirement, "status") ?? string.Empty;
            if (!string.IsNullOrWhiteSpace(requiredStatus) && !string.Equals(status, requiredStatus, StringComparison.OrdinalIgnoreCase))
                continue;

            var id = GetJsonString(requirement, "id");
            if (!string.IsNullOrWhiteSpace(id))
                yield return id;
        }
    }
}
