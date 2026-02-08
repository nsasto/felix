using System.CommandLine;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Spectre.Console;

namespace Felix.Cli;

class Program
{
    static async Task<int> Main(string[] args)
    {
        var rootCommand = new RootCommand("Felix - Autonomous agent executor");

        // Get repository root 
        // During development: c:\dev\Felix\src\Felix.Cli\bin\Debug\net10.0
        // In production: c:\dev\Felix\.felix\bin\Felix.Cli.exe
        var exePath = AppDomain.CurrentDomain.BaseDirectory;
        var felixPs1 = Path.Combine(exePath, "..", "..", "..", "..", "..", ".felix", "felix.ps1");

        // Try to find felix.ps1 by walking up the directory tree
        var searchDir = new DirectoryInfo(exePath);
        while (searchDir != null && !File.Exists(Path.Combine(searchDir.FullName, ".felix", "felix.ps1")))
        {
            searchDir = searchDir.Parent;
        }

        if (searchDir != null)
        {
            felixPs1 = Path.Combine(searchDir.FullName, ".felix", "felix.ps1");
        }

        felixPs1 = Path.GetFullPath(felixPs1);

        if (!File.Exists(felixPs1))
        {
            Console.Error.WriteLine($"Error: felix.ps1 not found at {felixPs1}");
            return 1;
        }

        var formatOpt = new Option<string>("--format", () => "rich", "Output format");
        rootCommand.AddOption(formatOpt);

        // Add commands
        rootCommand.AddCommand(CreateRunCommand(felixPs1, formatOpt));
        rootCommand.AddCommand(CreateLoopCommand(felixPs1, formatOpt));
        rootCommand.AddCommand(CreateStatusCommand(felixPs1, formatOpt));
        rootCommand.AddCommand(CreateListCommand(felixPs1, formatOpt));
        rootCommand.AddCommand(CreateValidateCommand(felixPs1));
        rootCommand.AddCommand(CreateDepsCommand(felixPs1));
        rootCommand.AddCommand(CreateSpecCommand(felixPs1));
        rootCommand.AddCommand(CreateAgentCommand(felixPs1));
        rootCommand.AddCommand(CreateVersionCommand(felixPs1));
        rootCommand.AddCommand(CreateDashboardCommand(felixPs1));

        return await rootCommand.InvokeAsync(args);
    }

    static Command CreateRunCommand(string felixPs1, Option<string> formatOpt)
    {
        var reqIdArg = new Argument<string>("requirement-id", "Requirement ID (e.g., S-0001)");
        var verboseOpt = new Option<bool>("--verbose", "Enable verbose logging");
        var quietOpt = new Option<bool>("--quiet", "Suppress non-essential output");

        var cmd = new Command("run", "Execute a single requirement")
        {
            reqIdArg,
            verboseOpt,
            quietOpt
        };
        cmd.AddOption(formatOpt);

        cmd.SetHandler(async (reqId, format, verbose, quiet) =>
        {
            var args = new List<string> { "run", reqId };
            if (format != "rich") args.AddRange(new[] { "--format", format });
            if (verbose) args.Add("--verbose");
            if (quiet) args.Add("--quiet");

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, reqIdArg, formatOpt, verboseOpt, quietOpt);

        return cmd;
    }

    static Command CreateLoopCommand(string felixPs1, Option<string> formatOpt)
    {
        var maxIterOpt = new Option<int?>("--max-iterations", "Maximum iterations");

        var cmd = new Command("loop", "Run agent in continuous loop mode")
        {
            maxIterOpt,
        };
        cmd.AddOption(formatOpt);

        cmd.SetHandler(async (maxIter, format) =>
        {
            var args = new List<string> { "loop" };
            if (maxIter.HasValue) args.AddRange(new[] { "--max-iterations", maxIter.Value.ToString() });
            if (format != "rich") args.AddRange(new[] { "--format", format });

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, maxIterOpt, formatOpt);

        return cmd;
    }

    static Command CreateStatusCommand(string felixPs1, Option<string> formatOpt)
    {
        var reqIdArg = new Argument<string?>("requirement-id", "Requirement ID (optional, shows summary if omitted)")
        {
            Arity = ArgumentArity.ZeroOrOne
        };

        var cmd = new Command("status", "Show requirement status")
        {
            reqIdArg,
        };
        cmd.AddOption(formatOpt);

        cmd.SetHandler(async (reqId, format) =>
        {
            var args = new List<string> { "status" };
            if (!string.IsNullOrEmpty(reqId)) args.Add(reqId);
            if (format != "rich") args.AddRange(new[] { "--format", format });

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, reqIdArg, formatOpt);

        return cmd;
    }

    static Command CreateListCommand(string felixPs1, Option<string> formatOpt)
    {
        var statusOpt = new Option<string?>("--status", "Filter by status");
        var priorityOpt = new Option<string?>("--priority", "Filter by priority");
        var labelsOpt = new Option<string?>("--labels", "Filter by labels (comma-separated)");
        var blockedByOpt = new Option<string?>("--blocked-by", "Filter by blocker type");
        var withDepsOpt = new Option<bool>("--with-deps", "Show dependencies inline");
        var uiOpt = new Option<bool>("--ui", "Enhanced table UI with Spectre.Console");

        var cmd = new Command("list", "List all requirements")
        {
            statusOpt,
            priorityOpt,
            labelsOpt,
            blockedByOpt,
            withDepsOpt,
            uiOpt
        };
        cmd.AddOption(formatOpt);

        cmd.SetHandler(async (status, priority, labels, blockedBy, withDeps, format, useUI) =>
        {
            if (useUI)
            {
                await ShowListUI(felixPs1, status, priority);
                return;
            }

            var args = new List<string> { "list" };
            if (status != null) args.AddRange(new[] { "--status", status });
            if (priority != null) args.AddRange(new[] { "--priority", priority });
            if (labels != null) args.AddRange(new[] { "--labels", labels });
            if (blockedBy != null) args.AddRange(new[] { "--blocked-by", blockedBy });
            if (withDeps) args.Add("--with-deps");
            if (format != "rich") args.AddRange(new[] { "--format", format });

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, statusOpt, priorityOpt, labelsOpt, blockedByOpt, withDepsOpt, formatOpt, uiOpt);

        return cmd;
    }

    static Command CreateValidateCommand(string felixPs1)
    {
        var reqIdArg = new Argument<string>("requirement-id", "Requirement ID to validate");

        var cmd = new Command("validate", "Run validation checks")
        {
            reqIdArg
        };

        cmd.SetHandler(async (reqId) =>
        {
            await ExecutePowerShell(felixPs1, "validate", reqId);
        }, reqIdArg);

        return cmd;
    }

    static Command CreateDepsCommand(string felixPs1)
    {
        var reqIdArg = new Argument<string?>("requirement-id", "Requirement ID")
        {
            Arity = ArgumentArity.ZeroOrOne
        };
        var checkOpt = new Option<bool>("--check", "Quick validation check only");
        var treeOpt = new Option<bool>("--tree", "Show full dependency tree");
        var incompleteOpt = new Option<bool>("--incomplete", "List all requirements with incomplete dependencies");

        var cmd = new Command("deps", "Show dependencies and validate status")
        {
            reqIdArg,
            checkOpt,
            treeOpt,
            incompleteOpt
        };

        cmd.SetHandler(async (reqId, check, tree, incomplete) =>
        {
            var args = new List<string> { "deps" };

            if (incomplete)
            {
                args.Add("--incomplete");
            }
            else if (!string.IsNullOrEmpty(reqId))
            {
                args.Add(reqId);
                if (check) args.Add("--check");
                if (tree) args.Add("--tree");
            }
            else
            {
                Console.Error.WriteLine("Error: requirement-id required unless using --incomplete");
                Environment.Exit(1);
            }

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, reqIdArg, checkOpt, treeOpt, incompleteOpt);

        return cmd;
    }

    static Command CreateSpecCommand(string felixPs1)
    {
        var cmd = new Command("spec", "Spec management utilities");

        // spec create
        var descArg = new Argument<string?>("description", "Feature description (optional for interactive mode)")
        {
            Arity = ArgumentArity.ZeroOrOne
        };
        var quickOpt = new Option<bool>(new string[] { "--quick", "-q" }, "Quick mode with minimal questions");

        var createCmd = new Command("create", "Create a new specification")
        {
            descArg,
            quickOpt
        };

        createCmd.SetHandler(async (desc, quick) =>
        {
            var args = new List<string> { "spec", "create" };
            if (!string.IsNullOrEmpty(desc)) args.Add(desc);
            if (quick) args.Add("--quick");

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, descArg, quickOpt);

        // spec fix
        var fixDupsOpt = new Option<bool>(new string[] { "--fix-duplicates", "-f" }, "Auto-rename duplicate spec files");

        var fixCmd = new Command("fix", "Align specs folder with requirements.json")
        {
            fixDupsOpt
        };

        fixCmd.SetHandler(async (fixDups) =>
        {
            var args = new List<string> { "spec", "fix" };
            if (fixDups) args.Add("--fix-duplicates");

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, fixDupsOpt);

        // spec delete
        var delReqIdArg = new Argument<string>("requirement-id", "Requirement ID to delete");

        var deleteCmd = new Command("delete", "Delete a specification")
        {
            delReqIdArg
        };

        deleteCmd.SetHandler(async (reqId) =>
        {
            await ExecutePowerShell(felixPs1, "spec", "delete", reqId);
        }, delReqIdArg);

        cmd.AddCommand(createCmd);
        cmd.AddCommand(fixCmd);
        cmd.AddCommand(deleteCmd);

        return cmd;
    }

    static Command CreateAgentCommand(string felixPs1)
    {
        var cmd = new Command("agent", "Manage and switch agents");

        // agent list
        var listCmd = new Command("list", "List all available agents");
        listCmd.SetHandler(async () =>
        {
            await ExecutePowerShell(felixPs1, "agent", "list");
        });

        // agent current
        var currentCmd = new Command("current", "Show current active agent");
        currentCmd.SetHandler(async () =>
        {
            await ExecutePowerShell(felixPs1, "agent", "current");
        });

        // agent use
        var targetArg = new Argument<string>("target", "Agent ID or name");
        var useCmd = new Command("use", "Switch to a different agent")
        {
            targetArg
        };
        useCmd.SetHandler(async (target) =>
        {
            await ExecutePowerShell(felixPs1, "agent", "use", target);
        }, targetArg);

        // agent test
        var testTargetArg = new Argument<string>("target", "Agent ID or name to test");
        var testCmd = new Command("test", "Test agent connectivity")
        {
            testTargetArg
        };
        testCmd.SetHandler(async (target) =>
        {
            await ExecutePowerShell(felixPs1, "agent", "test", target);
        }, testTargetArg);

        cmd.AddCommand(listCmd);
        cmd.AddCommand(currentCmd);
        cmd.AddCommand(useCmd);
        cmd.AddCommand(testCmd);

        return cmd;
    }

    static Command CreateVersionCommand(string felixPs1)
    {
        var cmd = new Command("version", "Show version information");

        cmd.SetHandler(async () =>
        {
            await ExecutePowerShell(felixPs1, "version");
        });

        return cmd;
    }

    static Command CreateDashboardCommand(string felixPs1)
    {
        var cmd = new Command("dashboard", "Interactive TUI dashboard");

        cmd.SetHandler(async () =>
        {
            await RunInteractiveDashboard(felixPs1);
        });

        return cmd;
    }

    static async Task ExecutePowerShell(string felixPs1, params string[] args)
    {
        var quotedArgs = string.Join(" ", args.Select(a => a.Contains(' ') ? $"\"{a}\"" : a));

        // Try pwsh first (PowerShell 7+), fall back to powershell (Windows PowerShell 5.1)
        var pwshPath = FindPowerShell();

        var psi = new ProcessStartInfo
        {
            FileName = pwshPath,
            Arguments = $"-NoProfile -File \"{felixPs1}\" {quotedArgs}",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = false,
            CreateNoWindow = false
        };

        var process = new Process { StartInfo = psi };

        process.OutputDataReceived += (sender, e) =>
        {
            if (e.Data != null) Console.WriteLine(e.Data);
        };

        process.ErrorDataReceived += (sender, e) =>
        {
            if (e.Data != null) Console.Error.WriteLine(e.Data);
        };

        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        await process.WaitForExitAsync();

        Environment.ExitCode = process.ExitCode;
    }

    static string FindPowerShell()
    {
        // Try PowerShell 7+ first
        var pwsh = @"C:\Program Files\PowerShell\7\pwsh.exe";
        if (File.Exists(pwsh)) return pwsh;

        // Try pwsh in PATH
        try
        {
            var result = Process.Start(new ProcessStartInfo
            {
                FileName = "where",
                Arguments = "pwsh",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                CreateNoWindow = true
            });
            if (result != null)
            {
                var path = result.StandardOutput.ReadLine();
                result.WaitForExit();
                if (!string.IsNullOrEmpty(path) && File.Exists(path)) return path;
            }
        }
        catch { }

        // Fall back to Windows PowerShell 5.1
        return "powershell.exe";
    }

    static async Task ShowListUI(string felixPs1, string? statusFilter, string? priorityFilter)
    {
        var rule = new Rule("[cyan]Requirements List[/]").RuleStyle(Style.Parse("cyan dim"));
        AnsiConsole.Write(rule);
        AnsiConsole.WriteLine();

        await AnsiConsole.Status()
            .Spinner(Spinner.Known.Dots)
            .StartAsync("Loading requirements...", async ctx =>
            {
                // Build args for filtering
                var args = new List<string> { "status", "--format", "json" };
                var output = await ExecutePowerShellCapture(felixPs1, args.ToArray());

                try
                {
                    var doc = JsonDocument.Parse(output);
                    var requirements = doc.RootElement;

                    // Filter requirements
                    var filtered = requirements.EnumerateArray().Where(req =>
                    {
                        var status = req.GetProperty("status").GetString();
                        var priority = req.TryGetProperty("priority", out var p) ? p.GetString() : "medium";

                        if (statusFilter != null && status != statusFilter) return false;
                        if (priorityFilter != null && priority != priorityFilter) return false;

                        return true;
                    }).ToList();

                    // Create table
                    var table = new Table()
                        .Border(TableBorder.Rounded)
                        .BorderColor(Color.Grey)
                        .AddColumn(new TableColumn("[yellow]ID[/]"))
                        .AddColumn(new TableColumn("[yellow]Title[/]").Width(60))
                        .AddColumn(new TableColumn("[yellow]Status[/]").Centered())
                        .AddColumn(new TableColumn("[yellow]Priority[/]").Centered());

                    foreach (var req in filtered)
                    {
                        var id = req.GetProperty("id").GetString() ?? "";
                        var title = req.GetProperty("title").GetString() ?? "";
                        var status = req.GetProperty("status").GetString() ?? "";
                        var priority = req.TryGetProperty("priority", out var p) ? p.GetString() : "medium";

                        var statusColor = status switch
                        {
                            "complete" => "green",
                            "done" => "blue",
                            "in_progress" => "yellow",
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

                        // Truncate long titles
                        if (title.Length > 57) title = title.Substring(0, 54) + "...";

                        table.AddRow(
                            $"[cyan]{id}[/]",
                            $"[white]{title.EscapeMarkup()}[/]",
                            $"[{statusColor}]{status}[/]",
                            $"[{priorityColor}]{priority}[/]"
                        );
                    }

                    AnsiConsole.Write(table);
                    AnsiConsole.WriteLine();
                    AnsiConsole.MarkupLine($"[grey]Showing {filtered.Count} of {requirements.GetArrayLength()} requirements[/]");
                }
                catch (Exception ex)
                {
                    AnsiConsole.MarkupLine($"[red]Error: {ex.Message}[/]");
                }
            });
    }

    static async Task<string> ExecutePowerShellCapture(string felixPs1, params string[] args)
    {
        var quotedArgs = string.Join(" ", args.Select(a => a.Contains(' ') ? $"\"{a}\"" : a));
        var pwshPath = FindPowerShell();

        var psi = new ProcessStartInfo
        {
            FileName = pwshPath,
            Arguments = $"-NoProfile -File \"{felixPs1}\" {quotedArgs}",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        var process = Process.Start(psi);
        if (process == null) return "";

        var output = await process.StandardOutput.ReadToEndAsync();
        await process.WaitForExitAsync();

        return output;
    }

    static async Task ShowDashboard(string felixPs1)
    {
        AnsiConsole.Clear();

        // ASCII Art Banner
        AnsiConsole.MarkupLine("[cyan1]███████╗███████╗██╗     ██╗██╗  ██╗[/]");
        AnsiConsole.MarkupLine("[cyan1]██╔════╝██╔════╝██║     ██║╚██╗██╔╝[/]");
        AnsiConsole.MarkupLine("[cyan1]█████╗  █████╗  ██║     ██║ ╚███╔╝[/] ");
        AnsiConsole.MarkupLine("[cyan1]██╔══╝  ██╔══╝  ██║     ██║ ██╔██╗[/] ");
        AnsiConsole.MarkupLine("[cyan1]██║     ███████╗███████╗██║██╔╝ ██╗[/]");
        AnsiConsole.MarkupLine("[cyan1]╚═╝     ╚══════╝╚══════╝╚═╝╚═╝  ╚═╝[/]");
        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine("[grey dim]Autonomous Agent Executor[/]");
        AnsiConsole.WriteLine();

        // Get status data
        var output = await ExecutePowerShellCapture(felixPs1, "status", "--format", "json");
        var doc = JsonDocument.Parse(output);
        var requirements = doc.RootElement;
        var total = requirements.GetArrayLength();

        var statusCounts = new Dictionary<string, int>();
        foreach (var req in requirements.EnumerateArray())
        {
            var status = req.GetProperty("status").GetString() ?? "unknown";
            statusCounts[status] = statusCounts.GetValueOrDefault(status, 0) + 1;
        }

        // Simple text bar chart
        var complete = statusCounts.GetValueOrDefault("complete", 0);
        var done = statusCounts.GetValueOrDefault("done", 0);
        var inProgress = statusCounts.GetValueOrDefault("in_progress", 0);
        var planned = statusCounts.GetValueOrDefault("planned", 0);
        var blocked = statusCounts.GetValueOrDefault("blocked", 0);

        // Horizontal stacked bar (like GitHub language stats)
        var barWidth = 80;
        var completeWidth = (int)((complete / (double)total) * barWidth);
        var doneWidth = (int)((done / (double)total) * barWidth);
        var inProgressWidth = (int)((inProgress / (double)total) * barWidth);
        var plannedWidth = (int)((planned / (double)total) * barWidth);
        var blockedWidth = barWidth - completeWidth - doneWidth - inProgressWidth - plannedWidth;

        AnsiConsole.MarkupLine($"[green]{"".PadRight(completeWidth, '█')}[/][blue]{"".PadRight(doneWidth, '█')}[/][yellow]{"".PadRight(inProgressWidth, '█')}[/][cyan1]{"".PadRight(plannedWidth, '█')}[/][red]{"".PadRight(Math.Max(0, blockedWidth), '█')}[/]");
        AnsiConsole.WriteLine();

        if (complete > 0) AnsiConsole.MarkupLine($"[green]■[/] Complete {complete}%  ", false);
        if (done > 0) AnsiConsole.MarkupLine($"[blue]■[/] Done {done}%  ", false);
        if (inProgress > 0) AnsiConsole.MarkupLine($"[yellow]■[/] In Progress {inProgress}%  ", false);
        if (planned > 0) AnsiConsole.MarkupLine($"[cyan1]■[/] Planned {planned}%  ", false);
        if (blocked > 0) AnsiConsole.MarkupLine($"[red]■[/] Blocked {blocked}%", false);

        AnsiConsole.WriteLine();
        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine($"[grey]Total: {total} requirements[/]");
        AnsiConsole.WriteLine();
    }

    static async Task RunInteractiveDashboard(string felixPs1)
    {
        bool running = true;

        while (running)
        {
            await ShowDashboard(felixPs1);

            AnsiConsole.WriteLine();
            AnsiConsole.MarkupLine("[grey dim][cyan]1[/] Run  [cyan]2[/] Status  [cyan]3[/] List  [cyan]4[/] Validate  [cyan]5[/] Deps  [cyan]/[/] Commands  [cyan]?[/] Help  [cyan]q[/] Quit[/]");

            var key = Console.ReadKey(true);

            switch (key.KeyChar)
            {
                case '1':
                    await RunAgentInteractive(felixPs1);
                    break;
                case '2':
                    await ShowStatusUI(felixPs1);
                    AnsiConsole.WriteLine();
                    AnsiConsole.MarkupLine("[grey]Press any key to continue...[/]");
                    Console.ReadKey(true);
                    break;
                case '3':
                    await InteractiveList(felixPs1);
                    AnsiConsole.WriteLine();
                    AnsiConsole.MarkupLine("[grey]Press any key to continue...[/]");
                    Console.ReadKey(true);
                    break;
                case '4':
                    await ValidateInteractive(felixPs1);
                    break;
                case '5':
                    await ShowDependencies(felixPs1);
                    break;
                case '/':
                    await ShowCommands(felixPs1);
                    break;
                case '?':
                    ShowHelp();
                    break;
                case 'q':
                case 'Q':
                    running = false;
                    AnsiConsole.Clear();
                    AnsiConsole.MarkupLine("[green]Felix TUI exited.[/]");
                    break;
                default:
                    // Ignore other keys
                    break;
            }
        }
    }

    static void ShowHelp()
    {
        AnsiConsole.Clear();

        var helpPanel = new Panel(
            new Markup(
                "[yellow bold]Keyboard Shortcuts[/]\n\n" +
                "[cyan]1-5[/]     Quick actions\n" +
                "[cyan]/[/]       Show all commands\n" +
                "[cyan]?[/]       This help screen\n" +
                "[cyan]q[/]       Quit dashboard\n\n" +
                "[yellow bold]Commands[/]\n\n" +
                "[cyan]run[/]         Execute a requirement\n" +
                "[cyan]loop[/]        Run agent in loop mode\n" +
                "[cyan]status[/]      Show requirements status\n" +
                "[cyan]list[/]        List all requirements\n" +
                "[cyan]validate[/]    Run validation checks\n" +
                "[cyan]deps[/]        Show dependencies\n" +
                "[cyan]spec[/]        Manage specifications\n" +
                "[cyan]tui[/]         Interactive TUI dashboard\n"))
        {
            Header = new PanelHeader("[yellow]❓ Help[/]"),
            Border = BoxBorder.Double,
            BorderStyle = Style.Parse("yellow")
        };

        AnsiConsole.Write(helpPanel);
        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine("[grey]Press any key to continue...[/]");
        Console.ReadKey(true);
    }

    static async Task ShowCommands(string felixPs1)
    {
        var command = AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .Title("[cyan]Select a command:[/]")
                .PageSize(10)
                .MoreChoicesText("[grey](Move up and down to reveal more)[/]")
                .AddChoices(new[] {
                    "List Requirements",
                    "Show Status",
                    "Check Dependencies",
                    "Run Agent",
                    "Validate",
                    "Create Spec",
                    "Back to Dashboard"
                }));

        if (command == "List Requirements")
            await InteractiveList(felixPs1);
        else if (command == "Show Status")
            await ShowStatusUI(felixPs1);
        else if (command == "Check Dependencies")
            await ShowDependencies(felixPs1);
        else if (command == "Run Agent")
            await RunAgentInteractive(felixPs1);
        else if (command == "Validate")
            await ValidateInteractive(felixPs1);
        else if (command == "Create Spec")
            await CreateSpecInteractive(felixPs1);

        if (command != "Back to Dashboard")
        {
            AnsiConsole.WriteLine();
            AnsiConsole.MarkupLine("[grey]Press any key to continue...[/]");
            Console.ReadKey(true);
        }
    }

    static async Task InteractiveList(string felixPs1)
    {
        var statusFilter = AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .Title("[cyan]Filter by status?[/]")
                .AddChoices(new[] { "All", "planned", "in_progress", "done", "complete", "blocked" }));

        if (statusFilter == "All")
            statusFilter = null;

        await ShowListUI(felixPs1, statusFilter, null);
    }

    static async Task ShowDependencies(string felixPs1)
    {
        AnsiConsole.Clear();
        var rule = new Rule("[cyan]Dependency Check[/]").RuleStyle(Style.Parse("cyan dim"));
        AnsiConsole.Write(rule);
        AnsiConsole.WriteLine();

        await ExecutePowerShell(felixPs1, "deps", "--incomplete");

        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine("[grey]Press any key to continue...[/]");
        Console.ReadKey(true);
    }

    static async Task ShowDepsInteractive(string felixPs1)
    {
        var option = AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .Title("[cyan]Dependency view:[/]")
                .AddChoices(new[] { "Tree View", "Incomplete Only", "Check Specific Requirement" }));

        AnsiConsole.Clear();
        var rule = new Rule("[cyan]Dependencies[/]").RuleStyle(Style.Parse("cyan dim"));
        AnsiConsole.Write(rule);
        AnsiConsole.WriteLine();

        if (option == "Tree View")
        {
            await ExecutePowerShell(felixPs1, "deps", "--tree");
        }
        else if (option == "Incomplete Only")
        {
            await ExecutePowerShell(felixPs1, "deps", "--incomplete");
        }
        else
        {
            var output = await ExecutePowerShellCapture(felixPs1, "status", "--format", "json");
            var doc = JsonDocument.Parse(output);
            var requirements = doc.RootElement;

            var reqs = requirements.EnumerateArray()
                .Select(r => $"{r.GetProperty("id").GetString()}: {r.GetProperty("title").GetString()}")
                .ToList();

            if (reqs.Any())
            {
                var selected = AnsiConsole.Prompt(
                    new SelectionPrompt<string>()
                        .Title("[cyan]Select requirement:[/]")
                        .PageSize(10)
                        .AddChoices(reqs));

                var reqId = selected.Split(':')[0];
                AnsiConsole.Clear();
                await ExecutePowerShell(felixPs1, "deps", reqId, "--check");
            }
        }

        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine("[grey]Press any key to continue...[/]");
        Console.ReadKey(true);
    }

    static async Task RunAgentInteractive(string felixPs1)
    {
        var output = await ExecutePowerShellCapture(felixPs1, "status", "--format", "json");
        var doc = JsonDocument.Parse(output);
        var requirements = doc.RootElement;

        var planned = requirements.EnumerateArray()
            .Where(r => r.GetProperty("status").GetString() == "planned")
            .Select(r => $"{r.GetProperty("id").GetString()}: {r.GetProperty("title").GetString()}")
            .ToList();

        if (!planned.Any())
        {
            AnsiConsole.MarkupLine("[yellow]No planned requirements found.[/]");
            return;
        }

        var selected = AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .Title("[cyan]Select requirement to run:[/]")
                .PageSize(10)
                .AddChoices(planned));

        var reqId = selected.Split(':')[0];

        AnsiConsole.Clear();
        await ExecutePowerShell(felixPs1, "run", reqId);
    }

    static async Task ValidateInteractive(string felixPs1)
    {
        var output = await ExecutePowerShellCapture(felixPs1, "status", "--format", "json");
        var doc = JsonDocument.Parse(output);
        var requirements = doc.RootElement;

        var done = requirements.EnumerateArray()
            .Where(r => r.GetProperty("status").GetString() == "done")
            .Select(r => $"{r.GetProperty("id").GetString()}: {r.GetProperty("title").GetString()}")
            .ToList();

        if (!done.Any())
        {
            AnsiConsole.MarkupLine("[yellow]No done requirements to validate.[/]");
            return;
        }

        var selected = AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .Title("[cyan]Select requirement to validate:[/]")
                .PageSize(10)
                .AddChoices(done));

        var reqId = selected.Split(':')[0];

        AnsiConsole.Clear();
        await ExecutePowerShell(felixPs1, "validate", reqId);
    }

    static async Task CreateSpecInteractive(string felixPs1)
    {
        var description = AnsiConsole.Ask<string>("[cyan]Feature description:[/]");

        AnsiConsole.Clear();
        await ExecutePowerShell(felixPs1, "spec", "create", description);
    }

    static async Task ShowStatusUI(string felixPs1)
    {
        AnsiConsole.Clear();
        var rule = new Rule("[cyan]Requirements Dashboard[/]").RuleStyle(Style.Parse("cyan dim"));
        AnsiConsole.Write(rule);
        AnsiConsole.WriteLine();

        await AnsiConsole.Status()
            .StartAsync("Loading requirements...", async ctx =>
            {
                var output = await ExecutePowerShellCapture(felixPs1, "status", "--format", "json");

                try
                {
                    var doc = JsonDocument.Parse(output);
                    var requirements = doc.RootElement;

                    var statusCounts = new Dictionary<string, int>();
                    foreach (var req in requirements.EnumerateArray())
                    {
                        var status = req.GetProperty("status").GetString() ?? "unknown";
                        statusCounts[status] = statusCounts.GetValueOrDefault(status, 0) + 1;
                    }

                    var table = new Table()
                        .Border(TableBorder.Rounded)
                        .BorderColor(Color.Grey)
                        .AddColumn(new TableColumn("[yellow]Status[/]").Centered())
                        .AddColumn(new TableColumn("[yellow]Count[/]").Centered());

                    foreach (var (status, count) in statusCounts.OrderByDescending(x => x.Value))
                    {
                        var (color, emoji) = status switch
                        {
                            "complete" => ("green", "✓"),
                            "done" => ("blue", "●"),
                            "in_progress" => ("yellow", "⟳"),
                            "planned" => ("cyan", "○"),
                            "blocked" => ("red", "✗"),
                            _ => ("white", "?")
                        };
                        table.AddRow($"[{color}]{emoji} {status}[/]", $"[{color} bold]{count}[/]");
                    }

                    AnsiConsole.Write(table);

                    var total = requirements.GetArrayLength();
                    AnsiConsole.WriteLine();
                    AnsiConsole.MarkupLine($"[grey]Total: {total} requirement{(total != 1 ? "s" : "")}[/]");
                }
                catch (Exception ex)
                {
                    AnsiConsole.MarkupLine($"[red]Error: {ex.Message}[/]");
                }
            });
    }
}
