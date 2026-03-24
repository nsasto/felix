using Spectre.Console;
using System.Text;
using System.Text.Json;

namespace Felix.Cli;

partial class Program
{
    static async Task ShowDashboard(string felixPs1)
    {
        AnsiConsole.Clear();

        AnsiConsole.MarkupLine("[cyan]FELIX[/]");
        AnsiConsole.MarkupLine("[grey dim]Autonomous Agent Executor[/]");
        AnsiConsole.WriteLine();

        var output = ReadRequirementsJson();
        var trimmed = output.Trim();
        if (string.IsNullOrEmpty(trimmed) || !trimmed.StartsWith("["))
        {
            AnsiConsole.MarkupLine("[yellow]No requirements found.[/]");
            AnsiConsole.MarkupLine("[grey]Run [cyan]felix setup[/] in a project directory first.[/]");
            AnsiConsole.WriteLine();
            return;
        }

        JsonDocument doc;
        try { doc = JsonDocument.Parse(trimmed); }
        catch
        {
            AnsiConsole.MarkupLine("[red]Could not parse requirements data.[/]");
            AnsiConsole.MarkupLine($"[grey]{trimmed.EscapeMarkup().Substring(0, Math.Min(trimmed.Length, 200))}[/]");
            AnsiConsole.WriteLine();
            return;
        }

        var requirements = doc.RootElement;
        var total = requirements.GetArrayLength();
        if (total == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No requirements found in this project.[/]");
            AnsiConsole.WriteLine();
            return;
        }

        var statusCounts = new Dictionary<string, int>();
        foreach (var req in requirements.EnumerateArray())
        {
            var status = req.GetProperty("status").GetString() ?? "unknown";
            statusCounts[status] = statusCounts.GetValueOrDefault(status, 0) + 1;
        }

        var complete = statusCounts.GetValueOrDefault("complete", 0);
        var done = statusCounts.GetValueOrDefault("done", 0);
        var inProgress = statusCounts.GetValueOrDefault("in_progress", 0);
        var planned = statusCounts.GetValueOrDefault("planned", 0);
        var blocked = statusCounts.GetValueOrDefault("blocked", 0);

        var barWidth = 80;
        var completeWidth = (int)((complete / (double)total) * barWidth);
        var doneWidth = (int)((done / (double)total) * barWidth);
        var inProgressWidth = (int)((inProgress / (double)total) * barWidth);
        var plannedWidth = (int)((planned / (double)total) * barWidth);
        var blockedWidth = barWidth - completeWidth - doneWidth - inProgressWidth - plannedWidth;

        AnsiConsole.MarkupLine($"[green]{"".PadRight(completeWidth, '#')}[/][blue]{"".PadRight(doneWidth, '#')}[/][yellow]{"".PadRight(inProgressWidth, '#')}[/][cyan1]{"".PadRight(plannedWidth, '#')}[/][red]{"".PadRight(Math.Max(0, blockedWidth), '#')}[/]");
        AnsiConsole.WriteLine();

        if (complete > 0) AnsiConsole.MarkupLine($"[green]*[/] Complete {complete}%  ", false);
        if (done > 0) AnsiConsole.MarkupLine($"[blue]*[/] Done {done}%  ", false);
        if (inProgress > 0) AnsiConsole.MarkupLine($"[yellow]*[/] In Progress {inProgress}%  ", false);
        if (planned > 0) AnsiConsole.MarkupLine($"[cyan1]*[/] Planned {planned}%  ", false);
        if (blocked > 0) AnsiConsole.MarkupLine($"[red]*[/] Blocked {blocked}%", false);

        AnsiConsole.WriteLine();
        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine($"[grey]Total: {total} requirements[/]");
        AnsiConsole.WriteLine();
    }

    static async Task RunInteractiveDashboard(string felixPs1)
    {
        await RunCopilotStyleTui(felixPs1);
    }

    static void ShowHelp()
    {
        var helpPanel = new Panel(
            new Markup(
                "[yellow bold]Slash Commands[/]\n\n" +
                "[cyan]/help[/]          Show help\n" +
                "[cyan]/version[/]       Show version info\n" +
                "[cyan]/status[/]        Show requirements status\n" +
                "[cyan]/list[/]          List requirements\n" +
                "[cyan]/run-next[/]      Run next requirement\n" +
                "[cyan]/run[/]           Run a requirement\n" +
                "[cyan]/validate[/]      Validate a requirement\n" +
                "[cyan]/deps[/]          Show dependencies\n" +
                "[cyan]/procs[/]         Show active sessions\n" +
                "[cyan]/setup[/]         Run setup\n" +
                "[cyan]/quit[/]          Exit the TUI\n\n" +
                "[grey]Esc cancels menus or suggestions. Backspace on empty input exits the active selection.[/]"))
        {
            Header = new PanelHeader("[yellow]Help[/]"),
            Border = BoxBorder.Rounded,
            BorderStyle = Style.Parse("yellow")
        };

        AnsiConsole.Write(helpPanel);
        AnsiConsole.WriteLine();
    }

    static Task ShowCommands(string felixPs1) => Task.CompletedTask;

    static async Task InteractiveList(string felixPs1)
    {
        await ShowListUI(felixPs1, null, null, null, null, false);
    }

    static async Task ShowDependencies(string felixPs1)
    {
        var rule = new Rule("[cyan]Dependency Check[/]").RuleStyle(Style.Parse("cyan dim"));
        AnsiConsole.Write(rule);
        AnsiConsole.WriteLine();

        await ExecutePowerShell(felixPs1, "deps", "--incomplete");
    }

    static async Task ShowDepsInteractive(string felixPs1)
    {
        await ShowDependencies(felixPs1);
    }

    static async Task RunAgentInteractive(string felixPs1)
    {
        var output = ReadRequirementsJson();
        var elements = ParseRequirementsJson(output);
        if (elements == null)
        {
            AnsiConsole.MarkupLine("[yellow]No requirements found. Run felix setup in a project directory.[/]");
            return;
        }

        var requirement = elements.FirstOrDefault(r => string.Equals(r.GetProperty("status").GetString(), "planned", StringComparison.OrdinalIgnoreCase));
        if (requirement.ValueKind == JsonValueKind.Undefined)
        {
            AnsiConsole.MarkupLine("[yellow]No planned requirements found.[/]");
            return;
        }

        var reqId = requirement.GetProperty("id").GetString() ?? string.Empty;
        await ExecuteFelixRichCommand(felixPs1, "Run Requirement", "run", reqId);
    }

    static async Task ValidateInteractive(string felixPs1)
    {
        var output = ReadRequirementsJson();
        var elements = ParseRequirementsJson(output);
        if (elements == null)
        {
            AnsiConsole.MarkupLine("[yellow]No requirements found. Run felix setup in a project directory.[/]");
            return;
        }

        var requirement = elements.FirstOrDefault(r => string.Equals(r.GetProperty("status").GetString(), "done", StringComparison.OrdinalIgnoreCase));
        if (requirement.ValueKind == JsonValueKind.Undefined)
        {
            AnsiConsole.MarkupLine("[yellow]No done requirements to validate.[/]");
            return;
        }

        var reqId = requirement.GetProperty("id").GetString() ?? string.Empty;
        await ExecutePowerShell(felixPs1, "validate", reqId);
    }

    static async Task CreateSpecInteractive(string felixPs1)
    {
        AnsiConsole.MarkupLine("[yellow]Use /spec-create <description> to create a spec from the shell prompt.[/]");
        await Task.CompletedTask;
    }

    static async Task ShowProcs(string felixPs1)
    {
        var rule = new Rule("[cyan]Active Agent Sessions[/]").RuleStyle(Style.Parse("cyan dim"));
        AnsiConsole.Write(rule);
        AnsiConsole.WriteLine();

        await AnsiConsole.Status()
            .StartAsync("Loading sessions...", async _ =>
            {
                var output = await ExecutePowerShellCapture(felixPs1, "procs", "list");

                if (string.IsNullOrWhiteSpace(output) || output.Contains("No active sessions"))
                {
                    AnsiConsole.MarkupLine("[grey]No active sessions[/]");
                    return;
                }

                var lines = output.Split('\n', StringSplitOptions.RemoveEmptyEntries);

                var table = new Table()
                    .Border(TableBorder.Rounded)
                    .BorderColor(Color.Grey)
                    .AddColumn(new TableColumn("[yellow]Session ID[/]"))
                    .AddColumn(new TableColumn("[yellow]Requirement[/]"))
                    .AddColumn(new TableColumn("[yellow]Agent[/]"))
                    .AddColumn(new TableColumn("[yellow]PID[/]").RightAligned())
                    .AddColumn(new TableColumn("[yellow]Status[/]"))
                    .AddColumn(new TableColumn("[yellow]Duration[/]"));

                var foundData = false;
                foreach (var line in lines)
                {
                    if (line.Contains("-2026") && line.Contains("it"))
                    {
                        var parts = line.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                        if (parts.Length >= 6)
                        {
                            table.AddRow(
                                $"[cyan]{parts[0]}[/]",
                                $"[white]{parts[1]}[/]",
                                $"[green]{parts[2]}[/]",
                                $"[grey]{parts[3]}[/]",
                                $"[yellow]{parts[4]}[/]",
                                $"[grey]{string.Join(" ", parts.Skip(5))}[/]");
                            foundData = true;
                        }
                    }
                }

                if (foundData)
                {
                    AnsiConsole.Write(table);
                    AnsiConsole.WriteLine();
                    AnsiConsole.MarkupLine("[grey]Tip: Use 'felix procs kill <session-id>' to terminate a session[/]");
                }
                else
                {
                    AnsiConsole.MarkupLine("[grey]No active sessions[/]");
                }
            });
    }
}
