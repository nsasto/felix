using System.Text;
using System.Text.RegularExpressions;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    static bool _shellModeActive;
    const int TuiFooterBaseHeight = 4;
    const int TuiMaxTranscriptEntries = 48;
    const int TuiMaxTranscriptLinesPerEntry = 200;
    const int TuiMaxTranscriptCharsPerEntry = 16000;

    internal enum TuiCommandExecutionMode
    {
        Captured,
        Standalone
    }

    internal sealed record TuiCommandDefinition(string Name, string Description, string Usage, Func<string[], TuiCommandExecutionMode> ResolveExecutionMode, Func<string[], Task<TuiCommandResult>> ExecuteAsync);
    internal sealed record TuiSuggestion(string Value, string Description, bool IsCommand);
    internal sealed record TuiSuggestionWindow(int StartIndex, int Count);
    internal sealed record TuiCommandResult(bool ContinueRunning, Func<Task>? StandaloneAction = null)
    {
        public static TuiCommandResult Continue() => new(true);
        public static TuiCommandResult Exit() => new(false);
        public static TuiCommandResult Standalone(Func<Task> action) => new(true, action);
    }

    sealed class TuiShellState
    {
        public string Input { get; set; } = string.Empty;
        public List<TuiSuggestion> Suggestions { get; set; } = new();
        public int SelectedSuggestion { get; set; }
        public List<TuiTranscriptEntry> Transcript { get; } = new();
        public string FooterStatus { get; set; } = "Type / to browse commands";
        public bool IsExecuting { get; set; }
    }

    sealed record TuiTranscriptEntry(string Command, string Output, bool IsError = false);

    static async Task RunCopilotStyleTui(string felixPs1)
    {
        _shellModeActive = true;
        try
        {
            EnsureConsoleUnicodeRendering();
            AnsiConsole.Clear();
            var commands = BuildTuiCommands(felixPs1);
            var running = true;

            RenderTuiWelcomeCard();
            AnsiConsole.WriteLine();
            AnsiConsole.MarkupLine("[grey]Type [cyan]/[/] to open commands. Use [cyan]Esc[/] or [cyan]Backspace[/] on empty input to close suggestions.[/]");
            AnsiConsole.WriteLine();

            while (running)
            {
                var input = CaptureTuiInput(commands);
                if (string.IsNullOrWhiteSpace(input))
                    continue;

                AnsiConsole.MarkupLine($"[cyan]>[/] {input.EscapeMarkup()}");

                try
                {
                    running = await ExecuteTuiCommandInConsole(commands, input);
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

    static void EnsureConsoleUnicodeRendering()
    {
        try
        {
            if (Console.OutputEncoding.CodePage != Encoding.UTF8.CodePage)
                Console.OutputEncoding = Encoding.UTF8;
        }
        catch
        {
        }

        try
        {
            if (Console.InputEncoding.CodePage != Encoding.UTF8.CodePage)
                Console.InputEncoding = Encoding.UTF8;
        }
        catch
        {
        }
    }

    static void ClearIfStandalone()
    {
        if (!_shellModeActive)
            AnsiConsole.Clear();
    }

    static void RenderTuiWelcomeCard()
    {
        AnsiConsole.Write(CreateTuiWelcomePanel());
    }

    static Panel CreateTuiWelcomePanel()
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
            "███████╗███████╗██╗     ██╗██╗  ██╗",
            "██╔════╝██╔════╝██║     ██║╚██╗██╔╝",
            "█████╗  █████╗  ██║     ██║ ╚███╔╝ ",
            "██╔══╝  ██╔══╝  ██║     ██║ ██╔██╗ ",
            "██║     ███████╗███████╗██║██╔╝ ██╗",
            "╚═╝     ╚══════╝╚══════╝╚═╝╚═╝  ╚═╝"
        });

        var lines = new List<string>
        {
            string.Empty,
            $"[green]{wordmark.EscapeMarkup()}[/]",
            string.Empty,
            $"[grey]project[/] [white]{_felixProjectRoot.EscapeMarkup()}[/]",
            $"[grey]requirements[/] [white]{total}[/]  [grey]planned[/] [cyan]{statusCounts.GetValueOrDefault("planned", 0)}[/]  [grey]in progress[/] [yellow]{statusCounts.GetValueOrDefault("in_progress", 0)}[/]  [grey]done[/] [blue]{statusCounts.GetValueOrDefault("done", 0)}[/]  [grey]complete[/] [green]{statusCounts.GetValueOrDefault("complete", 0)}[/]  [grey]blocked[/] [red]{statusCounts.GetValueOrDefault("blocked", 0)}[/]",
            $"[grey]active agent[/] [white]{currentAgentLabel.EscapeMarkup()}[/]  [grey]configured agents[/] [white]{configuredAgents.Count}[/]"
        };

        return new Panel(string.Join(Environment.NewLine, lines))
        {
            Header = new PanelHeader("[grey]Felix TUI[/]", Justify.Left),
            Border = BoxBorder.Rounded,
            BorderStyle = Style.Parse("grey"),
            Expand = true,
            Padding = new Padding(1, 0, 1, 0)
        };
    }

    static List<TuiCommandDefinition> BuildTuiCommands(string felixPs1)
    {
        return new List<TuiCommandDefinition>
        {
            new("help", "Show shell help", "/help", _ => TuiCommandExecutionMode.Captured, async _ => { ShowHelp(); return TuiCommandResult.Continue(); }),
            new("version", "Show version information", "/version", _ => TuiCommandExecutionMode.Captured, async _ => { await ShowVersionUI(); return TuiCommandResult.Continue(); }),
            new("status", "Show requirement status overview", "/status", _ => TuiCommandExecutionMode.Captured, async _ => { await ShowStatusUI(felixPs1); return TuiCommandResult.Continue(); }),
            new("list", "List requirements", "/list [status] [--with-deps]", _ => TuiCommandExecutionMode.Captured, async args => { await ExecuteListCommand(felixPs1, args); return TuiCommandResult.Continue(); }),
            new("run-next", "Run next available requirement", "/run-next", _ => TuiCommandExecutionMode.Standalone, async _ => { await ExecuteFelixRichCommand(felixPs1, "Run Next Requirement", "run-next"); return TuiCommandResult.Continue(); }),
            new("run", "Run a planned requirement", "/run <requirement-id>", _ => TuiCommandExecutionMode.Standalone, async args => { if (args.Length == 0) { AnsiConsole.MarkupLine("[yellow]Usage:[/] /run <requirement-id>"); return TuiCommandResult.Continue(); } await ExecuteFelixRichCommand(felixPs1, "Run Requirement", "run", args[0]); return TuiCommandResult.Continue(); }),
            new("loop", "Run in continuous loop mode", "/loop [--max-iterations N]", _ => TuiCommandExecutionMode.Standalone, async args => { await ExecuteFelixRichCommand(felixPs1, "Continuous Loop", new[] { "loop" }.Concat(args).ToArray()); return TuiCommandResult.Continue(); }),
            new("validate", "Validate a completed requirement", "/validate <requirement-id>", _ => TuiCommandExecutionMode.Captured, async args => { if (args.Length == 0) { AnsiConsole.MarkupLine("[yellow]Usage:[/] /validate <requirement-id>"); return TuiCommandResult.Continue(); } await ShowValidateUI(felixPs1, args[0]); return TuiCommandResult.Continue(); }),
            new("deps", "Show dependency status", "/deps <requirement-id>|--incomplete [--tree] [--check]", _ => TuiCommandExecutionMode.Captured, async args => { await ExecuteDepsCommand(args); return TuiCommandResult.Continue(); }),
            new("procs", "Show or stop active sessions", "/procs [list|kill <target>|--all]", ResolveProcsExecutionMode, async args => { await ExecuteProcsCommand(args); return TuiCommandResult.Continue(); }),
            new("setup", "Run Felix setup", "/setup", _ => TuiCommandExecutionMode.Standalone, async _ => { await RunSetupInteractive(felixPs1); return TuiCommandResult.Continue(); }),
            new("context", "Run context command", "/context <subcommand>", ResolveContextExecutionMode, async args =>
            {
                if (args.Length > 0 && string.Equals(args[0], "show", StringComparison.OrdinalIgnoreCase))
                {
                    await ShowContextMarkdownUI();
                    return TuiCommandResult.Continue();
                }

                await ExecutePowerShell(felixPs1, new[] { "context" }.Concat(args).ToArray());
                return TuiCommandResult.Continue();
            }),
            new("spec-create", "Create a specification", "/spec-create <description>", _ => TuiCommandExecutionMode.Captured, async args => { if (args.Length == 0) { AnsiConsole.MarkupLine("[yellow]Usage:[/] /spec-create <description>"); return TuiCommandResult.Continue(); } await ExecutePowerShell(felixPs1, "spec", "create", string.Join(" ", args)); return TuiCommandResult.Continue(); }),
            new("spec-pull", "Pull specs from server", "/spec-pull", _ => TuiCommandExecutionMode.Captured, async _ => { await RunSpecPullUI(dryRun: false, delete: false, force: false); return TuiCommandResult.Continue(); }),
            new("spec-fix", "Fix spec alignment", "/spec-fix", _ => TuiCommandExecutionMode.Captured, async _ => { RunSpecFixUI(fixDuplicates: false); return TuiCommandResult.Continue(); }),
            new("agent-list", "Show configured agents", "/agent-list", _ => TuiCommandExecutionMode.Captured, async _ => { ShowAgentListUI(); return TuiCommandResult.Continue(); }),
            new("agent-current", "Show current agent", "/agent-current", _ => TuiCommandExecutionMode.Captured, async _ => { ShowCurrentAgentUI(); return TuiCommandResult.Continue(); }),
            new("quit", "Exit the TUI", "/quit", _ => TuiCommandExecutionMode.Captured, async _ => await Task.FromResult(TuiCommandResult.Exit())),
            new("exit", "Exit the TUI", "/exit", _ => TuiCommandExecutionMode.Captured, async _ => await Task.FromResult(TuiCommandResult.Exit())),
        };
    }

    internal static TuiCommandExecutionMode ResolveContextExecutionMode(string[] args)
    {
        if (args.Length > 0 && string.Equals(args[0], "show", StringComparison.OrdinalIgnoreCase))
            return TuiCommandExecutionMode.Captured;

        return TuiCommandExecutionMode.Captured;
    }

    internal static TuiCommandExecutionMode ResolveProcsExecutionMode(string[] args)
    {
        if (args.Length == 0)
            return TuiCommandExecutionMode.Captured;

        if (!string.Equals(args[0], "kill", StringComparison.OrdinalIgnoreCase))
            return TuiCommandExecutionMode.Captured;

        var hasTarget = args.Skip(1).Any(arg => !arg.StartsWith("--", StringComparison.Ordinal));
        var killAll = args.Skip(1).Any(arg => string.Equals(arg, "--all", StringComparison.OrdinalIgnoreCase));
        return hasTarget || killAll ? TuiCommandExecutionMode.Captured : TuiCommandExecutionMode.Standalone;
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

    static async Task ExecuteProcsCommand(string[] args)
    {
        if (args.Length == 0 || string.Equals(args[0], "list", StringComparison.OrdinalIgnoreCase))
        {
            await ShowProcsListUI();
            return;
        }

        if (string.Equals(args[0], "kill", StringComparison.OrdinalIgnoreCase))
        {
            var killAll = args.Skip(1).Any(arg => string.Equals(arg, "--all", StringComparison.OrdinalIgnoreCase));
            var target = args.Skip(1).FirstOrDefault(arg => !arg.StartsWith("--", StringComparison.Ordinal));
            KillProcessSessionsUI(target, killAll);
            return;
        }

        AnsiConsole.MarkupLine("[yellow]Usage:[/] /procs [list|kill <target>|--all]");
    }

    static async Task<TuiCommandResult> ExecuteTuiCommand(List<TuiCommandDefinition> commands, string input, TuiShellState state)
    {
        if (!input.StartsWith("/", StringComparison.Ordinal))
        {
            AppendTuiTranscript(state, input, "Commands must start with '/'. Type /help for available commands.", isError: true);
            return TuiCommandResult.Continue();
        }

        var tokens = TokenizeShellInput(input);
        if (tokens.Length == 0)
            return TuiCommandResult.Continue();

        var commandName = tokens[0].TrimStart('/');
        var command = commands.FirstOrDefault(candidate => string.Equals(candidate.Name, commandName, StringComparison.OrdinalIgnoreCase));
        if (command == null)
        {
            AppendTuiTranscript(state, input, $"Unknown command: {commandName}", isError: true);
            return TuiCommandResult.Continue();
        }

        var args = tokens.Skip(1).ToArray();
        var executionMode = command.ResolveExecutionMode(args);
        if (executionMode == TuiCommandExecutionMode.Standalone)
        {
            AppendTuiTranscript(state, input, "Launching command outside the retained shell for direct terminal control...");
            return TuiCommandResult.Standalone(async () => await command.ExecuteAsync(args));
        }

        TuiCommandResult? result = null;
        var output = await CaptureTuiCommandOutputAsync(async () =>
        {
            result = await command.ExecuteAsync(args);
        });

        result ??= TuiCommandResult.Continue();
        AppendTuiTranscript(state, input, output);
        return result;
    }

    static async Task<bool> ExecuteTuiCommandInConsole(List<TuiCommandDefinition> commands, string input)
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

        var args = tokens.Skip(1).ToArray();
        var executionMode = command.ResolveExecutionMode(args);

        if (executionMode == TuiCommandExecutionMode.Standalone)
        {
            var previousExitCode = Environment.ExitCode;
            try
            {
                var directResult = await command.ExecuteAsync(args);
                if (directResult.StandaloneAction != null)
                    await directResult.StandaloneAction();

                if (directResult.ContinueRunning)
                    AnsiConsole.MarkupLine($"[grey]{DescribeShellResume(Environment.ExitCode).EscapeMarkup()}[/]");

                return directResult.ContinueRunning;
            }
            finally
            {
                Environment.ExitCode = previousExitCode;
            }
        }

        TuiCommandResult? result = null;
        var output = await CaptureTuiCommandOutputAsync(async () =>
        {
            result = await command.ExecuteAsync(args);
        });

        result ??= TuiCommandResult.Continue();
        if (!string.IsNullOrWhiteSpace(output))
            Console.WriteLine(output);

        return result.ContinueRunning;
    }

    static string? CaptureTuiInput(List<TuiCommandDefinition> commands)
    {
        var buffer = new StringBuilder();
        var selectedIndex = 0;
        var previousLines = 0;
        var contentTop = GetSafeBufferTop(Console.CursorTop);
        var originTop = contentTop;

        while (true)
        {
            var suggestions = GetTuiSuggestions(commands, buffer.ToString());
            if (selectedIndex >= suggestions.Count)
                selectedIndex = suggestions.Count == 0 ? 0 : suggestions.Count - 1;

            previousLines = RenderPromptBlock(buffer.ToString(), suggestions, selectedIndex, contentTop, ref originTop, previousLines);
            var key = Console.ReadKey(intercept: true);

            if (key.Key == ConsoleKey.Escape)
            {
                ClearPromptBlock(originTop, previousLines);
                SafeSetCursorPosition(0, contentTop);
                return null;
            }

            if (key.Key == ConsoleKey.Enter)
            {
                var finalInput = ResolveFinalInput(buffer.ToString(), suggestions, selectedIndex);
                ClearPromptBlock(originTop, previousLines);
                SafeSetCursorPosition(0, contentTop);
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
                    SafeSetCursorPosition(0, contentTop);
                    return null;
                }

                buffer.Length -= 1;
                continue;
            }

            if (!char.IsControl(key.KeyChar))
            {
                buffer.Append(key.KeyChar);
                selectedIndex = 0;
            }
        }
    }

    static int RenderPromptBlock(string input, List<TuiSuggestion> suggestions, int selectedIndex, int contentTop, ref int originTop, int previousLines)
    {
        var width = Math.Max(40, Console.WindowWidth - 1);
        var innerWidth = Math.Max(10, width - 4);
        var promptRows = 3;

        var initialVisibleBottom = GetVisibleBottom();
        var initialVisibleTop = GetVisibleTop();
        var initialAvailableRows = Math.Max(1, initialVisibleBottom - initialVisibleTop + 1);
        var initialMaxSuggestionRows = Math.Max(0, initialAvailableRows - promptRows);
        var suggestionWindow = GetSuggestionWindow(suggestions.Count, selectedIndex, initialMaxSuggestionRows);
        var visibleSuggestions = suggestions.Skip(suggestionWindow.StartIndex).Take(suggestionWindow.Count).ToList();
        var commandColumnWidth = GetSuggestionCommandColumnWidth(visibleSuggestions);

        var lines = new List<string>();
        foreach (var suggestion in visibleSuggestions.Select((item, index) => new { item, index }))
        {
            var absoluteIndex = suggestionWindow.StartIndex + suggestion.index;
            var isSelected = absoluteIndex == selectedIndex;
            lines.AddRange(FormatSuggestionLines(suggestion.item, isSelected, width, commandColumnWidth));
        }

        lines.Add("╭" + new string('─', innerWidth + 2) + "╮");
        lines.Add("│ " + TruncatePad(input, innerWidth) + " │");
        lines.Add("╰" + new string('─', innerWidth + 2) + "╯");

        while (lines.Count < previousLines)
            lines.Add(new string(' ', width));

        EnsurePromptWindowVisible(contentTop, lines.Count);

        var visibleBottom = GetVisibleBottom();
        var visibleTop = GetVisibleTop();

        var pinnedOriginTop = GetPromptOriginTop(contentTop, promptRows, lines.Count - promptRows);
        if (previousLines > 0 && originTop != pinnedOriginTop)
            ClearPromptBlock(originTop, previousLines);

        originTop = pinnedOriginTop;
        var maxVisibleLines = Math.Max(1, visibleBottom - originTop + 1);
        if (lines.Count > maxVisibleLines)
            lines = lines.Take(maxVisibleLines).ToList();

        for (var index = 0; index < lines.Count; index++)
        {
            SafeSetCursorPosition(0, originTop + index);
            var isSelectedSuggestion = index < visibleSuggestions.Count && (suggestionWindow.StartIndex + index) == selectedIndex;
            WritePromptLine(lines[index].PadRight(width), isSelectedSuggestion);
        }

        var caretLeft = Math.Min(innerWidth + 2, input.Length + 2);
        var caretTop = GetSafeBufferTop(originTop + lines.Count - 2);
        SafeSetCursorPosition(caretLeft, caretTop);
        return lines.Count;
    }

    internal static TuiSuggestionWindow GetSuggestionWindow(int suggestionCount, int selectedIndex, int maxVisibleRows)
    {
        if (suggestionCount <= 0 || maxVisibleRows <= 0)
            return new TuiSuggestionWindow(0, 0);

        if (suggestionCount <= maxVisibleRows)
            return new TuiSuggestionWindow(0, suggestionCount);

        var clampedSelectedIndex = Math.Clamp(selectedIndex, 0, suggestionCount - 1);
        var startIndex = clampedSelectedIndex - (maxVisibleRows / 2);
        startIndex = Math.Max(0, startIndex);
        startIndex = Math.Min(startIndex, suggestionCount - maxVisibleRows);
        return new TuiSuggestionWindow(startIndex, maxVisibleRows);
    }

    static int GetSuggestionCommandColumnWidth(IReadOnlyList<TuiSuggestion> suggestions)
    {
        if (suggestions.Count == 0)
            return 16;

        var maxCommandLength = suggestions.Max(suggestion => suggestion.Value.Length);
        return Math.Clamp(maxCommandLength + 2, 14, 24);
    }

    static IEnumerable<string> FormatSuggestionLines(TuiSuggestion suggestion, bool isSelected, int width, int commandColumnWidth)
    {
        var indicator = isSelected ? ">" : " ";
        var commandText = suggestion.Value.PadRight(commandColumnWidth);
        var firstPrefix = $"{indicator} {commandText}";
        var continuationPrefix = $"  {new string(' ', commandColumnWidth)}";
        var descriptionWidth = Math.Max(10, width - firstPrefix.Length - 1);
        var wrappedDescription = WrapText(suggestion.Description, descriptionWidth).Take(2).ToList();

        if (wrappedDescription.Count == 0)
        {
            yield return TruncatePad(firstPrefix, width);
            yield break;
        }

        yield return TruncatePad($"{firstPrefix} {wrappedDescription[0]}", width);
        for (var index = 1; index < wrappedDescription.Count; index++)
            yield return TruncatePad($"{continuationPrefix} {wrappedDescription[index]}", width);
    }

    static IEnumerable<string> WrapText(string value, int width)
    {
        if (string.IsNullOrWhiteSpace(value))
            yield break;

        var words = value.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var currentLine = new StringBuilder();
        foreach (var word in words)
        {
            if (currentLine.Length == 0)
            {
                currentLine.Append(word);
                continue;
            }

            if (currentLine.Length + 1 + word.Length <= width)
            {
                currentLine.Append(' ');
                currentLine.Append(word);
                continue;
            }

            yield return currentLine.ToString();
            currentLine.Clear();

            if (word.Length <= width)
            {
                currentLine.Append(word);
                continue;
            }

            var remaining = word;
            while (remaining.Length > width)
            {
                yield return remaining[..width];
                remaining = remaining[width..];
            }

            currentLine.Append(remaining);
        }

        if (currentLine.Length > 0)
            yield return currentLine.ToString();
    }

    static void EnsurePromptWindowVisible(int contentTop, int requiredLines)
    {
        if (!OperatingSystem.IsWindows())
            return;

        try
        {
            var visibleBottom = GetVisibleBottom();
            var requiredBottom = contentTop + Math.Max(0, requiredLines - 1);
            if (requiredBottom <= visibleBottom)
                return;

            var maxWindowTop = Math.Max(0, Console.BufferHeight - Console.WindowHeight);
            var desiredWindowTop = Math.Max(0, requiredBottom - Console.WindowHeight + 1);
            Console.WindowTop = Math.Min(maxWindowTop, desiredWindowTop);
        }
        catch
        {
        }
    }

    static void ClearPromptBlock(int originTop, int lineCount)
    {
        var width = Math.Max(40, Console.WindowWidth - 1);
        originTop = GetSafeBufferTop(originTop);
        for (var index = 0; index < lineCount; index++)
        {
            SafeSetCursorPosition(0, originTop + index);
            Console.Write(new string(' ', width));
        }
    }

    static void WritePromptLine(string text, bool isSelectedSuggestion)
    {
        ConsoleColor? originalForeground = null;
        ConsoleColor? originalBackground = null;
        try
        {
            if (isSelectedSuggestion)
            {
                originalForeground = Console.ForegroundColor;
                originalBackground = Console.BackgroundColor;
                Console.ForegroundColor = ConsoleColor.Black;
                Console.BackgroundColor = ConsoleColor.Cyan;
            }

            Console.Write(text);
        }
        finally
        {
            if (originalBackground.HasValue)
                Console.BackgroundColor = originalBackground.Value;
            if (originalForeground.HasValue)
                Console.ForegroundColor = originalForeground.Value;
        }
    }

    static void SafeSetCursorPosition(int left, int top)
    {
        try
        {
            var safeLeft = Math.Clamp(left, 0, Math.Max(0, Console.BufferWidth - 1));
            var safeTop = GetSafeBufferTop(top);
            Console.SetCursorPosition(safeLeft, safeTop);
        }
        catch (ArgumentOutOfRangeException)
        {
            try
            {
                Console.SetCursorPosition(0, 0);
            }
            catch
            {
            }
        }
        catch (IOException)
        {
        }
    }

    static int GetSafeBufferTop(int requestedTop)
    {
        try
        {
            return Math.Clamp(requestedTop, 0, Math.Max(0, Console.BufferHeight - 1));
        }
        catch
        {
            return 0;
        }
    }

    static int GetPromptOriginTop(int contentTop, int promptRows, int suggestionRows)
    {
        try
        {
            var visibleTop = GetVisibleTop();
            var visibleBottom = GetVisibleBottom();
            var promptTop = Math.Max(visibleTop, visibleBottom - Math.Max(1, promptRows) + 1);
            var suggestionTop = Math.Max(visibleTop, promptTop - Math.Max(0, suggestionRows));
            return Math.Max(GetSafeBufferTop(contentTop), suggestionTop);
        }
        catch
        {
            return GetSafeBufferTop(Console.CursorTop);
        }
    }

    static int GetVisibleBottom()
    {
        try
        {
            return Math.Min(Console.BufferHeight - 1, Console.WindowTop + Console.WindowHeight - 1);
        }
        catch
        {
            return Math.Max(0, Console.BufferHeight - 1);
        }
    }

    static int GetVisibleTop()
    {
        try
        {
            return Console.WindowTop;
        }
        catch
        {
            return 0;
        }
    }

    static string TruncatePad(string value, int width)
    {
        if (value.Length > width)
            return value[..Math.Max(0, width - 3)] + "...";

        return value.PadRight(width);
    }

    internal static string[] TokenizeShellInput(string input)
    {
        return Regex.Matches(input, "\"([^\"]*)\"|(\\S+)")
            .Select(match => match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .ToArray();
    }

    static Layout CreateTuiLayout()
    {
        return new Layout("Root")
            .SplitRows(
                new Layout("Body").Ratio(1),
                new Layout("Footer").Size(TuiFooterBaseHeight));
    }

    static void RefreshTuiLayout(Layout layout, TuiShellState state)
    {
        var footerHeight = GetTuiFooterHeight(state);
        layout["Footer"].Size(footerHeight);
        layout["Body"].Update(CreateTuiContent(state));
        layout["Footer"].Update(CreateTuiComposerPanel(state));
    }

    static bool TryApplyTuiKey(List<TuiCommandDefinition> commands, TuiShellState state, ConsoleKeyInfo key)
    {
        if (key.Key == ConsoleKey.Enter)
            return true;

        if (key.Key == ConsoleKey.Escape)
        {
            state.Input = string.Empty;
            state.Suggestions = new List<TuiSuggestion>();
            state.SelectedSuggestion = 0;
            state.FooterStatus = "Suggestions cleared";
            return false;
        }

        if (key.Key == ConsoleKey.UpArrow)
        {
            if (state.Suggestions.Count > 0)
                state.SelectedSuggestion = (state.SelectedSuggestion - 1 + state.Suggestions.Count) % state.Suggestions.Count;
            return false;
        }

        if (key.Key == ConsoleKey.DownArrow)
        {
            if (state.Suggestions.Count > 0)
                state.SelectedSuggestion = (state.SelectedSuggestion + 1) % state.Suggestions.Count;
            return false;
        }

        if (key.Key == ConsoleKey.Backspace)
        {
            if (state.Input.Length == 0)
            {
                state.Suggestions = new List<TuiSuggestion>();
                state.SelectedSuggestion = 0;
                state.FooterStatus = "Type / to browse commands";
                return false;
            }

            state.Input = state.Input[..^1];
            UpdateTuiSuggestions(commands, state);
            return false;
        }

        if (!char.IsControl(key.KeyChar))
        {
            state.Input += key.KeyChar;
            UpdateTuiSuggestions(commands, state);
            return false;
        }

        return false;
    }

    static void UpdateTuiSuggestions(List<TuiCommandDefinition> commands, TuiShellState state)
    {
        state.Suggestions = GetTuiSuggestions(commands, state.Input);
        state.SelectedSuggestion = state.Suggestions.Count == 0
            ? 0
            : Math.Clamp(state.SelectedSuggestion, 0, state.Suggestions.Count - 1);
        state.FooterStatus = GetFooterStatus(state.Input, state.Suggestions.Count > 0);
    }

    static Spectre.Console.Rendering.IRenderable CreateTuiContent(TuiShellState state)
    {
        if (state.Transcript.Count == 0)
        {
            return new Rows(
                CreateTuiWelcomePanel(),
                new Markup("[grey]Type [cyan]/[/] to open commands. Use [cyan]Esc[/] or [cyan]Backspace[/] on empty input to close suggestions.[/]"));
        }

        var transcriptEntries = GetVisibleTranscriptEntries(state);
        return new Padder(
            new Rows(transcriptEntries.Select(CreateTuiTranscriptEntryRenderable)),
            new Padding(0, 0, 0, 1));
    }

    static Panel CreateTuiComposerPanel(TuiShellState state)
    {
        var lines = new List<string>
        {
            $"[cyan]>[/] {(string.IsNullOrWhiteSpace(state.Input) ? "[grey]type a slash command[/]" : state.Input.EscapeMarkup())}",
            $"[grey]{state.FooterStatus.EscapeMarkup()}[/]"
        };

        foreach (var suggestion in state.Suggestions.Select((suggestion, index) => new { suggestion, index }))
        {
            var description = $"{suggestion.suggestion.Value}  {suggestion.suggestion.Description}".EscapeMarkup();
            lines.Add(suggestion.index == state.SelectedSuggestion
                ? $"[black on cyan] {description} [/]"
                : $"[grey]  {description}[/]");
        }

        return new Panel(new Markup(string.Join(Environment.NewLine, lines)))
        {
            Header = new PanelHeader(state.IsExecuting ? "[yellow]Running[/]" : "[grey]Command[/]", Justify.Left),
            Border = BoxBorder.Rounded,
            BorderStyle = Style.Parse(state.IsExecuting ? "yellow" : "grey"),
            Expand = true,
            Padding = new Padding(1, 0, 1, 0)
        };
    }

    static int GetTuiFooterHeight(TuiShellState state)
    {
        return TuiFooterBaseHeight + state.Suggestions.Count;
    }

    static IReadOnlyList<TuiTranscriptEntry> GetVisibleTranscriptEntries(TuiShellState state)
    {
        if (state.Transcript.Count <= TuiMaxTranscriptEntries)
            return state.Transcript;

        return state.Transcript[^TuiMaxTranscriptEntries..];
    }

    static Spectre.Console.Rendering.IRenderable CreateTuiTranscriptEntryRenderable(TuiTranscriptEntry entry)
    {
        var output = string.IsNullOrWhiteSpace(entry.Output) ? "(no output)" : entry.Output.TrimEnd();
        var commandColor = entry.IsError ? "red" : "cyan";
        return new Padder(
            new Rows(
                new Markup($"[{commandColor}]>[/] {entry.Command.EscapeMarkup()}"),
                new Text(output),
                Text.Empty),
            new Padding(0, 0, 0, 1));
    }

    static void AppendTuiTranscript(TuiShellState state, string command, string? output, bool isError = false)
    {
        state.Transcript.Add(new TuiTranscriptEntry(command, NormalizeTuiOutput(output), isError));
    }

    internal static string NormalizeTuiOutput(string? output)
    {
        if (string.IsNullOrWhiteSpace(output))
            return string.Empty;

        var normalized = output
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n')
            .Replace("\t", "    ", StringComparison.Ordinal)
            .Trim('\n');

        while (normalized.Contains("\n\n\n", StringComparison.Ordinal))
            normalized = normalized.Replace("\n\n\n", "\n\n", StringComparison.Ordinal);

        normalized = string.Join("\n", normalized
            .Split('\n')
            .Select(line => line.TrimEnd()));

        var lines = normalized.Split('\n');
        if (lines.Length > TuiMaxTranscriptLinesPerEntry)
        {
            normalized = string.Join("\n", lines.Take(TuiMaxTranscriptLinesPerEntry))
                + $"\n\n... output truncated ({lines.Length - TuiMaxTranscriptLinesPerEntry} more lines)";
        }

        if (normalized.Length > TuiMaxTranscriptCharsPerEntry)
        {
            normalized = normalized[..TuiMaxTranscriptCharsPerEntry]
                + "\n\n... output truncated (character limit reached)";
        }

        return normalized;
    }

    internal static string GetFooterStatus(string input, bool hasSuggestions)
    {
        if (hasSuggestions)
            return "Use arrows to select, Enter to accept";

        if (string.IsNullOrWhiteSpace(input))
            return "Type / to browse commands";

        if (!input.StartsWith("/", StringComparison.Ordinal))
            return "Commands start with /";

        return "Press Enter to run command";
    }

    internal static string DescribeShellResume(int exitCode)
    {
        return exitCode == 0
            ? "Returned to shell. Command completed successfully."
            : $"Returned to shell. Command exited with code {exitCode}.";
    }

    static async Task<string> CaptureTuiCommandOutputAsync(Func<Task> action)
    {
        var originalConsole = AnsiConsole.Console;
        var originalOut = Console.Out;
        var originalError = Console.Error;

        using var writer = new StringWriter();
        var captureConsole = AnsiConsole.Create(new AnsiConsoleSettings
        {
            Ansi = AnsiSupport.No,
            ColorSystem = ColorSystemSupport.NoColors,
            Interactive = InteractionSupport.No,
            Out = new AnsiConsoleOutput(writer)
        });

        try
        {
            AnsiConsole.Console = captureConsole;
            Console.SetOut(writer);
            Console.SetError(writer);
            await action();
            await writer.FlushAsync();
            return NormalizeTuiOutput(writer.ToString());
        }
        finally
        {
            Console.SetOut(originalOut);
            Console.SetError(originalError);
            AnsiConsole.Console = originalConsole;
        }
    }

    static (int Width, int Height) GetTuiWindowSize()
    {
        try
        {
            return (Console.WindowWidth, Console.WindowHeight);
        }
        catch
        {
            return (0, 0);
        }
    }

    static bool IsConsoleKeyAvailable()
    {
        try
        {
            return Console.KeyAvailable;
        }
        catch
        {
            return false;
        }
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
