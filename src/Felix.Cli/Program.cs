using System.CommandLine;
using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Spectre.Console;

namespace Felix.Cli;

class Program
{
    // Set once in Main(); used by ExecutePowerShell* to inject env vars into subprocesses.
    static string _felixInstallDir = "";
    static string _felixProjectRoot = "";
    const string DefaultUpdateRepo = "nsasto/felix";
    const string DefaultWindowsReleaseRid = "win-x64";

    internal sealed record GitHubReleaseAsset(string Name, string DownloadUrl);
    internal sealed record GitHubReleaseMetadata(string TagName, IReadOnlyList<GitHubReleaseAsset> Assets);
    internal sealed record UpdateReleasePlan(string CurrentVersion, string TargetVersion, GitHubReleaseAsset ZipAsset, GitHubReleaseAsset ChecksumAsset, bool HasInstalledCopy);

    static async Task<int> Main(string[] args)
    {
        var rootCommand = new RootCommand("Felix - Autonomous agent executor");

        // 'felix install' extracts PS scripts from the embedded zip — no PS needed yet.
        // Register it unconditionally so it works before any scripts are on disk.
        rootCommand.AddCommand(CreateInstallCommand());

        // ── Resolve felix.ps1 ────────────────────────────────────────────────
        // Priority 1: walk up from exe dir (finds local dev repo — dev workflow unchanged)
        // Priority 2: global install dir %LOCALAPPDATA%\Programs\Felix\ (installed app)
        string? felixPs1 = null;

        var searchDir = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
        while (searchDir != null && !File.Exists(Path.Combine(searchDir.FullName, ".felix", "felix.ps1")))
            searchDir = searchDir.Parent;

        if (searchDir != null)
            felixPs1 = Path.GetFullPath(Path.Combine(searchDir.FullName, ".felix", "felix.ps1"));

        if (felixPs1 == null || !File.Exists(felixPs1))
        {
            var globalInstall = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs", "Felix", "felix.ps1");
            if (File.Exists(globalInstall))
                felixPs1 = globalInstall;
        }

        if (felixPs1 == null || !File.Exists(felixPs1))
        {
            // Allow 'felix install' to proceed without scripts
            if (args.Length > 0 && args[0] == "install")
                return await rootCommand.InvokeAsync(args);

            Console.Error.WriteLine("Error: felix.ps1 not found.");
            Console.Error.WriteLine("Run 'felix install' to install Felix, or run from inside a Felix repository.");
            return 1;
        }

        // ── Set shared env-var context ────────────────────────────────────────
        // FELIX_INSTALL_DIR → directory that contains felix.ps1 (core/, commands/, plugins/)
        // FELIX_PROJECT_ROOT → current working directory (the project being worked on)
        _felixInstallDir = Path.GetDirectoryName(felixPs1)!;
        _felixProjectRoot = Directory.GetCurrentDirectory();

        var formatOpt = new Option<string>("--format", () => "rich", "Output format");
        rootCommand.AddOption(formatOpt);

        // Add PS-backed commands
        rootCommand.AddCommand(CreateRunCommand(felixPs1, formatOpt));
        rootCommand.AddCommand(CreateRunNextCommand(felixPs1, formatOpt));
        rootCommand.AddCommand(CreateLoopCommand(felixPs1, formatOpt));
        rootCommand.AddCommand(CreateStatusCommand(felixPs1, formatOpt));
        rootCommand.AddCommand(CreateListCommand(felixPs1, formatOpt));
        rootCommand.AddCommand(CreateValidateCommand(felixPs1));
        rootCommand.AddCommand(CreateDepsCommand(felixPs1));
        rootCommand.AddCommand(CreateSpecCommand(felixPs1));
        rootCommand.AddCommand(CreateAgentCommand(felixPs1));
        rootCommand.AddCommand(CreateSetupCommand(felixPs1));
        rootCommand.AddCommand(CreateProcsCommand(felixPs1));
        rootCommand.AddCommand(CreateContextCommand(felixPs1, formatOpt));
        rootCommand.AddCommand(CreateUpdateCommand());
        rootCommand.AddCommand(CreateVersionCommand(felixPs1));
        rootCommand.AddCommand(CreateHelpCommand(felixPs1, rootCommand));
        rootCommand.AddCommand(CreateDashboardCommand(felixPs1));
        rootCommand.AddCommand(CreateTuiCommand(felixPs1));

        // Generic passthrough: if the first arg is not a known verb, forward to PowerShell directly.
        // This allows new PS command files to be added without touching Program.cs.
        if (args.Length > 0 && !args[0].StartsWith("-"))
        {
            var knownVerbs = rootCommand.Subcommands
                .Select(c => c.Name)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            knownVerbs.Add("--help"); knownVerbs.Add("--version");
            if (!knownVerbs.Contains(args[0]))
            {
                await ExecutePowerShell(felixPs1, args);
                return Environment.ExitCode;
            }
        }

        return await rootCommand.InvokeAsync(args);
    }

    static Command CreateRunCommand(string felixPs1, Option<string> formatOpt)
    {
        var reqIdArg = new Argument<string>("requirement-id", "Requirement ID (e.g., S-0001)");
        var verboseOpt = new Option<bool>("--verbose", "Enable verbose logging");
        verboseOpt.AddAlias("-Verbose");
        var quietOpt = new Option<bool>("--quiet", "Suppress non-essential output");
        var syncOpt = new Option<bool>("--sync", "Temporarily enable sync (overrides config)");

        var cmd = new Command("run", "Execute a single requirement")
        {
            reqIdArg,
            verboseOpt,
            quietOpt,
            syncOpt
        };
        cmd.AddOption(formatOpt);

        cmd.SetHandler(async (reqId, format, verbose, quiet, sync) =>
        {
            var args = new List<string> { "run", reqId };
            if (format != "rich") args.AddRange(new[] { "--format", format });
            if (verbose) args.Add("--verbose");
            if (quiet) args.Add("--quiet");
            if (sync) args.Add("--sync");

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, reqIdArg, formatOpt, verboseOpt, quietOpt, syncOpt);

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

    static Command CreateRunNextCommand(string felixPs1, Option<string> formatOpt)
    {
        var syncOpt = new Option<bool>("--sync", "Temporarily enable sync (overrides config)");

        var cmd = new Command("run-next", "Claim and run next available requirement (local or server-assigned)")
        {
            syncOpt,
        };
        cmd.AddOption(formatOpt);

        cmd.SetHandler(async (sync, format) =>
        {
            var args = new List<string> { "run-next" };
            if (sync) args.Add("--sync");
            if (format != "rich") args.AddRange(new[] { "--format", format });

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, syncOpt, formatOpt);

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
        var tagsOpt = new Option<string?>("--tags", "Filter by tags (comma-separated)");
        var blockedByOpt = new Option<string?>("--blocked-by", "Filter by blocker type");
        var withDepsOpt = new Option<bool>("--with-deps", "Show dependencies inline");
        var uiOpt = new Option<bool>("--ui", "Enhanced table UI with Spectre.Console");

        var cmd = new Command("list", "List all requirements")
        {
            statusOpt,
            priorityOpt,
            tagsOpt,
            blockedByOpt,
            withDepsOpt,
            uiOpt
        };
        cmd.AddOption(formatOpt);

        cmd.SetHandler(async (status, priority, tags, blockedBy, withDeps, format, useUI) =>
        {
            if (useUI)
            {
                await ShowListUI(felixPs1, status, priority);
                return;
            }

            var args = new List<string> { "list" };
            if (status != null) args.AddRange(new[] { "--status", status });
            if (priority != null) args.AddRange(new[] { "--priority", priority });
            if (tags != null) args.AddRange(new[] { "--tags", tags });
            if (blockedBy != null) args.AddRange(new[] { "--blocked-by", blockedBy });
            if (withDeps) args.Add("--with-deps");
            if (format != "rich") args.AddRange(new[] { "--format", format });

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, statusOpt, priorityOpt, tagsOpt, blockedByOpt, withDepsOpt, formatOpt, uiOpt);

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

        // spec status
        var statusReqIdArg = new Argument<string>("requirement-id", "Requirement ID to update");
        var statusArg = new Argument<string>("status", "New status (draft, planned, in_progress, blocked, complete, done)");

        var statusCmd = new Command("status", "Update a requirement status in requirements.json")
        {
            statusReqIdArg,
            statusArg
        };

        statusCmd.SetHandler(async (reqId, status) =>
        {
            await ExecutePowerShell(felixPs1, "spec", "status", reqId, status);
        }, statusReqIdArg, statusArg);

        // spec pull
        var dryRunOpt = new Option<bool>("--dry-run", "Show what would change without writing files");
        var deleteOpt = new Option<bool>("--delete", "Also delete local specs that no longer exist on server");
        var forceOpt2 = new Option<bool>("--force", "Overwrite local files even if not tracked in manifest");

        var pullCmd = new Command("pull", "Download changed specs from server")
        {
            dryRunOpt,
            deleteOpt,
            forceOpt2
        };

        pullCmd.SetHandler(async (dryRun, delete, force) =>
        {
            var args = new List<string> { "spec", "pull" };
            if (dryRun) args.Add("--dry-run");
            if (delete) args.Add("--delete");
            if (force) args.Add("--force");
            await ExecutePowerShell(felixPs1, args.ToArray());
        }, dryRunOpt, deleteOpt, forceOpt2);

        // spec push
        var pushDryRunOpt = new Option<bool>("--dry-run", "Show what would change without uploading");
        var pushForceOpt = new Option<bool>("--force", "Upload all local specs and request create-if-missing requirement mappings");

        var pushCmd = new Command("push", "Upload local spec files to server")
        {
            pushDryRunOpt,
            pushForceOpt
        };

        pushCmd.SetHandler(async (dryRun, force) =>
        {
            var args = new List<string> { "spec", "push" };
            if (dryRun) args.Add("--dry-run");
            if (force) args.Add("--force");
            await ExecutePowerShell(felixPs1, args.ToArray());
        }, pushDryRunOpt, pushForceOpt);

        cmd.AddCommand(createCmd);
        cmd.AddCommand(fixCmd);
        cmd.AddCommand(deleteCmd);
        cmd.AddCommand(statusCmd);
        cmd.AddCommand(pullCmd);
        cmd.AddCommand(pushCmd);

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
        var targetArg = new Argument<string?>("target", "Agent ID or name")
        {
            Arity = ArgumentArity.ZeroOrOne
        };
        var useCmd = new Command("use", "Switch to a different agent")
        {
            targetArg
        };
        useCmd.SetHandler(async (target) =>
        {
            if (string.IsNullOrEmpty(target))
                await ExecutePowerShell(felixPs1, "agent", "use");
            else
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

        var setupCmd = new Command("setup", "Configure agents for this project");
        setupCmd.SetHandler(async () =>
        {
            await ExecutePowerShell(felixPs1, "agent", "setup");
        });

        var registerCmd = new Command("register", "Register the current agent with the sync server");
        registerCmd.SetHandler(async () =>
        {
            await ExecutePowerShell(felixPs1, "agent", "register");
        });

        cmd.AddCommand(listCmd);
        cmd.AddCommand(currentCmd);
        cmd.AddCommand(useCmd);
        cmd.AddCommand(testCmd);
        cmd.AddCommand(setupCmd);
        cmd.AddCommand(registerCmd);

        return cmd;
    }

    static Command CreateSetupCommand(string felixPs1)
    {
        var cmd = new Command("setup", "Initialize or re-configure a Felix project in the current directory");

        cmd.SetHandler(async () =>
        {
            await ExecutePowerShell(felixPs1, "setup");
        });

        return cmd;
    }

    static Command CreateUpdateCommand()
    {
        var checkOpt = new Option<bool>("--check", "Check GitHub for a newer Felix release without installing it");
        var yesOpt = new Option<bool>(new[] { "--yes", "-y" }, "Skip the confirmation prompt and install immediately");

        var cmd = new Command("update", "Check GitHub Releases and update the installed Felix CLI")
        {
            checkOpt,
            yesOpt
        };

        cmd.SetHandler(async (check, yes) =>
        {
            Environment.ExitCode = await RunSelfUpdateAsync(check, yes);
        }, checkOpt, yesOpt);

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

    static Command CreateTuiCommand(string felixPs1)
    {
        var cmd = new Command("tui", "Interactive TUI dashboard (alias for 'dashboard')");

        cmd.SetHandler(async () =>
        {
            await RunInteractiveDashboard(felixPs1);
        });

        return cmd;
    }

    static Command CreateHelpCommand(string felixPs1, RootCommand rootCommand)
    {
        var subCmdArg = new Argument<string?>("command", "Command to get help for")
        {
            Arity = ArgumentArity.ZeroOrOne
        };

        var cmd = new Command("help", "Show help for a command")
        {
            subCmdArg
        };

        cmd.SetHandler(async (subCmd) =>
        {
            if (!string.IsNullOrEmpty(subCmd))
            {
                // If the subcommand is registered in C#, delegate to System.CommandLine's --help.
                // Otherwise fall back to PS help.ps1 (covers passthrough commands).
                var known = rootCommand.Subcommands
                    .Select(c => c.Name)
                    .ToHashSet(StringComparer.OrdinalIgnoreCase);
                if (known.Contains(subCmd!))
                    await rootCommand.InvokeAsync(new[] { subCmd!, "--help" });
                else
                    await ExecutePowerShell(felixPs1, "help", subCmd!);
            }
            else
            {
                await ExecutePowerShell(felixPs1, "help");
            }
        }, subCmdArg);

        return cmd;
    }

    static Command CreateProcsCommand(string felixPs1)
    {
        var subCmdArg = new Argument<string[]>("subcommand", "list, kill <session-id>, kill all")
        {
            Arity = ArgumentArity.ZeroOrMore
        };

        var cmd = new Command("procs", "Manage active agent execution sessions")
        {
            subCmdArg
        };

        cmd.SetHandler(async (subArgs) =>
        {
            var args = new List<string> { "procs" };
            args.AddRange(subArgs);
            await ExecutePowerShell(felixPs1, args.ToArray());
        }, subCmdArg);

        return cmd;
    }

    static Command CreateContextCommand(string felixPs1, Option<string> formatOpt)
    {
        var subCmdArg = new Argument<string[]>("subcommand", "build, show")
        {
            Arity = ArgumentArity.ZeroOrMore
        };

        var cmd = new Command("context", "Generate or view project context documentation")
        {
            subCmdArg
        };
        cmd.AddOption(formatOpt);

        cmd.SetHandler(async (subArgs, format) =>
        {
            var args = new List<string> { "context" };
            args.AddRange(subArgs);
            if (format != "rich") args.AddRange(new[] { "--format", format });
            await ExecutePowerShell(felixPs1, args.ToArray());
        }, subCmdArg, formatOpt);

        return cmd;
    }

    static async Task ExecutePowerShell(string felixPs1, params string[] args)
    {
        var quotedArgs = string.Join(" ", args.Select(a => a.Contains(' ') ? $"\"{a}\"" : a));

        // Try pwsh first (PowerShell 7+), fall< Back to powershell (Windows PowerShell 5.1)
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

        // Inject context so PS scripts know where engine files live and what the project dir is
        if (!string.IsNullOrEmpty(_felixInstallDir))
            psi.Environment["FELIX_INSTALL_DIR"] = _felixInstallDir;
        if (!string.IsNullOrEmpty(_felixProjectRoot))
            psi.Environment["FELIX_PROJECT_ROOT"] = _felixProjectRoot;

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
        if (OperatingSystem.IsWindows())
        {
            // Try well-known PowerShell 7+ path first
            var pwsh7 = @"C:\Program Files\PowerShell\7\pwsh.exe";
            if (File.Exists(pwsh7)) return pwsh7;
        }

        // Try pwsh in PATH (works on all platforms)
        try
        {
            var whichCmd = OperatingSystem.IsWindows() ? "where" : "which";
            var result = Process.Start(new ProcessStartInfo
            {
                FileName = whichCmd,
                Arguments = "pwsh",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                CreateNoWindow = true
            });
            if (result != null)
            {
                var path = result.StandardOutput.ReadLine()?.Trim();
                result.WaitForExit();
                if (!string.IsNullOrEmpty(path) && File.Exists(path)) return path;
            }
        }
        catch { }

        // Windows fallback: PowerShell 5.1; Linux/macOS: rely on pwsh in PATH
        return OperatingSystem.IsWindows() ? "powershell.exe" : "pwsh";
    }

    static Task ShowListUI(string felixPs1, string? statusFilter, string? priorityFilter)
    {
        var rule = new Rule("[cyan]Requirements List[/]").RuleStyle(Style.Parse("cyan dim"));
        AnsiConsole.Write(rule);
        AnsiConsole.WriteLine();

        List<JsonElement> filtered;
        int totalCount;
        try
        {
            var output = ReadRequirementsJson();
            var doc = JsonDocument.Parse(output);
            var requirements = doc.RootElement;
            if (requirements.ValueKind != JsonValueKind.Array)
            {
                AnsiConsole.MarkupLine("[yellow]No requirements found. Run felix setup in a project directory.[/]");
                return Task.CompletedTask;
            }
            totalCount = requirements.GetArrayLength();
            filtered = requirements.EnumerateArray().Where(req =>
            {
                var status = req.GetProperty("status").GetString();
                var priority = req.TryGetProperty("priority", out var p) ? p.GetString() : "medium";
                if (statusFilter != null && status != statusFilter) return false;
                if (priorityFilter != null && priority != priorityFilter) return false;
                return true;
            }).ToList();
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Error: {ex.Message}[/]");
            return Task.CompletedTask;
        }

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
            var title = req.TryGetProperty("title", out var titleProp) ? titleProp.GetString() ?? ""
                      : req.TryGetProperty("spec_path", out var spProp) ? spProp.GetString() ?? ""
                      : "";
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
        AnsiConsole.MarkupLine($"[grey]Showing {filtered.Count} of {totalCount} requirements[/]");
        return Task.CompletedTask;
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

        if (!string.IsNullOrEmpty(_felixInstallDir))
            psi.Environment["FELIX_INSTALL_DIR"] = _felixInstallDir;
        if (!string.IsNullOrEmpty(_felixProjectRoot))
            psi.Environment["FELIX_PROJECT_ROOT"] = _felixProjectRoot;

        var process = Process.Start(psi);
        if (process == null) return "";

        var output = await process.StandardOutput.ReadToEndAsync();
        await process.WaitForExitAsync();

        return output;
    }

    /// <summary>
    /// Parses a JSON array from captured PS output.
    /// Returns null (instead of throwing) when the output is empty or not valid JSON.
    /// </summary>
    static List<JsonElement>? ParseRequirementsJson(string output)
    {
        var t = output.Trim();
        if (string.IsNullOrEmpty(t) || !t.StartsWith("[")) return null;
        try { return JsonDocument.Parse(t).RootElement.EnumerateArray().ToList(); }
        catch { return null; }
    }

    internal static string GetInstallDirectory()
    {
        if (OperatingSystem.IsWindows())
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs", "Felix");
        }

        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".local", "share", "felix");
    }

    internal static string? GetInstalledVersion(string installDir)
    {
        var versionFile = Path.Combine(installDir, "version.txt");
        if (!File.Exists(versionFile)) return null;

        return File.ReadAllText(versionFile).Trim();
    }

    internal static bool EnsureWindowsInstallDirOnPath(string installDir)
    {
        var userPath = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? "";
        var segments = userPath.Split(';', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Any(s => string.Equals(s.Trim().TrimEnd('\\'), installDir.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        var updatedPath = string.IsNullOrWhiteSpace(userPath) ? installDir : $"{userPath};{installDir}";
        Environment.SetEnvironmentVariable("Path", updatedPath, EnvironmentVariableTarget.User);
        return true;
    }

    internal static string GetCurrentReleaseRid()
    {
        if (OperatingSystem.IsWindows())
        {
            return DefaultWindowsReleaseRid;
        }

        if (OperatingSystem.IsLinux())
        {
            return RuntimeInformation.OSArchitecture == Architecture.X64
                ? "linux-x64"
                : throw new PlatformNotSupportedException($"felix update does not currently publish Linux assets for architecture '{RuntimeInformation.OSArchitecture}'.");
        }

        if (OperatingSystem.IsMacOS())
        {
            return RuntimeInformation.OSArchitecture switch
            {
                Architecture.Arm64 => "osx-arm64",
                Architecture.X64 => "osx-x64",
                _ => throw new PlatformNotSupportedException($"felix update does not currently publish macOS assets for architecture '{RuntimeInformation.OSArchitecture}'.")
            };
        }

        throw new PlatformNotSupportedException("felix update is not supported on this operating system.");
    }

    internal static string GetExecutableFileName(string? releaseRid = null)
    {
        var rid = releaseRid ?? GetCurrentReleaseRid();
        return rid.StartsWith("win-", StringComparison.OrdinalIgnoreCase) ? "felix.exe" : "felix";
    }

    static async Task<int> RunSelfUpdateAsync(bool checkOnly, bool assumeYes)
    {
        string releaseRid;
        try
        {
            releaseRid = GetCurrentReleaseRid();
        }
        catch (PlatformNotSupportedException ex)
        {
            AnsiConsole.MarkupLine($"[yellow]{ex.Message.EscapeMarkup()}[/]");
            return 1;
        }

        var installDir = GetInstallDirectory();
        var installedVersion = GetInstalledVersion(installDir);
        var currentVersion = installedVersion ?? ReadEmbeddedVersion();
        var executableName = GetExecutableFileName(releaseRid);
        var hasInstalledCopy = File.Exists(Path.Combine(installDir, executableName));

        GitHubReleaseMetadata release;
        try
        {
            release = await GetLatestGitHubReleaseAsync(DefaultUpdateRepo);
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Update check failed:[/] {ex.Message.EscapeMarkup()}");
            return 1;
        }

        var targetVersion = NormalizeVersionString(release.TagName);
        var plan = SelectUpdateReleasePlan(release, currentVersion, targetVersion, hasInstalledCopy, releaseRid);
        if (plan == null)
        {
            AnsiConsole.MarkupLine($"[red]Update failed:[/] Could not find the required {releaseRid.EscapeMarkup()} release assets on GitHub.");
            return 1;
        }

        var comparison = CompareVersions(plan.CurrentVersion, plan.TargetVersion);
        var updateAvailable = !plan.HasInstalledCopy || comparison < 0;

        AnsiConsole.MarkupLine("[cyan]Felix CLI Updater[/]");
        AnsiConsole.MarkupLine("[grey]──────────────────────────────[/]");
        AnsiConsole.MarkupLine($"[grey]Current:[/] {plan.CurrentVersion.EscapeMarkup()}");
        AnsiConsole.MarkupLine($"[grey]Latest:[/]  {plan.TargetVersion.EscapeMarkup()}");
        AnsiConsole.MarkupLine($"[grey]Source:[/]  https://github.com/{DefaultUpdateRepo}/releases/latest");

        if (!updateAvailable)
        {
            AnsiConsole.MarkupLine("[green]Felix is already up to date.[/]");
            return 0;
        }

        if (checkOnly)
        {
            if (plan.HasInstalledCopy)
            {
                AnsiConsole.MarkupLine("[yellow]Update available.[/]");
            }
            else
            {
                AnsiConsole.MarkupLine($"[yellow]No installed Felix copy found in[/] [grey]{installDir.EscapeMarkup()}[/]");
                AnsiConsole.MarkupLine("[yellow]The latest release is available to install.[/]");
            }
            return 0;
        }

        if (!assumeYes)
        {
            var prompt = plan.HasInstalledCopy
                ? $"Install Felix {plan.TargetVersion} to {installDir}?"
                : $"Install Felix {plan.TargetVersion} to {installDir}? No existing installed copy was found.";

            if (!AnsiConsole.Confirm(prompt))
            {
                AnsiConsole.MarkupLine("[grey]Update cancelled.[/]");
                return 0;
            }
        }

        string stageRoot;
        try
        {
            stageRoot = await DownloadAndStageReleaseAsync(plan);
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Download failed:[/] {ex.Message.EscapeMarkup()}");
            return 1;
        }

        Directory.CreateDirectory(installDir);
        var addedToPath = OperatingSystem.IsWindows() && EnsureWindowsInstallDirOnPath(installDir);

        try
        {
            LaunchUpdateHelper(stageRoot, installDir, releaseRid);
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Could not launch the updater helper:[/] {ex.Message.EscapeMarkup()}");
            return 1;
        }

        if (addedToPath)
        {
            AnsiConsole.MarkupLine($"[green]✓[/] Added [grey]{installDir.EscapeMarkup()}[/] to User PATH");
        }

        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine($"[green]Felix {plan.TargetVersion.EscapeMarkup()} staged successfully.[/]");
        AnsiConsole.MarkupLine("[grey]The update helper will replace the installed files after this process exits.[/]");
        AnsiConsole.MarkupLine("[grey]Run 'felix version' again in a few seconds to confirm the new version.[/]");
        return 0;
    }

    internal static async Task<GitHubReleaseMetadata> GetLatestGitHubReleaseAsync(string repo, HttpClient? client = null)
    {
        var disposeClient = client == null;
        client ??= CreateGitHubHttpClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, $"https://api.github.com/repos/{repo}/releases/latest");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));

        try
        {
            using var response = await client.SendAsync(request);
            var content = await response.Content.ReadAsStringAsync();
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException($"GitHub API returned {(int)response.StatusCode}: {content}");
            }

            using var document = JsonDocument.Parse(content);
            var root = document.RootElement;
            var tagName = root.GetProperty("tag_name").GetString() ?? throw new InvalidOperationException("GitHub release response did not include tag_name.");
            var assets = new List<GitHubReleaseAsset>();

            foreach (var assetElement in root.GetProperty("assets").EnumerateArray())
            {
                var name = assetElement.GetProperty("name").GetString();
                var downloadUrl = assetElement.GetProperty("browser_download_url").GetString();
                if (!string.IsNullOrWhiteSpace(name) && !string.IsNullOrWhiteSpace(downloadUrl))
                {
                    assets.Add(new GitHubReleaseAsset(name, downloadUrl));
                }
            }

            return new GitHubReleaseMetadata(tagName, assets);
        }
        finally
        {
            if (disposeClient)
            {
                client.Dispose();
            }
        }
    }

    static HttpClient CreateGitHubHttpClient()
    {
        var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd($"Felix/{ReadEmbeddedVersion()}");
        client.Timeout = TimeSpan.FromMinutes(5);
        return client;
    }

    internal static UpdateReleasePlan? SelectUpdateReleasePlan(GitHubReleaseMetadata release, string currentVersion, string targetVersion, bool hasInstalledCopy, string? releaseRid = null)
    {
        var rid = releaseRid ?? GetCurrentReleaseRid();
        var zipAsset = FindReleaseAsset(release, new[]
        {
            $"felix-latest-{rid}.zip",
            $"felix-{targetVersion}-{rid}.zip"
        });

        var checksumAsset = FindReleaseAsset(release, new[]
        {
            "checksums-latest.txt",
            $"checksums-{targetVersion}.txt"
        });

        if (zipAsset == null || checksumAsset == null)
        {
            return null;
        }

        return new UpdateReleasePlan(currentVersion, targetVersion, zipAsset, checksumAsset, hasInstalledCopy);
    }

    internal static GitHubReleaseAsset? FindReleaseAsset(GitHubReleaseMetadata release, IEnumerable<string> candidateNames)
    {
        foreach (var candidate in candidateNames)
        {
            var asset = release.Assets.FirstOrDefault(a => string.Equals(a.Name, candidate, StringComparison.OrdinalIgnoreCase));
            if (asset != null)
            {
                return asset;
            }
        }

        return null;
    }

    internal static string NormalizeVersionString(string version)
    {
        var normalized = version.Trim();
        if (normalized.StartsWith("v", StringComparison.OrdinalIgnoreCase))
        {
            normalized = normalized.Substring(1);
        }

        var prereleaseIndex = normalized.IndexOf('-');
        if (prereleaseIndex > 0)
        {
            normalized = normalized.Substring(0, prereleaseIndex);
        }

        return normalized;
    }

    internal static int CompareVersions(string left, string right)
    {
        var normalizedLeft = NormalizeVersionString(left);
        var normalizedRight = NormalizeVersionString(right);

        if (Version.TryParse(normalizedLeft, out var leftVersion) && Version.TryParse(normalizedRight, out var rightVersion))
        {
            return leftVersion.CompareTo(rightVersion);
        }

        return string.Compare(normalizedLeft, normalizedRight, StringComparison.OrdinalIgnoreCase);
    }

    static async Task<string> DownloadAndStageReleaseAsync(UpdateReleasePlan plan)
    {
        var stageRoot = Path.Combine(Path.GetTempPath(), $"felix-update-{Guid.NewGuid():N}");
        Directory.CreateDirectory(stageRoot);

        var zipPath = Path.Combine(stageRoot, plan.ZipAsset.Name);
        var checksumPath = Path.Combine(stageRoot, plan.ChecksumAsset.Name);
        var payloadDir = Path.Combine(stageRoot, "payload");

        using var client = CreateGitHubHttpClient();

        AnsiConsole.MarkupLine($"[grey]Downloading[/] {plan.ZipAsset.Name.EscapeMarkup()} ...");
        await DownloadFileAsync(client, plan.ZipAsset.DownloadUrl, zipPath);

        AnsiConsole.MarkupLine($"[grey]Downloading[/] {plan.ChecksumAsset.Name.EscapeMarkup()} ...");
        await DownloadFileAsync(client, plan.ChecksumAsset.DownloadUrl, checksumPath);

        VerifyDownloadedChecksum(checksumPath, zipPath, plan.ZipAsset.Name);
        AnsiConsole.MarkupLine("[green]✓[/] Checksum verified");

        ZipFile.ExtractToDirectory(zipPath, payloadDir);

        var executableName = GetExecutableFileName();
        var stagedExe = Path.Combine(payloadDir, executableName);
        if (!File.Exists(stagedExe))
        {
            throw new InvalidOperationException($"Downloaded archive did not contain {executableName}.");
        }

        return stageRoot;
    }

    static async Task DownloadFileAsync(HttpClient client, string downloadUrl, string destinationPath)
    {
        using var response = await client.GetAsync(downloadUrl, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();

        await using var responseStream = await response.Content.ReadAsStreamAsync();
        await using var fileStream = File.Create(destinationPath);
        await responseStream.CopyToAsync(fileStream);
    }

    internal static void VerifyDownloadedChecksum(string checksumPath, string filePath, string expectedFileName)
    {
        var checksumEntry = File.ReadAllLines(checksumPath)
            .Select(line => line.Trim())
            .Where(line => !string.IsNullOrWhiteSpace(line))
            .Select(ParseChecksumLine)
            .Where(result => result.HasValue)
            .Select(result => result!.Value)
            .FirstOrDefault(result => string.Equals(result.FileName, expectedFileName, StringComparison.OrdinalIgnoreCase));

        if (string.IsNullOrWhiteSpace(checksumEntry.Hash))
        {
            throw new InvalidOperationException($"Checksum file did not include an entry for {expectedFileName}.");
        }

        using var sha = SHA256.Create();
        using var stream = File.OpenRead(filePath);
        var actualHash = Convert.ToHexString(sha.ComputeHash(stream));
        if (!string.Equals(actualHash, checksumEntry.Hash, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"Checksum mismatch for {expectedFileName}. Expected {checksumEntry.Hash}, got {actualHash}.");
        }
    }

    internal static (string Hash, string FileName)? ParseChecksumLine(string line)
    {
        var separatorIndex = line.IndexOf("  ", StringComparison.Ordinal);
        if (separatorIndex < 0)
        {
            return null;
        }

        var hash = line.Substring(0, separatorIndex).Trim();
        var fileName = line.Substring(separatorIndex + 2).Trim();
        if (string.IsNullOrWhiteSpace(hash) || string.IsNullOrWhiteSpace(fileName))
        {
            return null;
        }

        return (hash, fileName);
    }

    static void LaunchUpdateHelper(string stageRoot, string installDir, string releaseRid)
    {
        var isWindows = releaseRid.StartsWith("win-", StringComparison.OrdinalIgnoreCase);
        var helperExtension = isWindows ? ".ps1" : ".sh";
        var helperScriptPath = Path.Combine(Path.GetTempPath(), $"felix-apply-update-{Guid.NewGuid():N}{helperExtension}");
        var helperScript = isWindows ? BuildWindowsUpdateHelperScript() : BuildUnixUpdateHelperScript();

        File.WriteAllText(helperScriptPath, helperScript, new UTF8Encoding(false));

        ProcessStartInfo startInfo;
        if (isWindows)
        {
            startInfo = new ProcessStartInfo
            {
                FileName = FindPowerShell(),
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{helperScriptPath}\" -ParentPid {Environment.ProcessId} -StageRoot \"{stageRoot}\" -InstallDir \"{installDir}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
        }
        else
        {
            startInfo = new ProcessStartInfo
            {
                FileName = "/bin/sh",
                Arguments = $"\"{helperScriptPath}\" {Environment.ProcessId} \"{stageRoot}\" \"{installDir}\"",
                UseShellExecute = false,
                CreateNoWindow = true
            };
        }

        var helperProcess = Process.Start(startInfo);

        if (helperProcess == null)
        {
            throw new InvalidOperationException("Failed to start the background updater helper process.");
        }
    }

    internal static string BuildWindowsUpdateHelperScript() => @"
param(
    [int]$ParentPid,
    [string]$StageRoot,
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'

try {
    Wait-Process -Id $ParentPid -ErrorAction SilentlyContinue
} catch {
}

Start-Sleep -Milliseconds 750

$payloadDir = Join-Path $StageRoot 'payload'
if (-not (Test-Path -LiteralPath $payloadDir)) {
    throw ""Update payload directory not found: $payloadDir""
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

Get-ChildItem -LiteralPath $payloadDir -Force | ForEach-Object {
    $destination = Join-Path $InstallDir $_.Name
    Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force
}

Remove-Item -LiteralPath $StageRoot -Recurse -Force -ErrorAction SilentlyContinue
";

        internal static string BuildUnixUpdateHelperScript() => """
#!/bin/sh
PARENT_PID="$1"
STAGE_ROOT="$2"
INSTALL_DIR="$3"

while kill -0 "$PARENT_PID" 2>/dev/null; do
    sleep 1
done

PAYLOAD_DIR="$STAGE_ROOT/payload"
if [ ! -d "$PAYLOAD_DIR" ]; then
    echo "Update payload directory not found: $PAYLOAD_DIR" >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"
cp -R "$PAYLOAD_DIR"/. "$INSTALL_DIR"/
if [ -f "$INSTALL_DIR/felix" ]; then
    chmod +x "$INSTALL_DIR/felix"
fi
rm -rf "$STAGE_ROOT"
""";

    // ── felix install ─────────────────────────────────────────────────────────

    static Command CreateInstallCommand()
    {
        var forceOpt = new Option<bool>("--force", "Re-extract scripts even if version matches");
        var cmd = new Command("install", "Install Felix CLI to user directory and add to PATH")
        {
            forceOpt
        };
        cmd.IsHidden = true;

        cmd.SetHandler((bool force) =>
        {
            // ── Platform-aware install directory ────────────────────────────
            var installDir = GetInstallDirectory();

            AnsiConsole.MarkupLine("[cyan]Felix CLI Installer[/]");
            AnsiConsole.MarkupLine("[grey]──────────────────────────────[/]");

            // Read embedded version
            var embeddedVersion = ReadEmbeddedVersion();
            var versionFile = Path.Combine(installDir, "version.txt");
            var installedVersion = File.Exists(versionFile) ? File.ReadAllText(versionFile).Trim() : null;

            if (!force && installedVersion == embeddedVersion)
            {
                AnsiConsole.MarkupLine($"[green]Already installed:[/] Felix {embeddedVersion} at [grey]{installDir}[/]");
            }
            else
            {
                var action = installedVersion == null ? "Installing" : $"Upgrading {installedVersion} \u2192";
                AnsiConsole.MarkupLine($"[yellow]{action} Felix {embeddedVersion}[/] \u2192 [grey]{installDir}[/]");

                Directory.CreateDirectory(installDir);
                ExtractEmbeddedScripts(installDir);

                // Copy self (the exe doing the installing) into the install dir
                var selfPath = Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule!.FileName;
                var destExeName = OperatingSystem.IsWindows() ? "felix.exe" : "felix";
                var destExe = Path.Combine(installDir, destExeName);
                File.Copy(selfPath!, destExe, overwrite: true);

                // On Linux/macOS ensure the binary is executable
                if (!OperatingSystem.IsWindows())
                {
                    try { Process.Start("chmod", $"+x \"{destExe}\"")?.WaitForExit(); } catch { }
                }

                AnsiConsole.MarkupLine("[green]\u2713[/] Scripts and felix extracted");
            }

            // ── PATH setup ──────────────────────────────────────────────────
            if (OperatingSystem.IsWindows())
            {
                var userPath = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? "";
                var segments = userPath.Split(';', StringSplitOptions.RemoveEmptyEntries);
                if (!segments.Any(s => string.Equals(s.Trim(), installDir, StringComparison.OrdinalIgnoreCase)))
                {
                    Environment.SetEnvironmentVariable("Path", $"{userPath};{installDir}", EnvironmentVariableTarget.User);
                    AnsiConsole.MarkupLine($"[green]\u2713[/] Added [grey]{installDir}[/] to User PATH");
                }
                else
                {
                    AnsiConsole.MarkupLine("[green]\u2713[/] Already in PATH");
                }
            }
            else
            {
                // Append PATH export to common shell profiles (idempotent)
                var exportLine = $"export PATH=\"$PATH:{installDir}\"";
                var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                var profiles = new[] { ".bashrc", ".zshrc", ".profile" };
                var updated = new List<string>();

                foreach (var p in profiles)
                {
                    var profilePath = Path.Combine(home, p);
                    if (!File.Exists(profilePath)) continue;
                    var content = File.ReadAllText(profilePath);
                    if (content.Contains(installDir)) continue;
                    File.AppendAllText(profilePath, $"\n# Felix CLI\n{exportLine}\n");
                    updated.Add(p);
                }

                if (updated.Count > 0)
                    AnsiConsole.MarkupLine($"[green]\u2713[/] PATH added to: [grey]{string.Join(", ", updated.Select(p => "~/" + p))}[/]");
                else
                    AnsiConsole.MarkupLine("[green]\u2713[/] Already in PATH");
            }

            AnsiConsole.WriteLine();
            AnsiConsole.MarkupLine("[green]Installation complete![/]");
            AnsiConsole.MarkupLine("  1. [yellow]Restart your terminal[/] (or [grey]source ~/.zshrc[/] on macOS/Linux)");
            AnsiConsole.MarkupLine("  2. In a project directory, run: [cyan]felix setup[/]");
        }, forceOpt);

        return cmd;
    }

    static string ReadEmbeddedVersion()
    {
        var asm = typeof(Program).Assembly;
        using var zip = new ZipArchive(asm.GetManifestResourceStream("felix-scripts.zip")
            ?? throw new Exception("Embedded felix-scripts.zip not found"), ZipArchiveMode.Read);
        var entry = zip.GetEntry("version.txt");
        if (entry == null) return "unknown";
        using var reader = new System.IO.StreamReader(entry.Open());
        return reader.ReadToEnd().Trim();
    }

    static void ExtractEmbeddedScripts(string installDir)
    {
        var asm = typeof(Program).Assembly;
        using var zip = new ZipArchive(asm.GetManifestResourceStream("felix-scripts.zip")
            ?? throw new Exception("Embedded felix-scripts.zip not found"), ZipArchiveMode.Read);

        var count = 0;
        foreach (var entry in zip.Entries)
        {
            if (string.IsNullOrEmpty(entry.Name)) continue; // directory marker

            var destPath = Path.GetFullPath(Path.Combine(installDir, entry.FullName));
            // Safety check: ensure extraction stays inside install dir
            if (!destPath.StartsWith(installDir + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                continue;

            Directory.CreateDirectory(Path.GetDirectoryName(destPath)!);
            using var src = entry.Open();
            using var dst = File.Create(destPath);
            src.CopyTo(dst);
            count++;
        }

        AnsiConsole.MarkupLine($"[grey]  Extracted {count} files[/]");
    }

    // Read requirements.json directly — avoids spawning a PowerShell process just for data.
    // Handles both bare array [] and wrapped { "requirements": [] } formats.
    static string ReadRequirementsJson()
    {
        var path = Path.Combine(_felixProjectRoot, ".felix", "requirements.json");
        if (!File.Exists(path)) return "[]";
        try
        {
            var raw = File.ReadAllText(path, Encoding.UTF8).Trim();
            if (raw.StartsWith("{"))
            {
                // Wrapped format: extract the array value
                using var doc = JsonDocument.Parse(raw);
                var root = doc.RootElement;
                // Try common wrapper keys
                foreach (var key in new[] { "requirements", "items", "data" })
                {
                    if (root.TryGetProperty(key, out var arr) && arr.ValueKind == JsonValueKind.Array)
                        return arr.GetRawText();
                }
                // Single-array-value object fallback
                foreach (var prop in root.EnumerateObject())
                {
                    if (prop.Value.ValueKind == JsonValueKind.Array)
                        return prop.Value.GetRawText();
                }
                return "[]";
            }
            return raw;
        }
        catch { return "[]"; }
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

        // Get status data — read file directly, no process spawn
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
            AnsiConsole.MarkupLine("[grey dim][cyan]1[/] Run  [cyan]2[/] Status  [cyan]3[/] List  [cyan]4[/] Validate  [cyan]5[/] Deps  [cyan]6[/] Procs  [cyan]/[/] Commands  [cyan]?[/] Help  [cyan]q[/] Quit[/]");
            AnsiConsole.WriteLine();
            var inputPanel = new Panel(new Markup("[cyan bold]>[/] "))
            {
                Border = BoxBorder.Rounded,
                BorderStyle = Style.Parse("cyan"),
                Padding = new Padding(1, 0),
                Expand = true
            };
            AnsiConsole.Write(inputPanel);
            // Position cursor inside the panel content row after "> "
            try { Console.CursorTop -= 2; Console.CursorLeft = 4; } catch { }

            var key = Console.ReadKey(true);

            // Restore cursor to below the panel before any sub-UI renders
            try { Console.CursorTop += 2; Console.CursorLeft = 0; } catch { }

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
                case '6':
                    await ShowProcs(felixPs1);
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
                "[cyan]1-6[/]     Quick actions\n" +
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
                .EnableSearch()
                .SearchPlaceholderText("[grey](type to filter)[/]")
                .MoreChoicesText("[grey](Move up and down to reveal more)[/]")
                .AddChoices(new[] {
                    "List Requirements",
                    "Show Status",
                    "Run Next",
                    "Run Agent",
                    "Run Loop",
                    "Validate",
                    "Create Spec",
                    "Pull Specs",
                    "Fix Specs",
                    "Check Dependencies",
                    "Build Context",
                    "Active Sessions",
                    "Setup",
                    "< Back"
                }));

        if (command == "< Back") return;

        if (command == "List Requirements")
            await InteractiveList(felixPs1);
        else if (command == "Show Status")
            await ShowStatusUI(felixPs1);
        else if (command == "Check Dependencies")
            await ShowDependencies(felixPs1);
        else if (command == "Run Next")
        {
            AnsiConsole.Clear();
            await ExecutePowerShell(felixPs1, "run-next");
        }
        else if (command == "Run Agent")
            await RunAgentInteractive(felixPs1);
        else if (command == "Run Loop")
        {
            AnsiConsole.Clear();
            await ExecutePowerShell(felixPs1, "loop");
        }
        else if (command == "Validate")
            await ValidateInteractive(felixPs1);
        else if (command == "Create Spec")
            await CreateSpecInteractive(felixPs1);
        else if (command == "Pull Specs")
        {
            AnsiConsole.Clear();
            await ExecutePowerShell(felixPs1, "spec", "pull");
        }
        else if (command == "Fix Specs")
        {
            AnsiConsole.Clear();
            await ExecutePowerShell(felixPs1, "spec", "fix");
        }
        else if (command == "Build Context")
        {
            AnsiConsole.Clear();
            await ExecutePowerShell(felixPs1, "context", "build");
        }
        else if (command == "Active Sessions")
            await ShowProcs(felixPs1);
        else if (command == "Setup")
        {
            AnsiConsole.Clear();
            await ExecutePowerShell(felixPs1, "setup");
        }

        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine("[grey]Press any key to continue...[/]");
        Console.ReadKey(true);
    }

    static async Task InteractiveList(string felixPs1)
    {
        var statusFilter = AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .Title("[cyan]Filter by status?[/]")
                .EnableSearch()
                .SearchPlaceholderText("[grey](type to filter)[/]")
                .AddChoices(new[] { "All", "planned", "in_progress", "done", "complete", "blocked", "< Back" }));

        if (statusFilter == "< Back") return;
        if (statusFilter == "All") statusFilter = null;

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
                .EnableSearch()
                .SearchPlaceholderText("[grey](type to filter)[/]")
                .AddChoices(new[] { "Tree View", "Incomplete Only", "Check Specific Requirement", "< Back" }));

        if (option == "< Back") return;

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
            var output = ReadRequirementsJson();
            var elements = ParseRequirementsJson(output);
            if (elements == null || !elements.Any()) { AnsiConsole.MarkupLine("[yellow]No requirements found. Run felix setup in a project directory.[/]"); return; }

            var reqs = elements
            .Select(r =>
            {
                var id = r.GetProperty("id").GetString() ?? "";
                var label = r.TryGetProperty("title", out var t) ? t.GetString() ?? ""
                           : r.TryGetProperty("spec_path", out var sp) ? sp.GetString() ?? "" : "";
                return $"{id}: {label}";
            })
                .ToList();

            if (reqs.Any())
            {
                var selected = AnsiConsole.Prompt(
                    new SelectionPrompt<string>()
                        .Title("[cyan]Select requirement:[/]")
                        .PageSize(10)
                        .EnableSearch()
                        .SearchPlaceholderText("[grey](type to filter)[/]")
                        .AddChoices(reqs.Prepend("< Back")));

                if (selected != "< Back")
                {
                    var reqId = selected.Split(':')[0];
                    AnsiConsole.Clear();
                    await ExecutePowerShell(felixPs1, "deps", reqId, "--check");
                }
            }
        }

        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine("[grey]Press any key to continue...[/]");
        Console.ReadKey(true);
    }

    static async Task RunAgentInteractive(string felixPs1)
    {
        var output = ReadRequirementsJson();
        var elements = ParseRequirementsJson(output);
        if (elements == null) { AnsiConsole.MarkupLine("[yellow]No requirements found. Run felix setup in a project directory.[/]"); return; }

        var planned = elements
            .Where(r => r.GetProperty("status").GetString() == "planned")
            .Select(r =>
            {
                var id = r.GetProperty("id").GetString() ?? "";
                var label = r.TryGetProperty("title", out var t) ? t.GetString() ?? ""
                           : r.TryGetProperty("spec_path", out var sp) ? sp.GetString() ?? "" : "";
                return $"{id}: {label}";
            })
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
                .EnableSearch()
                .SearchPlaceholderText("[grey](type to filter)[/]")
                .AddChoices(planned.Prepend("< Back")));

        if (selected == "< Back") return;

        var reqId = selected.Split(':')[0];

        AnsiConsole.Clear();
        await ExecutePowerShell(felixPs1, "run", reqId);
    }

    static async Task ValidateInteractive(string felixPs1)
    {
        var output = ReadRequirementsJson();
        var elements = ParseRequirementsJson(output);
        if (elements == null) { AnsiConsole.MarkupLine("[yellow]No requirements found. Run felix setup in a project directory.[/]"); return; }

        var done = elements
            .Where(r => r.GetProperty("status").GetString() == "done")
            .Select(r =>
            {
                var id = r.GetProperty("id").GetString() ?? "";
                var label = r.TryGetProperty("title", out var t) ? t.GetString() ?? ""
                           : r.TryGetProperty("spec_path", out var sp) ? sp.GetString() ?? "" : "";
                return $"{id}: {label}";
            })
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
                .EnableSearch()
                .SearchPlaceholderText("[grey](type to filter)[/]")
                .AddChoices(done.Prepend("< Back")));

        if (selected == "< Back") return;

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

    static Task ShowStatusUI(string felixPs1)
    {
        AnsiConsole.Clear();
        var rule = new Rule("[cyan]Requirements Dashboard[/]").RuleStyle(Style.Parse("cyan dim"));
        AnsiConsole.Write(rule);
        AnsiConsole.WriteLine();

        Dictionary<string, int> statusCounts;
        int total;
        try
        {
            var output = ReadRequirementsJson();
            var doc = JsonDocument.Parse(output);
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
            AnsiConsole.MarkupLine($"[red]Error: {ex.Message}[/]");
            return Task.CompletedTask;
        }

        var table = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Status[/]").RightAligned())
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
        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine($"[grey]Total: {total} requirement{(total != 1 ? "s" : "")}[/]");
        return Task.CompletedTask;
    }

    static async Task ShowProcs(string felixPs1)
    {
        AnsiConsole.Clear();
        var rule = new Rule("[cyan]Active Agent Sessions[/]").RuleStyle(Style.Parse("cyan dim"));
        AnsiConsole.Write(rule);
        AnsiConsole.WriteLine();

        await AnsiConsole.Status()
            .StartAsync("Loading sessions...", async ctx =>
            {
                var output = await ExecutePowerShellCapture(felixPs1, "procs", "list");

                if (string.IsNullOrWhiteSpace(output) || output.Contains("No active sessions"))
                {
                    AnsiConsole.MarkupLine("[grey]No active sessions[/]");
                    return;
                }

                // Parse the output (simple text format from felix procs list)
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

                // Skip header lines and parse session data
                bool foundData = false;
                foreach (var line in lines)
                {
                    // Look for lines with session data (contains hyphens in session ID format)
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
                                $"[grey]{string.Join(" ", parts.Skip(5))}[/]"
                            );
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

        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine("[grey]Press any key to continue...[/]");
        Console.ReadKey(true);
    }
}
