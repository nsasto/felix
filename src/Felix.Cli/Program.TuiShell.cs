using System.CommandLine;
using System.Text;
using System.Text.RegularExpressions;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    static bool _shellModeActive;
    const int TuiBaseFooterHeight = 4;
    const int TuiMaxTranscriptEntries = 100;
    const int TuiMaxTranscriptLinesPerEntry = 120;
    const int TuiMaxTranscriptCharsPerEntry = 12000;

    static readonly HashSet<string> TuiExcludedSlashPaths = new(StringComparer.OrdinalIgnoreCase)
    {
        "tui",
        "dashboard"
    };

    static readonly HashSet<string> TuiSupportedSlashPaths = new(StringComparer.OrdinalIgnoreCase)
    {
        "help",
        "version",
        "status",
        "list",
        "run",
        "run-next",
        "loop",
        "setup",
        "validate",
        "deps",
        "context",
        "spec list",
        "spec fix",
        "spec status",
        "spec pull",
        "spec push",
        "agent list",
        "agent current",
        "agent install-help",
        "procs list"
    };

    static readonly HashSet<string> TuiCommandsThatStageBeforeExecution = new(StringComparer.OrdinalIgnoreCase)
    {
        "run",
        "run-next",
        "loop"
    };

    static readonly Dictionary<string, string[]> TuiCommonFlags = new(StringComparer.OrdinalIgnoreCase)
    {
        ["run"] = new[] { "--verbose", "--debug", "--quiet", "--sync", "--format" },
        ["run-next"] = new[] { "--sync", "--verbose", "--debug", "--format" },
        ["loop"] = new[] { "--max-iterations", "--format" },
        ["spec pull"] = new[] { "--dry-run", "--delete", "--force" },
        ["spec push"] = new[] { "--dry-run", "--force" },
        ["update"] = new[] { "--check", "--yes", "-y" }
    };

    internal enum TuiCommandExecutionMode
    {
        Captured,
        Standalone
    }

    internal enum TuiCommandExecutionBackend
    {
        Auto,
        CSharp,
        PowerShell
    }

    internal enum TuiLayoutMode
    {
        Normal,
        Compact,
        Minimal
    }

    internal sealed record TuiCommandCatalogEntry(
        string SlashPath,
        string Description,
        string Usage,
        string[] PathTokens,
        string[] OptionAliases,
        string[] ArgumentNames,
        int MinimumPositionalArguments,
        TuiCommandExecutionMode ExecutionMode,
        TuiCommandExecutionBackend ExecutionBackend);

    internal sealed record TuiSuggestion(string Value, string Description, bool IsCommand);

    sealed class TuiHeaderSnapshot
    {
        public int TotalRequirements { get; init; }
        public IReadOnlyDictionary<string, int> StatusCounts { get; init; } = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        public string CurrentAgentLabel { get; init; } = "not set";
        public int ConfiguredAgents { get; init; }
        public string VersionLabel { get; init; } = "unknown";
    }

    sealed class TuiShellState
    {
        public string Input { get; set; } = string.Empty;
        public List<TuiSuggestion> Suggestions { get; set; } = new();
        public int SelectedSuggestion { get; set; } = -1;
        public List<TuiTranscriptEntry> Transcript { get; } = new();
        public int TranscriptScrollOffset { get; set; }
        public string FooterStatus { get; set; } = "Type / to browse commands. Tab accepts suggestions.";
        public bool IsExecuting { get; set; }
        public bool IsSuspended { get; set; }
        public bool NeedsFullClear { get; set; } = true;
        public TuiLayoutMode LayoutMode { get; set; } = TuiLayoutMode.Normal;
        public (int Width, int Height) LastWindowSize { get; set; }
        public string? ResumeMessage { get; set; }
        public string? PendingStandaloneInput { get; set; }
        public string[]? PendingStandaloneArgs { get; set; }
        public TuiHeaderSnapshot Header { get; set; } = LoadTuiHeaderSnapshot();
        public bool IsBodyDirty { get; set; } = true;
        public int LastRenderedFooterHeight { get; set; } = -1;
        public int LastRenderedFooterTop { get; set; } = -1;
    }

    sealed record TuiTranscriptEntry(string Command, string Output, bool IsError = false);
    sealed record TuiTranscriptRenderLine(string Text, bool IsCommand, bool IsError);

    internal sealed record TuiExecutionResult(bool ContinueRunning, string ResolvedInput, string[]? StandaloneArgs = null);

    static async Task RunCopilotStyleTui(string felixPs1)
    {
        _shellModeActive = true;
        try
        {
            EnsureConsoleUnicodeRendering();
            var rootCommand = CreateRootCommand(felixPs1);
            var catalog = BuildTuiCommandCatalog(rootCommand);
            var state = new TuiShellState();
            UpdateTuiWindowState(state);
            UpdateTuiSuggestions(catalog, state);

            var running = true;
            while (running)
            {
                var layout = CreateTuiLayout();
                state.IsSuspended = false;
                state.Header = LoadTuiHeaderSnapshot();
                state.IsBodyDirty = true;
                UpdateTuiSuggestions(catalog, state);

                RenderTuiShell(layout, state);

                while (running && !state.IsSuspended)
                {
                    if (UpdateTuiWindowState(state))
                        RenderTuiShell(layout, state);

                    if (!IsConsoleKeyAvailable())
                    {
                        await Task.Delay(30);
                        continue;
                    }

                    var key = Console.ReadKey(intercept: true);
                    if (!TryApplyTuiKey(catalog, state, key))
                    {
                        RenderTuiShell(layout, state);
                        continue;
                    }

                    var rawInput = state.Input;
                    var finalInput = NormalizeTuiInput(rawInput);
                    state.Input = string.Empty;
                    state.SelectedSuggestion = -1;
                    UpdateTuiSuggestions(catalog, state);

                    if (string.IsNullOrWhiteSpace(finalInput))
                    {
                        RenderTuiShell(layout, state);
                        continue;
                    }

                    if (ShouldStageCommandBeforeExecution(catalog, finalInput))
                    {
                        state.Input = EnsureCommandHasTrailingSpace(finalInput);
                        UpdateTuiSuggestions(catalog, state);
                        RenderTuiShell(layout, state);
                        continue;
                    }

                    if (!IsTuiInputReadyToExecute(catalog, finalInput))
                    {
                        state.Input = EnsureCommandHasTrailingSpace(finalInput);
                        UpdateTuiSuggestions(catalog, state);
                        RenderTuiShell(layout, state);
                        continue;
                    }

                    state.IsExecuting = true;
                    RenderTuiShell(layout, state);

                    var result = await ExecuteTuiCommand(felixPs1, rootCommand, catalog, finalInput, state);
                    running = result.ContinueRunning;
                    state.IsExecuting = false;
                    if (result.StandaloneArgs != null)
                    {
                        state.IsSuspended = true;
                        state.PendingStandaloneInput = result.ResolvedInput;
                        state.PendingStandaloneArgs = result.StandaloneArgs;
                    }

                    UpdateTuiSuggestions(catalog, state);
                    RenderTuiShell(layout, state);
                }

                if (!running || state.PendingStandaloneArgs == null)
                    continue;

                await ExecuteStandaloneTuiCommand(felixPs1, rootCommand, catalog, state);
            }
        }
        finally
        {
            _shellModeActive = false;
        }
    }

    static void RenderTuiShell(Layout layout, TuiShellState state)
    {
        var footerHeight = GetTuiFooterHeight(state);
        var requiresFullLayoutRender = state.NeedsFullClear
            || state.IsBodyDirty
            || state.LastRenderedFooterHeight != footerHeight;

        if (requiresFullLayoutRender)
        {
            if (state.NeedsFullClear)
            {
                AnsiConsole.Clear();
                state.NeedsFullClear = false;
            }
            else
            {
                var footerTop = Math.Max(0, state.LastWindowSize.Height - footerHeight);
                ClearTuiRegion(0, footerTop);
                TryResetTuiCursorToOrigin();
            }

            RefreshTuiLayout(layout, state);
            AnsiConsole.Write(layout);
            RenderTuiFooterOnly(state);
            state.IsBodyDirty = false;
            state.LastRenderedFooterHeight = footerHeight;
            state.LastRenderedFooterTop = Math.Max(0, state.LastWindowSize.Height - footerHeight);
        }
        else
        {
            RenderTuiFooterOnly(state);
        }
    }

    static void TryResetTuiCursorToOrigin()
    {
        try
        {
            Console.SetCursorPosition(0, 0);
        }
        catch
        {
        }
    }

    static void RenderTuiFooterOnly(TuiShellState state)
    {
        var footerHeight = GetTuiFooterHeight(state);
        var footerTop = Math.Max(0, state.LastWindowSize.Height - footerHeight);
        var clearStart = state.LastRenderedFooterTop >= 0
            ? Math.Min(state.LastRenderedFooterTop, footerTop)
            : footerTop;
        ClearTuiRegion(clearStart, state.LastWindowSize.Height);

        try
        {
            Console.SetCursorPosition(0, footerTop);
        }
        catch
        {
        }

        WritePlainFooter(state, footerTop);
        state.LastRenderedFooterHeight = footerHeight;
        state.LastRenderedFooterTop = footerTop;
    }

    static void WritePlainFooter(TuiShellState state, int footerTop)
    {
        var width = Math.Max(20, state.LastWindowSize.Width);
        var originalForeground = Console.ForegroundColor;
        var originalBackground = Console.BackgroundColor;
        var lines = BuildPlainFooterLines(state, width);
        for (var index = 0; index < lines.Count; index++)
        {
            try
            {
                Console.SetCursorPosition(0, footerTop + index);
                Console.ForegroundColor = lines[index].Foreground;
                Console.BackgroundColor = lines[index].Background;
                Console.Write(lines[index].Text.PadRight(width));
            }
            catch
            {
                Console.ForegroundColor = originalForeground;
                Console.BackgroundColor = originalBackground;
                return;
            }
        }

        Console.ForegroundColor = originalForeground;
        Console.BackgroundColor = originalBackground;
    }

    sealed record PlainFooterLine(string Text, ConsoleColor Foreground, ConsoleColor Background)
    {
        public static implicit operator PlainFooterLine(string text) => new(NormalizeFooterGlyphs(text), ConsoleColor.DarkGray, ConsoleColor.DarkBlue);
    }

    static List<PlainFooterLine> BuildPlainFooterLines(TuiShellState state, int width)
    {
        var visibleSuggestions = GetVisibleSuggestions(state).ToList();
        var startIndex = GetVisibleSuggestionStartIndex(state);
        var safeWidth = Math.Max(10, width);
        var innerWidth = Math.Max(2, safeWidth - 2);
        var title = state.IsExecuting ? "Command [running]" : "Command";
        var topLine = BuildFooterBorderLine(title, safeWidth);
        var contentLines = new List<PlainFooterLine>
        {
            CreateFooterContentLine($"> {(string.IsNullOrWhiteSpace(state.Input) ? "type a slash command" : state.Input)}", innerWidth, ConsoleColor.Gray, ConsoleColor.DarkBlue),
            CreateFooterContentLine(state.FooterStatus, innerWidth, ConsoleColor.DarkGray, ConsoleColor.DarkBlue)
        };

        foreach (var suggestion in visibleSuggestions.Select((item, index) => new { item, index }))
        {
            var description = state.LayoutMode == TuiLayoutMode.Minimal
                ? suggestion.item.Value
                : $"{suggestion.item.Value}  {TruncateText(suggestion.item.Description, 70)}";
            var isSelected = (startIndex + suggestion.index) == state.SelectedSuggestion;
            var prefix = isSelected ? "> " : "  ";
            contentLines.Add(CreateFooterContentLine(
                prefix + description,
                innerWidth,
                isSelected ? ConsoleColor.Black : ConsoleColor.Gray,
                isSelected ? ConsoleColor.Cyan : ConsoleColor.DarkBlue));
        }

        while (contentLines.Count < TuiBaseFooterHeight + visibleSuggestions.Count - 2)
            contentLines.Add(CreateFooterContentLine(string.Empty, innerWidth, ConsoleColor.Gray, ConsoleColor.DarkBlue));

        var lines = new List<PlainFooterLine> { new(topLine, ConsoleColor.DarkGray, ConsoleColor.DarkBlue) };
        lines.AddRange(contentLines);
        lines.Add($"╰{new string('─', innerWidth)}╯");
        return lines;
    }

    static string BuildFooterBorderLine(string title, int width)
    {
        var safeWidth = Math.Max(10, width);
        var innerWidth = Math.Max(2, safeWidth - 2);
        var titleText = $"─{title}";
        if (titleText.Length > innerWidth)
            titleText = TruncatePlainText(titleText, innerWidth);

        return $"╭{titleText}{new string('─', Math.Max(0, innerWidth - titleText.Length))}╮";
    }

    static string WrapFooterContentLine(string content, int innerWidth)
    {
        var clipped = TruncatePlainText(content, innerWidth);
        return $"{'\u2502'}{clipped.PadRight(innerWidth)}{'\u2502'}";
    }

    static void ClearTuiRegion(int startRow, int endExclusiveRow)
    {
        var width = Math.Max(0, GetTuiWindowSize().Width);
        if (width == 0 || endExclusiveRow <= startRow)
            return;

        var blankLine = new string(' ', width);
        for (var row = startRow; row < endExclusiveRow; row++)
        {
            try
            {
                Console.SetCursorPosition(0, row);
                Console.Write(blankLine);
            }
            catch
            {
                return;
            }
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

    static TuiHeaderSnapshot LoadTuiHeaderSnapshot()
    {
        var requirements = ParseRequirementsJson(ReadRequirementsJson()) ?? new List<System.Text.Json.JsonElement>();
        var statusCounts = requirements
            .GroupBy(req => GetJsonString(req, "status") ?? "unknown", StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.Count(), StringComparer.OrdinalIgnoreCase);

        var configuredAgents = ReadConfiguredAgents() ?? new List<ConfiguredAgent>();
        var currentAgent = configuredAgents.FirstOrDefault(agent => agent.IsCurrent);
        var currentAgentLabel = currentAgent == null
            ? "not set"
            : $"{currentAgent.Name} ({currentAgent.ModelDisplay})";
        var versionLabel = GetInstalledVersion(_felixInstallDir)
            ?? typeof(Program).Assembly.GetName().Version?.ToString()
            ?? "unknown";

        return new TuiHeaderSnapshot
        {
            TotalRequirements = requirements.Count,
            StatusCounts = statusCounts,
            CurrentAgentLabel = currentAgentLabel,
            ConfiguredAgents = configuredAgents.Count,
            VersionLabel = versionLabel
        };
    }

    static Panel CreateTuiWelcomePanel(TuiShellState state)
    {
        var header = state.Header;
        var lines = new List<string>();
        if (state.LayoutMode == TuiLayoutMode.Minimal)
        {
            lines.Add($"[grey]project[/] [white]{_felixProjectRoot.EscapeMarkup()}[/]");
            lines.Add($"[grey]agent[/] [white]{header.CurrentAgentLabel.EscapeMarkup()}[/]");
            lines.Add($"[grey]version[/] [white]{header.VersionLabel.EscapeMarkup()}[/]");
        }
        else
        {
            lines.Add($"[green]{GetFelixWordmark(state.LayoutMode).EscapeMarkup()}[/]");
            lines.Add(string.Empty);
            lines.Add($"[grey]project[/] [white]{_felixProjectRoot.EscapeMarkup()}[/]");
            lines.Add($"[grey]requirements[/] [white]{header.TotalRequirements}[/]  [grey]planned[/] [cyan]{header.StatusCounts.GetValueOrDefault("planned", 0)}[/]  [grey]in progress[/] [yellow]{header.StatusCounts.GetValueOrDefault("in_progress", 0)}[/]  [grey]done[/] [blue]{header.StatusCounts.GetValueOrDefault("done", 0)}[/]  [grey]complete[/] [green]{header.StatusCounts.GetValueOrDefault("complete", 0)}[/]  [grey]blocked[/] [red]{header.StatusCounts.GetValueOrDefault("blocked", 0)}[/]");
            lines.Add($"[grey]active agent[/] [white]{header.CurrentAgentLabel.EscapeMarkup()}[/]  [grey]configured agents[/] [white]{header.ConfiguredAgents}[/]");
            lines.Add($"[grey]version[/] [white]{header.VersionLabel.EscapeMarkup()}[/]");
        }

        return new Panel(new Markup(string.Join(Environment.NewLine, lines)))
        {
            Header = new PanelHeader("[grey]Felix[/]", Justify.Left),
            Border = BoxBorder.Rounded,
            BorderStyle = Style.Parse("grey"),
            Expand = true,
            Padding = new Padding(1, 0, 1, 0)
        };
    }

    static Layout CreateTuiLayout()
    {
        return new Layout("Root")
            .SplitRows(
                new Layout("Body").Ratio(1),
                new Layout("Footer").Size(TuiBaseFooterHeight));
    }

    static void RefreshTuiLayout(Layout layout, TuiShellState state)
    {
        layout["Footer"].Size(GetTuiFooterHeight(state));
        layout["Body"].Update(CreateTuiContent(state));
        layout["Footer"].Update(Text.Empty);
    }

    static bool TryApplyTuiKey(IReadOnlyList<TuiCommandCatalogEntry> catalog, TuiShellState state, ConsoleKeyInfo key)
    {
        if (key.Key == ConsoleKey.Enter)
            return true;

        if (key.Key == ConsoleKey.Tab)
        {
            if (state.Suggestions.Count == 0)
                return false;

            var acceptedInput = AcceptSelectedSuggestionIntoInput(catalog, state.Input, state.Suggestions, state.SelectedSuggestion);
            if (!string.Equals(acceptedInput, state.Input, StringComparison.Ordinal))
            {
                state.Input = acceptedInput;
                UpdateTuiSuggestions(catalog, state);
            }

            return false;
        }

        if (key.Key == ConsoleKey.Escape)
        {
            state.Input = string.Empty;
            state.Suggestions = new List<TuiSuggestion>();
            state.SelectedSuggestion = -1;
            state.FooterStatus = "Suggestions cleared";
            return false;
        }

        if (key.Key == ConsoleKey.PageUp)
        {
            ScrollTranscript(state, GetTranscriptPageSize(state));
            state.IsBodyDirty = true;
            return false;
        }

        if (key.Key == ConsoleKey.PageDown)
        {
            ScrollTranscript(state, -GetTranscriptPageSize(state));
            state.IsBodyDirty = true;
            return false;
        }

        if (key.Key == ConsoleKey.Home)
        {
            state.TranscriptScrollOffset = GetMaxTranscriptScrollOffset(state);
            state.IsBodyDirty = true;
            return false;
        }

        if (key.Key == ConsoleKey.End)
        {
            state.TranscriptScrollOffset = 0;
            state.IsBodyDirty = true;
            return false;
        }

        if (key.Key == ConsoleKey.UpArrow)
        {
            if (state.Suggestions.Count > 0)
                SelectSuggestionIntoInput(catalog, state, state.SelectedSuggestion < 0 ? state.Suggestions.Count - 1 : (state.SelectedSuggestion - 1 + state.Suggestions.Count) % state.Suggestions.Count);
            else
            {
                ScrollTranscript(state, 1);
                state.IsBodyDirty = true;
            }
            return false;
        }

        if (key.Key == ConsoleKey.DownArrow)
        {
            if (state.Suggestions.Count > 0)
                SelectSuggestionIntoInput(catalog, state, state.SelectedSuggestion < 0 ? 0 : (state.SelectedSuggestion + 1) % state.Suggestions.Count);
            else
            {
                ScrollTranscript(state, -1);
                state.IsBodyDirty = true;
            }
            return false;
        }

        if (key.Key == ConsoleKey.Backspace)
        {
            if (state.Input.Length == 0)
            {
                state.Suggestions = new List<TuiSuggestion>();
                state.SelectedSuggestion = -1;
                state.FooterStatus = "Type / to browse commands. Use arrows to populate suggestions.";
                return false;
            }

            state.Input = state.Input[..^1];
            UpdateTuiSuggestions(catalog, state);
            return false;
        }

        if (!char.IsControl(key.KeyChar))
        {
            state.Input += key.KeyChar;
            UpdateTuiSuggestions(catalog, state);
            return false;
        }

        return false;
    }

    static void SelectSuggestionIntoInput(IReadOnlyList<TuiCommandCatalogEntry> catalog, TuiShellState state, int selectedIndex)
    {
        if (state.Suggestions.Count == 0)
            return;

        state.SelectedSuggestion = Math.Clamp(selectedIndex, 0, state.Suggestions.Count - 1);
        var acceptedInput = AcceptSelectedSuggestionIntoInput(catalog, state.Input, state.Suggestions, state.SelectedSuggestion);
        if (!string.Equals(acceptedInput, state.Input, StringComparison.Ordinal))
            state.Input = acceptedInput;

        state.FooterStatus = GetFooterStatus(state.Input, state.Suggestions.Count > 0);
    }

    static void UpdateTuiSuggestions(IReadOnlyList<TuiCommandCatalogEntry> catalog, TuiShellState state)
    {
        state.Suggestions = GetTuiSuggestions(catalog, state.Input);
        state.SelectedSuggestion = -1;
        state.FooterStatus = GetFooterStatus(state.Input, state.Suggestions.Count > 0);
    }

    static Spectre.Console.Rendering.IRenderable CreateTuiContent(TuiShellState state)
    {
        var rows = new List<Spectre.Console.Rendering.IRenderable>();

        if (state.Transcript.Count == 0)
        {
            if (state.LayoutMode != TuiLayoutMode.Minimal)
                rows.Add(CreateTuiWelcomePanel(state));
            rows.Add(new Markup("[grey]Type [cyan]/[/] to browse the full CLI surface. Use the arrow keys to populate the textbox and [cyan]Esc[/] to clear suggestions.[/]"));
            rows.Add(new Markup("[grey]Captured commands stay in the shell. Interactive commands suspend the shell and resume when they finish.[/]"));
            return new Padder(new Rows(rows), new Padding(0, 1, 0, 0));
        }

        var visibleLines = GetVisibleTranscriptLines(state);
        rows.AddRange(visibleLines.Select(CreateTuiTranscriptLineRenderable));
        return new Padder(new Rows(rows), new Padding(0, 0, 0, 1));
    }

    static int GetTuiFooterHeight(TuiShellState state)
    {
        return TuiBaseFooterHeight + GetVisibleSuggestions(state).Count();
    }

    static int GetVisibleSuggestionStartIndex(TuiShellState state)
    {
        var maxSuggestions = GetSuggestionLimit(state.LayoutMode);
        if (state.Suggestions.Count <= maxSuggestions)
            return 0;

        if (state.SelectedSuggestion < 0)
            return 0;

        return Math.Clamp(state.SelectedSuggestion - (maxSuggestions / 2), 0, Math.Max(0, state.Suggestions.Count - maxSuggestions));
    }

    static IEnumerable<TuiSuggestion> GetVisibleSuggestions(TuiShellState state)
    {
        var maxSuggestions = GetSuggestionLimit(state.LayoutMode);
        if (state.Suggestions.Count <= maxSuggestions)
            return state.Suggestions;

        var start = GetVisibleSuggestionStartIndex(state);
        return state.Suggestions.Skip(start).Take(maxSuggestions);
    }

    internal static int GetSuggestionLimit(TuiLayoutMode layoutMode)
    {
        return layoutMode switch
        {
            TuiLayoutMode.Minimal => 1,
            TuiLayoutMode.Compact => 4,
            _ => 6
        };
    }

    static int GetTranscriptPageSize(TuiShellState state)
    {
        var windowHeight = state.LastWindowSize.Height <= 0 ? 0 : state.LastWindowSize.Height;
        var availableRows = Math.Max(4, windowHeight - GetTuiFooterHeight(state) - 1);

        return state.LayoutMode switch
        {
            TuiLayoutMode.Minimal => Math.Max(4, availableRows),
            TuiLayoutMode.Compact => Math.Max(8, availableRows),
            _ => Math.Max(12, availableRows)
        };
    }

    static int GetMaxTranscriptScrollOffset(TuiShellState state)
    {
        return Math.Max(0, BuildTranscriptRenderLines(state.Transcript).Count - GetTranscriptPageSize(state));
    }

    static void ScrollTranscript(TuiShellState state, int delta)
    {
        var maxOffset = GetMaxTranscriptScrollOffset(state);
        state.TranscriptScrollOffset = Math.Clamp(state.TranscriptScrollOffset + delta, 0, maxOffset);
    }

    static IReadOnlyList<TuiTranscriptRenderLine> GetVisibleTranscriptLines(TuiShellState state)
    {
        var allLines = BuildTranscriptRenderLines(state.Transcript);
        var maxEntries = GetTranscriptPageSize(state);

        if (allLines.Count <= maxEntries)
            return allLines;

        state.TranscriptScrollOffset = Math.Clamp(state.TranscriptScrollOffset, 0, GetMaxTranscriptScrollOffset(state));
        var endExclusive = Math.Max(maxEntries, allLines.Count - state.TranscriptScrollOffset);
        var startIndex = Math.Max(0, endExclusive - maxEntries);
        while (startIndex < endExclusive && string.IsNullOrEmpty(allLines[startIndex].Text))
            startIndex++;
        return allLines[startIndex..endExclusive];
    }

    static List<TuiTranscriptRenderLine> BuildTranscriptRenderLines(IReadOnlyList<TuiTranscriptEntry> transcript)
    {
        var lines = new List<TuiTranscriptRenderLine>();
        foreach (var entry in transcript)
        {
            lines.Add(new TuiTranscriptRenderLine($"> {entry.Command}", true, entry.IsError));

            var output = string.IsNullOrWhiteSpace(entry.Output) ? "(no output)" : entry.Output.TrimEnd();
            foreach (var outputLine in output.Split('\n'))
                lines.Add(new TuiTranscriptRenderLine(outputLine, false, entry.IsError));

            lines.Add(new TuiTranscriptRenderLine(string.Empty, false, entry.IsError));
        }

        return lines;
    }

    static Spectre.Console.Rendering.IRenderable CreateTuiTranscriptLineRenderable(TuiTranscriptRenderLine line)
    {
        if (line.IsCommand)
        {
            var commandColor = line.IsError ? "red" : "cyan";
            return new Markup($"[{commandColor}]{line.Text.EscapeMarkup()}[/]");
        }

        return new Text(line.Text);
    }

    static void AppendTuiTranscript(TuiShellState state, string command, string? output, bool isError = false)
    {
        state.Transcript.Add(new TuiTranscriptEntry(command, NormalizeTuiOutput(output), isError));
        if (state.Transcript.Count > TuiMaxTranscriptEntries)
            state.Transcript.RemoveRange(0, state.Transcript.Count - TuiMaxTranscriptEntries);
        state.TranscriptScrollOffset = Math.Clamp(state.TranscriptScrollOffset, 0, GetMaxTranscriptScrollOffset(state));
        state.IsBodyDirty = true;
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
            return "Use arrows to populate the textbox, Enter to run";

        if (string.IsNullOrWhiteSpace(input))
            return "Type / or start typing a command. Use arrows to populate suggestions. PageUp/PageDown scroll history.";

        return "Press Enter to run command";
    }

    internal static string AcceptSelectedSuggestionIntoInput(IReadOnlyList<TuiCommandCatalogEntry> catalog, string input, List<TuiSuggestion> suggestions, int selectedIndex)
    {
        if (suggestions.Count == 0)
            return input;

        if (selectedIndex < 0 || selectedIndex >= suggestions.Count)
            return input;

        var resolved = ResolveFinalInput(input, suggestions, selectedIndex);
        if (string.IsNullOrWhiteSpace(resolved))
            return input;

        if (string.Equals(resolved, input, StringComparison.Ordinal))
            return input;

        return IsExactKnownCommandInput(catalog, resolved)
            ? EnsureCommandHasTrailingSpace(resolved)
            : resolved;
    }

    internal static string DescribeShellResume(int exitCode)
    {
        return exitCode == 0
            ? "Returned to shell. Command completed successfully."
            : $"Returned to shell. Command exited with code {exitCode}.";
    }

    internal static string GetStandaloneResumePrompt()
    {
        return "Press any key to return to Felix TUI...";
    }

    static async Task<string> CaptureTuiCommandOutputAsync(Func<Task<int>> action)
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

    static bool UpdateTuiWindowState(TuiShellState state)
    {
        var windowSize = GetTuiWindowSize();
        if (windowSize == state.LastWindowSize)
            return false;

        state.LastWindowSize = windowSize;
        state.LayoutMode = GetTuiLayoutMode(windowSize.Width, windowSize.Height);
        state.NeedsFullClear = true;
        state.IsBodyDirty = true;
        return true;
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

    internal static TuiLayoutMode GetTuiLayoutMode(int width, int height)
    {
        if (height < 16)
            return TuiLayoutMode.Minimal;
        if (width < 100 || height < 28)
            return TuiLayoutMode.Compact;
        return TuiLayoutMode.Normal;
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

    static async Task<TuiExecutionResult> ExecuteTuiCommand(string felixPs1, RootCommand rootCommand, IReadOnlyList<TuiCommandCatalogEntry> catalog, string input, TuiShellState state)
    {
        input = NormalizeTuiInput(input);

        var body = input[1..].Trim();
        if (string.Equals(body, "quit", StringComparison.OrdinalIgnoreCase) || string.Equals(body, "exit", StringComparison.OrdinalIgnoreCase))
            return new TuiExecutionResult(false, input);

        if (string.Equals(body, "clear", StringComparison.OrdinalIgnoreCase))
        {
            state.Transcript.Clear();
            state.IsBodyDirty = true;
            state.ResumeMessage = "Cleared transcript.";
            return new TuiExecutionResult(true, input);
        }

        var matchedCommand = FindMatchedCommand(catalog, body);
        if (matchedCommand == null)
        {
            AppendTuiTranscript(state, input, $"Unknown command: {body}", isError: true);
            return new TuiExecutionResult(true, input);
        }

        var invocationArgs = TokenizeShellInput(body);
        if (matchedCommand.ExecutionMode == TuiCommandExecutionMode.Standalone)
        {
            AppendTuiTranscript(state, input, "Suspending shell for direct terminal control...");
            return new TuiExecutionResult(true, input, invocationArgs);
        }

        var (exitCode, output) = await ExecuteCapturedTuiCommand(felixPs1, rootCommand, matchedCommand, invocationArgs);

        if (exitCode != 0 && string.IsNullOrWhiteSpace(output))
            output = $"Command exited with code {exitCode}.";

        AppendTuiTranscript(state, input, output, isError: exitCode != 0);
        state.Header = LoadTuiHeaderSnapshot();
        return new TuiExecutionResult(true, input);
    }

    static async Task<(int ExitCode, string Output)> ExecuteCapturedTuiCommand(string felixPs1, RootCommand rootCommand, TuiCommandCatalogEntry entry, string[] invocationArgs)
    {
        var backend = ResolveExecutionBackend(rootCommand, entry);
        if (backend == TuiCommandExecutionBackend.PowerShell)
        {
            var args = BuildPlainCaptureArgs(entry.SlashPath, invocationArgs);
            var output = await ExecutePowerShellCapture(felixPs1, args);
            return (Environment.ExitCode, NormalizeTuiOutput(output));
        }

        var exitCode = 0;
        var captured = await CaptureTuiCommandOutputAsync(async () =>
        {
            exitCode = await rootCommand.InvokeAsync(invocationArgs);
            return exitCode;
        });

        return (exitCode, captured);
    }

    static string[] BuildPlainCaptureArgs(string slashPath, string[] invocationArgs)
    {
        if (!SupportsPlainFormatCapture(slashPath))
            return invocationArgs;

        if (invocationArgs.Contains("--format", StringComparer.OrdinalIgnoreCase))
            return invocationArgs;

        return invocationArgs.Concat(new[] { "--format", "plain" }).ToArray();
    }

    static bool SupportsPlainFormatCapture(string slashPath)
    {
        return slashPath is "help" or "status" or "list" or "spec list" or "context" or "procs list";
    }

    internal static TuiCommandExecutionBackend ResolveExecutionBackend(RootCommand rootCommand, TuiCommandCatalogEntry entry)
    {
        if (entry.ExecutionBackend != TuiCommandExecutionBackend.Auto)
            return entry.ExecutionBackend;

        return FindCommandByPath(rootCommand, entry.PathTokens) == null
            ? TuiCommandExecutionBackend.PowerShell
            : TuiCommandExecutionBackend.CSharp;
    }

    static Command? FindCommandByPath(Command rootCommand, IReadOnlyList<string> pathTokens)
    {
        Command current = rootCommand;
        foreach (var token in pathTokens)
        {
            var next = current.Subcommands.FirstOrDefault(command => string.Equals(command.Name, token, StringComparison.OrdinalIgnoreCase));
            if (next == null)
                return null;
            current = next;
        }

        return current;
    }

    static async Task ExecuteStandaloneTuiCommand(string felixPs1, RootCommand rootCommand, IReadOnlyList<TuiCommandCatalogEntry> catalog, TuiShellState state)
    {
        var input = state.PendingStandaloneInput ?? string.Empty;
        var invocationArgs = state.PendingStandaloneArgs;
        state.PendingStandaloneArgs = null;
        state.PendingStandaloneInput = null;
        state.ResumeMessage = null;

        if (invocationArgs == null || invocationArgs.Length == 0)
            return;

        AnsiConsole.Clear();
        var body = input.StartsWith("/", StringComparison.Ordinal) ? input[1..].Trim() : input.Trim();
        var matchedCommand = FindMatchedCommand(catalog, body);
        var backend = matchedCommand == null
            ? TuiCommandExecutionBackend.PowerShell
            : ResolveExecutionBackend(rootCommand, matchedCommand);

        int exitCode;
        if (backend == TuiCommandExecutionBackend.CSharp)
        {
            exitCode = await rootCommand.InvokeAsync(invocationArgs);
        }
        else
        {
            await ExecutePowerShell(felixPs1, invocationArgs);
            exitCode = Environment.ExitCode;
        }

        WaitForTuiResumeKey();
        state.Header = LoadTuiHeaderSnapshot();
        state.ResumeMessage = DescribeShellResume(exitCode);
        state.NeedsFullClear = true;
        AppendTuiTranscript(state, input, state.ResumeMessage, isError: exitCode != 0);
    }

    static void WaitForTuiResumeKey()
    {
        try
        {
            if (Console.IsInputRedirected)
                return;
        }
        catch
        {
        }

        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine($"[grey]{GetStandaloneResumePrompt().EscapeMarkup()}[/]");

        try
        {
            Console.ReadKey(intercept: true);
        }
        catch
        {
        }
    }

    internal static string ResolveFinalInput(string input, List<TuiSuggestion> suggestions, int selectedIndex)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            if (suggestions.Count == 0)
                return string.Empty;
            if (string.IsNullOrWhiteSpace(suggestions[selectedIndex].Value))
                return string.Empty;
            return "/" + suggestions[selectedIndex].Value;
        }

        if (suggestions.Count == 0)
            return input;

        var suggestion = suggestions[Math.Clamp(selectedIndex, 0, suggestions.Count - 1)];
        if (suggestion.IsCommand)
            return "/" + suggestion.Value;

        if (!input.StartsWith('/'))
            return input;

        var trimmed = input.TrimEnd();
        if (input.EndsWith(' '))
            return trimmed + " " + suggestion.Value;

        var parts = trimmed.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToList();
        if (parts.Count == 0)
            return "/" + suggestion.Value;

        parts[^1] = suggestion.Value;
        return string.Join(" ", parts);
    }

    internal static string[] TokenizeShellInput(string input)
    {
        return Regex.Matches(input, "\"([^\"]*)\"|(\\S+)")
            .Select(match => match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .ToArray();
    }

    static string NormalizeTuiInput(string input)
    {
        if (string.IsNullOrWhiteSpace(input) || input.StartsWith("/", StringComparison.Ordinal))
            return input;

        return "/" + input.Trim();
    }

    static TuiCommandCatalogEntry? FindMatchedCommand(IReadOnlyList<TuiCommandCatalogEntry> catalog, string body)
    {
        var tokens = TokenizeShellInput(body);
        if (tokens.Length == 0)
            return null;

        return catalog
            .Where(entry => tokens.Length >= entry.PathTokens.Length && entry.PathTokens.SequenceEqual(tokens.Take(entry.PathTokens.Length), StringComparer.OrdinalIgnoreCase))
            .OrderByDescending(entry => entry.PathTokens.Length)
            .FirstOrDefault();
    }

    static bool IsTuiInputReadyToExecute(IReadOnlyList<TuiCommandCatalogEntry> catalog, string input)
    {
        var normalized = NormalizeTuiInput(input);
        if (string.IsNullOrWhiteSpace(normalized) || !normalized.StartsWith("/", StringComparison.Ordinal))
            return false;

        var body = normalized[1..].Trim();
        var command = FindMatchedCommand(catalog, body);
        if (command == null)
            return true;

        var tokens = TokenizeShellInput(body);
        var remainingTokens = tokens.Skip(command.PathTokens.Length).ToArray();
        var positionalCount = CountPositionalArguments(remainingTokens);
        if (positionalCount < command.MinimumPositionalArguments)
            return false;

        if (string.Equals(command.SlashPath, "deps", StringComparison.OrdinalIgnoreCase))
            return positionalCount > 0 || remainingTokens.Any(token => token.StartsWith("-", StringComparison.Ordinal));

        return true;
    }

    static bool IsExactKnownCommandInput(IReadOnlyList<TuiCommandCatalogEntry> catalog, string input)
    {
        var normalized = NormalizeTuiInput(input);
        if (string.IsNullOrWhiteSpace(normalized) || !normalized.StartsWith("/", StringComparison.Ordinal))
            return false;

        var body = normalized[1..].Trim();
        if (string.IsNullOrWhiteSpace(body))
            return false;

        return catalog.Any(entry => string.Equals(entry.SlashPath, body, StringComparison.OrdinalIgnoreCase));
    }

    static bool ShouldStageCommandBeforeExecution(IReadOnlyList<TuiCommandCatalogEntry> catalog, string input)
    {
        var normalized = NormalizeTuiInput(input);
        if (string.IsNullOrWhiteSpace(normalized) || !normalized.StartsWith("/", StringComparison.Ordinal))
            return false;

        if (input.EndsWith(" ", StringComparison.Ordinal))
            return false;

        var body = normalized[1..].Trim();
        var command = FindMatchedCommand(catalog, body);
        if (command == null)
            return false;

        return string.Equals(body, command.SlashPath, StringComparison.OrdinalIgnoreCase)
            && TuiCommandsThatStageBeforeExecution.Contains(command.SlashPath);
    }

    static string EnsureCommandHasTrailingSpace(string input)
    {
        var normalized = NormalizeTuiInput(input).TrimEnd();
        return normalized.EndsWith(" ", StringComparison.Ordinal) ? normalized : normalized + " ";
    }

    internal static List<TuiCommandCatalogEntry> BuildTuiCommandCatalog(RootCommand rootCommand)
    {
        var entries = new List<TuiCommandCatalogEntry>();
        foreach (var subcommand in rootCommand.Subcommands)
            BuildTuiCommandCatalog(entries, rootCommand, subcommand, Array.Empty<string>());

        AddVirtualTuiCommands(entries);
        entries.Add(new TuiCommandCatalogEntry("clear", "Clear the transcript", "/clear", new[] { "clear" }, Array.Empty<string>(), Array.Empty<string>(), 0, TuiCommandExecutionMode.Captured, TuiCommandExecutionBackend.CSharp));
        entries.Add(new TuiCommandCatalogEntry("quit", "Exit the TUI", "/quit", new[] { "quit" }, Array.Empty<string>(), Array.Empty<string>(), 0, TuiCommandExecutionMode.Captured, TuiCommandExecutionBackend.CSharp));

        return entries
            .OrderBy(entry => entry.SlashPath, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    static void AddVirtualTuiCommands(List<TuiCommandCatalogEntry> entries)
    {
        entries.Add(new TuiCommandCatalogEntry(
            "context build",
            "Generate project context documentation",
            "/context build",
            new[] { "context", "build" },
            Array.Empty<string>(),
            Array.Empty<string>(),
            0,
            TuiCommandExecutionMode.Captured,
            TuiCommandExecutionBackend.CSharp));

        entries.Add(new TuiCommandCatalogEntry(
            "context show",
            "View generated project context documentation",
            "/context show",
            new[] { "context", "show" },
            Array.Empty<string>(),
            Array.Empty<string>(),
            0,
            TuiCommandExecutionMode.Captured,
            TuiCommandExecutionBackend.CSharp));
    }

    static void BuildTuiCommandCatalog(List<TuiCommandCatalogEntry> entries, RootCommand rootCommand, Command command, IReadOnlyList<string> parentPath)
    {
        var pathTokens = parentPath.Concat(new[] { command.Name }).ToArray();
        var slashPath = string.Join(" ", pathTokens);

        if (!TuiExcludedSlashPaths.Contains(slashPath) && IsExecutableCommand(command) && IsSupportedTuiCommand(slashPath))
        {
            var optionAliases = rootCommand.Options
                .Concat(command.Options)
                .SelectMany(GetOptionAliases)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
            var arguments = command.Arguments.ToArray();
            var argumentNames = arguments.Select(argument => argument.Name).ToArray();
            entries.Add(new TuiCommandCatalogEntry(
                slashPath,
                command.Description ?? string.Empty,
                BuildTuiUsage(slashPath, argumentNames),
                pathTokens,
                optionAliases,
                argumentNames,
                GetMinimumPositionalArguments(slashPath, arguments),
                ResolveExecutionMode(slashPath),
                ResolveExecutionBackend(slashPath)));
        }

        foreach (var subcommand in command.Subcommands)
            BuildTuiCommandCatalog(entries, rootCommand, subcommand, pathTokens);
    }

    static bool IsSupportedTuiCommand(string slashPath)
    {
        return TuiSupportedSlashPaths.Contains(slashPath);
    }

    static bool IsExecutableCommand(Command command)
    {
        return command.Subcommands.Count == 0;
    }

    static string BuildTuiUsage(string slashPath, IReadOnlyList<string> argumentNames)
    {
        if (argumentNames.Count == 0)
            return "/" + slashPath;

        return "/" + slashPath + " " + string.Join(" ", argumentNames.Select(name => $"<{name}>"));
    }

    static IEnumerable<string> GetOptionAliases(Option option)
    {
        yield return option.Name.StartsWith('-') ? option.Name : $"--{option.Name}";
        foreach (var alias in option.Aliases)
            yield return alias;
    }

    static int GetMinimumPositionalArguments(string slashPath, IReadOnlyList<Argument> arguments)
    {
        if (string.Equals(slashPath, "deps", StringComparison.OrdinalIgnoreCase))
            return 0;

        return arguments.Sum(argument => argument.Arity.MinimumNumberOfValues);
    }

    internal static TuiCommandExecutionMode ResolveExecutionMode(string slashPath)
    {
        if (slashPath is "help" or "version" or "status" or "list" or "validate" or "deps" or "context"
            or "agent list" or "agent current" or "agent install-help"
            or "procs list"
            or "spec list" or "spec fix" or "spec status" or "spec pull" or "spec push"
            or "clear" or "quit")
        {
            return TuiCommandExecutionMode.Captured;
        }

        return TuiCommandExecutionMode.Standalone;
    }

    internal static TuiCommandExecutionBackend ResolveExecutionBackend(string slashPath)
    {
        return slashPath switch
        {
            "clear" or "quit" => TuiCommandExecutionBackend.CSharp,
            _ => TuiCommandExecutionBackend.Auto
        };
    }

    internal static List<TuiSuggestion> GetTuiSuggestions(IReadOnlyList<TuiCommandCatalogEntry> catalog, string input)
    {
        var trimmed = input.Trim();
        if (trimmed.Length == 0)
            return new List<TuiSuggestion>();

        var body = trimmed.StartsWith("/", StringComparison.Ordinal) ? trimmed[1..] : trimmed;
        if (string.IsNullOrWhiteSpace(body))
        {
            return catalog
                .OrderBy(entry => entry.SlashPath, StringComparer.OrdinalIgnoreCase)
                .Select(entry => new TuiSuggestion(entry.SlashPath, entry.Description, true))
                .ToList();
        }

        var matchedCommand = FindMatchedCommand(catalog, body);
        var hasTrailingSpace = input.EndsWith(' ');
        if (matchedCommand == null || (!hasTrailingSpace && !string.Equals(body, matchedCommand.SlashPath, StringComparison.OrdinalIgnoreCase) && !body.StartsWith(matchedCommand.SlashPath + " ", StringComparison.OrdinalIgnoreCase)))
        {
            return catalog
                .Where(entry => entry.SlashPath.StartsWith(body, StringComparison.OrdinalIgnoreCase))
                .OrderBy(entry => entry.SlashPath, StringComparer.OrdinalIgnoreCase)
                .Select(entry => new TuiSuggestion(entry.SlashPath, entry.Description, true))
                .ToList();
        }

        var bodyTokens = TokenizeShellInput(body);
        var remainingTokens = bodyTokens.Skip(matchedCommand.PathTokens.Length).ToArray();
        var partialToken = hasTrailingSpace ? string.Empty : remainingTokens.LastOrDefault() ?? string.Empty;
        return GetCommandArgumentSuggestions(matchedCommand, remainingTokens, partialToken, hasTrailingSpace);
    }

    static List<TuiSuggestion> GetCommandArgumentSuggestions(TuiCommandCatalogEntry entry, string[] remainingTokens, string partialToken, bool hasTrailingSpace)
    {
        var suggestions = new List<TuiSuggestion>();
        suggestions.AddRange(GetDynamicArgumentSuggestions(entry, remainingTokens, partialToken, hasTrailingSpace));

        var usedOptions = remainingTokens
            .Where(token => token.StartsWith("-", StringComparison.Ordinal))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        if (string.IsNullOrWhiteSpace(partialToken) || partialToken.StartsWith("-", StringComparison.Ordinal))
        {
            foreach (var option in entry.OptionAliases.Where(alias => !usedOptions.Contains(alias) && alias.StartsWith(partialToken, StringComparison.OrdinalIgnoreCase)))
                suggestions.Add(new TuiSuggestion(option, "option", false));
        }

        var positionalCount = CountPositionalArguments(remainingTokens);
        if (positionalCount < entry.ArgumentNames.Length && !suggestions.Any(suggestion => !suggestion.Value.StartsWith("-", StringComparison.Ordinal)))
        {
            var nextArgument = entry.ArgumentNames[positionalCount];
            suggestions.Add(new TuiSuggestion($"<{nextArgument}>", "argument", false));
        }

        var orderedSuggestions = suggestions
            .GroupBy(suggestion => suggestion.Value, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .OrderByDescending(suggestion => suggestion.IsCommand)
            .ThenBy(suggestion => suggestion.Value, StringComparer.OrdinalIgnoreCase)
            .ToList();

        return orderedSuggestions;
    }

    static int CountPositionalArguments(IEnumerable<string> remainingTokens)
    {
        var count = 0;
        string? previousOption = null;
        foreach (var token in remainingTokens)
        {
            if (token.StartsWith("-", StringComparison.Ordinal))
            {
                previousOption = token;
                continue;
            }

            if (previousOption != null && OptionExpectsValue(previousOption))
            {
                previousOption = null;
                continue;
            }

            count++;
            previousOption = null;
        }

        return count;
    }

    static bool OptionExpectsValue(string option)
    {
        return option is "--status" or "--priority" or "--tags" or "--blocked-by" or "--format" or "--model" or "--max-iterations";
    }

    static List<TuiSuggestion> GetDynamicArgumentSuggestions(TuiCommandCatalogEntry entry, string[] remainingTokens, string partialToken, bool hasTrailingSpace)
    {
        var pendingOption = GetPendingOption(remainingTokens, hasTrailingSpace);
        if (string.Equals(entry.SlashPath, "list", StringComparison.OrdinalIgnoreCase) && string.Equals(pendingOption, "--status", StringComparison.OrdinalIgnoreCase))
            return CreateValueSuggestions(GetRequirementStatuses(), partialToken, "status");

        if (string.Equals(entry.SlashPath, "spec status", StringComparison.OrdinalIgnoreCase))
        {
            var positional = GetPositionalValues(remainingTokens).ToList();
            if (positional.Count == 0)
                return CreateValueSuggestions(GetRequirementSuggestions(null), partialToken, "requirement id");
            if (positional.Count == 1)
                return CreateValueSuggestions(GetRequirementStatuses(), partialToken, "status");
        }

        if (string.Equals(entry.SlashPath, "spec delete", StringComparison.OrdinalIgnoreCase))
            return CreateValueSuggestions(GetRequirementSuggestions(null), partialToken, "requirement id");

        if (string.Equals(entry.SlashPath, "run", StringComparison.OrdinalIgnoreCase))
            return CreateValueSuggestions(GetRequirementSuggestions("planned"), partialToken, "planned requirement")
                .Concat(CreateValueSuggestions(GetCommonFlags(entry.SlashPath), partialToken, "option"))
                .ToList();

        if (string.Equals(entry.SlashPath, "validate", StringComparison.OrdinalIgnoreCase))
            return CreateValueSuggestions(GetRequirementSuggestions("done"), partialToken, "done requirement");

        if (string.Equals(entry.SlashPath, "deps", StringComparison.OrdinalIgnoreCase))
            return CreateValueSuggestions(GetRequirementSuggestions(null), partialToken, "requirement id")
                .Concat(CreateValueSuggestions(new[] { "--incomplete", "--tree", "--check" }, partialToken, "option"))
                .ToList();

        if (string.Equals(entry.SlashPath, "context", StringComparison.OrdinalIgnoreCase))
        {
            var positional = GetPositionalValues(remainingTokens).ToList();
            if (positional.Count == 0)
                return CreateValueSuggestions(new[] { "build", "show" }, partialToken, "subcommand");
        }

        if (string.Equals(entry.SlashPath, "agent use", StringComparison.OrdinalIgnoreCase)
            || string.Equals(entry.SlashPath, "agent set-default", StringComparison.OrdinalIgnoreCase)
            || string.Equals(entry.SlashPath, "agent test", StringComparison.OrdinalIgnoreCase)
            || string.Equals(entry.SlashPath, "agent install-help", StringComparison.OrdinalIgnoreCase))
        {
            return CreateValueSuggestions(GetAgentSuggestions(), partialToken, "agent");
        }

        if (string.Equals(entry.SlashPath, "procs kill", StringComparison.OrdinalIgnoreCase))
            return CreateValueSuggestions(GetProcessKillSuggestions(), partialToken, "session");

        if (string.Equals(entry.SlashPath, "spec pull", StringComparison.OrdinalIgnoreCase)
            || string.Equals(entry.SlashPath, "spec push", StringComparison.OrdinalIgnoreCase)
            || string.Equals(entry.SlashPath, "run-next", StringComparison.OrdinalIgnoreCase)
            || string.Equals(entry.SlashPath, "loop", StringComparison.OrdinalIgnoreCase)
            || string.Equals(entry.SlashPath, "update", StringComparison.OrdinalIgnoreCase))
        {
            return CreateValueSuggestions(GetCommonFlags(entry.SlashPath), partialToken, "option");
        }

        return new List<TuiSuggestion>();
    }

    static IEnumerable<string> GetPositionalValues(IEnumerable<string> remainingTokens)
    {
        string? previousOption = null;
        foreach (var token in remainingTokens)
        {
            if (token.StartsWith("-", StringComparison.Ordinal))
            {
                previousOption = token;
                continue;
            }

            if (previousOption != null && OptionExpectsValue(previousOption))
            {
                previousOption = null;
                continue;
            }

            yield return token;
            previousOption = null;
        }
    }

    static string? GetPendingOption(IReadOnlyList<string> remainingTokens, bool hasTrailingSpace)
    {
        if (remainingTokens.Count == 0)
            return null;

        var lastToken = remainingTokens[^1];
        if (lastToken.StartsWith("-", StringComparison.Ordinal) && hasTrailingSpace && OptionExpectsValue(lastToken))
            return lastToken;

        if (remainingTokens.Count >= 2)
        {
            var previousToken = remainingTokens[^2];
            if (previousToken.StartsWith("-", StringComparison.Ordinal) && OptionExpectsValue(previousToken) && !hasTrailingSpace)
                return previousToken;
        }

        return null;
    }

    static List<TuiSuggestion> CreateValueSuggestions(IEnumerable<string> values, string partialToken, string description)
    {
        return values
            .Where(value => string.IsNullOrWhiteSpace(partialToken) || value.StartsWith(partialToken, StringComparison.OrdinalIgnoreCase))
            .Select(value => new TuiSuggestion(value, description, false))
            .ToList();
    }

    static IEnumerable<string> GetCommonFlags(string slashPath)
    {
        return TuiCommonFlags.TryGetValue(slashPath, out var flags)
            ? flags
            : Array.Empty<string>();
    }

    static IEnumerable<string> GetRequirementStatuses()
    {
        return new[] { "draft", "planned", "in_progress", "blocked", "complete", "done" };
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

    static IEnumerable<string> GetAgentSuggestions()
    {
        return (ReadConfiguredAgents() ?? new List<ConfiguredAgent>())
            .Select(agent => agent.Name)
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Distinct(StringComparer.OrdinalIgnoreCase);
    }

    static IEnumerable<string> GetProcessKillSuggestions()
    {
        foreach (var session in ReadActiveSessions(cleanupFile: false))
        {
            yield return session.SessionId;
            if (!string.IsNullOrWhiteSpace(session.RequirementId))
                yield return session.RequirementId!;
            yield return session.Pid.ToString();
        }

        yield return "all";
    }

    static string TruncateText(string value, int maxLength)
    {
        if (value.Length <= maxLength)
            return value;
        return value[..Math.Max(0, maxLength - 3)] + "...";
    }

    static string NormalizeFooterGlyphs(string value)
    {
        return value;
    }

    static PlainFooterLine CreateFooterContentLine(string content, int innerWidth, ConsoleColor foreground, ConsoleColor background)
    {
        var clipped = TruncatePlainText(content, innerWidth);
        return new PlainFooterLine($"│{clipped.PadRight(innerWidth)}│", foreground, background);
    }


    static string TruncatePlainText(string value, int maxLength)
    {
        if (maxLength <= 0)
            return string.Empty;

        if (value.Length <= maxLength)
            return value;

        if (maxLength <= 3)
            return value[..maxLength];

        return value[..(maxLength - 3)] + "...";
    }

    static string GetFelixWordmark(TuiLayoutMode layoutMode)
    {
        if (layoutMode == TuiLayoutMode.Compact)
        {
            return string.Join(Environment.NewLine, new[]
            {
                "███████╗███████╗██╗     ██╗██╗  ██╗",
                "██╔════╝██╔════╝██║     ██║╚██╗██╔╝",
                "█████╗  █████╗  ██║     ██║ ╚███╔╝ ",
                "██╔══╝  ██╔══╝  ██║     ██║ ██╔██╗ ",
                "██║     ███████╗███████╗██║██╔╝ ██╗",
                "╚═╝     ╚══════╝╚══════╝╚═╝╚═╝  ╚═╝"
            });
        }

        return string.Join(Environment.NewLine, new[]
        {
                "███████╗███████╗██╗     ██╗██╗  ██╗",
                "██╔════╝██╔════╝██║     ██║╚██╗██╔╝",
                "█████╗  █████╗  ██║     ██║ ╚███╔╝ ",
                "██╔══╝  ██╔══╝  ██║     ██║ ██╔██╗ ",
                "██║     ███████╗███████╗██║██╔╝ ██╗",
                "╚═╝     ╚══════╝╚══════╝╚═╝╚═╝  ╚═╝"
        });
    }
}
