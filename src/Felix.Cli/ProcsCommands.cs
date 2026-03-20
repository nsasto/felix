using System.CommandLine;
using System.Diagnostics;
using System.Text.Json;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    static readonly JsonSerializerOptions SessionJsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    static Command CreateProcsCommand(string felixPs1)
    {
        var cmd = new Command("procs", "View or stop Felix-managed processes");

        var listCmd = new Command("list", "List active Felix sessions and process IDs");
        listCmd.SetHandler(async () =>
        {
            await ShowProcsListUI();
        });

        var killTargetArg = new Argument<string?>("target", () => null, "Session id, process id, or 'all'")
        {
            Arity = ArgumentArity.ZeroOrOne
        };
        var killAllOpt = new Option<bool>("--all", "Kill all tracked Felix sessions");

        var killCmd = new Command("kill", "Stop tracked Felix sessions or processes")
        {
            killTargetArg,
            killAllOpt
        };

        killCmd.SetHandler(async (target, killAll) =>
        {
            KillProcessSessionsUI(target, killAll);
            await Task.CompletedTask;
        }, killTargetArg, killAllOpt);

        cmd.AddCommand(listCmd);
        cmd.AddCommand(killCmd);
        return cmd;
    }

    sealed record ActiveSession(
        string SessionId,
        int Pid,
        string? RepoPath,
        string? Branch,
        string? RequirementId,
        string? LogFile,
        DateTimeOffset StartedAt);

    static async Task ShowProcsListUI()
    {
        var sessions = ReadActiveSessions();

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Felix Processes[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        if (sessions.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No active Felix sessions found.[/]");
            return;
        }

        var table = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Session[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]PID[/]").RightAligned().NoWrap())
            .AddColumn(new TableColumn("[yellow]Requirement[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Branch[/]"))
            .AddColumn(new TableColumn("[yellow]Repo[/]"))
            .AddColumn(new TableColumn("[yellow]Started[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]State[/]").NoWrap());

        foreach (var session in sessions.OrderBy(s => s.StartedAt))
        {
            var processState = TryGetProcessState(session.Pid);
            table.AddRow(
                session.SessionId.EscapeMarkup(),
                session.Pid.ToString(),
                (session.RequirementId ?? "-").EscapeMarkup(),
                (session.Branch ?? "-").EscapeMarkup(),
                (session.RepoPath ?? "-").EscapeMarkup(),
                session.StartedAt.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss"),
                processState.EscapeMarkup());
        }

        AnsiConsole.Write(table);
        AnsiConsole.WriteLine();
        await Task.CompletedTask;
    }

    static List<ActiveSession> ReadActiveSessions(bool cleanupFile = false)
    {
        var sessionsPath = Path.Combine(_felixProjectRoot, ".felix", "sessions.json");
        if (!File.Exists(sessionsPath))
            return new List<ActiveSession>();

        List<ActiveSession>? sessions = null;
        try
        {
            var raw = File.ReadAllText(sessionsPath);
            if (string.IsNullOrWhiteSpace(raw))
                return new List<ActiveSession>();

            using var doc = JsonDocument.Parse(raw);
            if (doc.RootElement.ValueKind == JsonValueKind.Array)
            {
                sessions = JsonSerializer.Deserialize<List<ActiveSession>>(raw, SessionJsonOptions);
            }
            else if (doc.RootElement.ValueKind == JsonValueKind.Object)
            {
                var single = JsonSerializer.Deserialize<ActiveSession>(raw, SessionJsonOptions);
                sessions = single != null ? new List<ActiveSession> { single } : new List<ActiveSession>();
                if (cleanupFile && single != null)
                    SaveActiveSessions(sessions);
            }
        }
        catch
        {
            return new List<ActiveSession>();
        }

        sessions ??= new List<ActiveSession>();
        return sessions.Where(session => session != null).ToList();
    }

    static void SaveActiveSessions(IReadOnlyCollection<ActiveSession> sessions)
    {
        var sessionsPath = Path.Combine(_felixProjectRoot, ".felix", "sessions.json");
        Directory.CreateDirectory(Path.GetDirectoryName(sessionsPath)!);

        if (sessions.Count == 0)
        {
            if (File.Exists(sessionsPath))
                File.Delete(sessionsPath);
            return;
        }

        File.WriteAllText(sessionsPath, JsonSerializer.Serialize(sessions, SessionJsonOptions));
    }

    static void KillProcessSessionsUI(string? target, bool killAll)
    {
        var sessions = ReadActiveSessions(cleanupFile: true);
        if (sessions.Count == 0)
        {
            AnsiConsole.MarkupLine("[yellow]No tracked Felix sessions found.[/]");
            Environment.ExitCode = 0;
            return;
        }

        List<ActiveSession> matches;
        if (killAll || string.Equals(target, "all", StringComparison.OrdinalIgnoreCase))
        {
            matches = sessions.ToList();
        }
        else if (!string.IsNullOrWhiteSpace(target))
        {
            matches = sessions
                .Where(session =>
                    string.Equals(session.SessionId, target, StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(session.RequirementId, target, StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(session.Pid.ToString(), target, StringComparison.OrdinalIgnoreCase))
                .ToList();

            if (matches.Count == 0)
            {
                AnsiConsole.MarkupLine($"[red]No tracked Felix session matched '{target.EscapeMarkup()}'.[/]");
                Environment.ExitCode = 1;
                return;
            }
        }
        else
        {
            var choices = sessions
                .OrderBy(session => session.StartedAt)
                .Select(session => $"{session.SessionId} | PID {session.Pid} | {session.RequirementId ?? "-"} | {session.Branch ?? "-"}")
                .ToList();
            choices.Add("all");

            var selected = AnsiConsole.Prompt(
                new SelectionPrompt<string>()
                    .Title("[cyan]Select a session to stop[/]")
                    .PageSize(Math.Min(choices.Count, 12))
                    .AddChoices(choices));

            matches = string.Equals(selected, "all", StringComparison.OrdinalIgnoreCase)
                ? sessions.ToList()
                : new List<ActiveSession>
                {
                    sessions[choices.IndexOf(selected)]
                };
        }

        var remaining = sessions.ToList();
        var results = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Session[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]PID[/]").RightAligned().NoWrap())
            .AddColumn(new TableColumn("[yellow]Result[/]"));

        var stoppedCount = 0;
        foreach (var session in matches)
        {
            var result = TryStopSession(session);
            if (result)
            {
                stoppedCount++;
                remaining.RemoveAll(existing => string.Equals(existing.SessionId, session.SessionId, StringComparison.OrdinalIgnoreCase));
                results.AddRow(session.SessionId.EscapeMarkup(), session.Pid.ToString(), "[green]stopped[/]");
            }
            else
            {
                remaining.RemoveAll(existing => string.Equals(existing.SessionId, session.SessionId, StringComparison.OrdinalIgnoreCase));
                results.AddRow(session.SessionId.EscapeMarkup(), session.Pid.ToString(), "[yellow]not running; removed stale session[/]");
            }
        }

        SaveActiveSessions(remaining);

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Process Stop[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();
        AnsiConsole.Write(results);
        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine($"[green]Updated tracked sessions. Active remaining:[/] {remaining.Count}");
        Environment.ExitCode = 0;
    }

    static bool TryStopSession(ActiveSession session)
    {
        try
        {
            var process = Process.GetProcessById(session.Pid);
            if (process.HasExited)
                return false;

            try
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit(5000);
            }
            catch
            {
                if (!process.HasExited)
                    throw;
            }

            return true;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch
        {
            return false;
        }
    }

    static string TryGetProcessState(int pid)
    {
        try
        {
            var process = Process.GetProcessById(pid);
            return process.HasExited ? "exited" : "running";
        }
        catch
        {
            return "missing";
        }
    }
}
