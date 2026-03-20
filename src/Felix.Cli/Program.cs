using System.CommandLine;
using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Nodes;
using Spectre.Console;

namespace Felix.Cli;

class Program
{
    // Set once in Main(); used by ExecutePowerShell* to inject env vars into subprocesses.
    static string _felixInstallDir = "";
    static string _felixProjectRoot = "";
    static readonly object _renderSync = new();
    const int FelixCategoryColumnWidth = 10;
    const string DefaultUpdateRepo = "nsasto/felix";
    const string DefaultWindowsReleaseRid = "win-x64";

    internal sealed record GitHubReleaseAsset(string Name, string DownloadUrl);
    internal sealed record GitHubReleaseMetadata(string TagName, IReadOnlyList<GitHubReleaseAsset> Assets);
    internal sealed record UpdateReleasePlan(string CurrentVersion, string TargetVersion, GitHubReleaseAsset ZipAsset, GitHubReleaseAsset ChecksumAsset, string[] AcceptedChecksumFileNames, bool HasInstalledCopy);
    sealed class FelixRichRunState
    {
        public string CommandLabel { get; init; } = "Felix";
        public string? RunId { get; set; }
        public string? RequirementId { get; set; }
        public string? LatestMode { get; set; }
        public string? AgentName { get; set; }
        public string? CompletionStatus { get; set; }
        public int? Iteration { get; set; }
        public int? MaxIterations { get; set; }
        public int Errors { get; set; }
        public int Warnings { get; set; }
        public int TasksCompleted { get; set; }
        public int TasksFailed { get; set; }
        public int ValidationsPassed { get; set; }
        public int ValidationsFailed { get; set; }
        public double? DurationSeconds { get; set; }
        public string? TerminationReason { get; set; }
    }

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
        rootCommand.AddCommand(CreateListCommand(felixPs1, formatOpt, hiddenAlias: true));
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
            if (verbose) args.Add("--verbose");
            if (quiet) args.Add("--quiet");
            if (sync) args.Add("--sync");

            if (string.Equals(format, "rich", StringComparison.OrdinalIgnoreCase))
                await ExecuteFelixRichCommand(felixPs1, "Run Requirement", args.ToArray());
            else
            {
                args.AddRange(new[] { "--format", format });
                await ExecutePowerShell(felixPs1, args.ToArray());
            }
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

            if (string.Equals(format, "rich", StringComparison.OrdinalIgnoreCase))
                await ExecuteFelixRichCommand(felixPs1, "Continuous Loop", args.ToArray());
            else
            {
                args.AddRange(new[] { "--format", format });
                await ExecutePowerShell(felixPs1, args.ToArray());
            }
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

            if (string.Equals(format, "rich", StringComparison.OrdinalIgnoreCase))
                await ExecuteFelixRichCommand(felixPs1, "Run Next Requirement", args.ToArray());
            else
            {
                args.AddRange(new[] { "--format", format });
                await ExecutePowerShell(felixPs1, args.ToArray());
            }
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
            if (string.IsNullOrEmpty(reqId) && string.Equals(format, "rich", StringComparison.OrdinalIgnoreCase))
            {
                await ShowStatusUI(felixPs1);
                return;
            }

            var args = new List<string> { "status" };
            if (!string.IsNullOrEmpty(reqId)) args.Add(reqId);
            if (format != "rich") args.AddRange(new[] { "--format", format });

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, reqIdArg, formatOpt);

        return cmd;
    }

    static Command CreateListCommand(string felixPs1, Option<string> formatOpt, bool hiddenAlias = false)
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
            if (useUI || string.Equals(format, "rich", StringComparison.OrdinalIgnoreCase))
            {
                await ShowListUI(felixPs1, status, priority, tags, blockedBy, withDeps);
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

        if (hiddenAlias)
            cmd.IsHidden = true;

        return cmd;
    }

    static Command CreateValidateCommand(string felixPs1)
    {
        var reqIdArg = new Argument<string>("requirement-id", "Requirement ID to validate");
        var jsonOpt = new Option<bool>("--json", "Emit machine-readable validation result");

        var cmd = new Command("validate", "Run validation checks")
        {
            reqIdArg,
            jsonOpt
        };

        cmd.SetHandler(async (reqId, jsonOutput) =>
        {
            if (jsonOutput)
            {
                await ExecutePowerShell(felixPs1, "validate", reqId, "--json");
                return;
            }

            await ShowValidateUI(felixPs1, reqId);
        }, reqIdArg, jsonOpt);

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
            if (incomplete)
            {
                ShowDependencyOverviewUI();
                return;
            }

            if (!string.IsNullOrEmpty(reqId))
            {
                ShowRequirementDependenciesUI(reqId, check, tree);
                return;
            }

            Console.Error.WriteLine("Error: requirement-id required unless using --incomplete");
            Environment.Exit(1);
        }, reqIdArg, checkOpt, treeOpt, incompleteOpt);

        return cmd;
    }

    static Command CreateSpecCommand(string felixPs1)
    {
        var cmd = new Command("spec", "Spec management utilities");

        var listCmd = CreateListCommand(felixPs1, new Option<string>("--format", () => "rich", "Output format"));
        listCmd.Description = "List requirements and specs";
        listCmd.IsHidden = false;

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
            RunSpecFixUI(fixDups);
            await Task.CompletedTask;
        }, fixDupsOpt);

        // spec delete
        var delReqIdArg = new Argument<string>("requirement-id", "Requirement ID to delete");
        var assumeYesOpt = new Option<bool>(new[] { "--yes", "-y" }, "Skip the delete confirmation prompt");

        var deleteCmd = new Command("delete", "Delete a specification")
        {
            delReqIdArg,
            assumeYesOpt
        };

        deleteCmd.SetHandler(async (reqId, assumeYes) =>
        {
            DeleteSpecUI(reqId, assumeYes);
            await Task.CompletedTask;
        }, delReqIdArg, assumeYesOpt);

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
            UpdateSpecStatusUI(reqId, status);
            await Task.CompletedTask;
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

        cmd.AddCommand(listCmd);
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
            ShowAgentListUI();
            await Task.CompletedTask;
        });

        // agent current
        var currentCmd = new Command("current", "Show current active agent");
        currentCmd.SetHandler(async () =>
        {
            ShowCurrentAgentUI();
            await Task.CompletedTask;
        });

        // agent use
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
                await UseAgentInteractive(felixPs1, "use");
            else if (string.IsNullOrEmpty(model))
                await ExecutePowerShell(felixPs1, "agent", "use", target);
            else
                await ExecutePowerShell(felixPs1, "agent", "use", target, "--model", model);
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
                await UseAgentInteractive(felixPs1, "set-default");
            else if (string.IsNullOrEmpty(model))
                await ExecutePowerShell(felixPs1, "agent", "set-default", target);
            else
                await ExecutePowerShell(felixPs1, "agent", "set-default", target, "--model", model);
        }, setDefaultTargetArg, setDefaultModelOpt);

        // agent test
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
            await ExecutePowerShell(felixPs1, "agent", "register");
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

    static Command CreateSetupCommand(string felixPs1)
    {
        var cmd = new Command("setup", "Initialize or re-configure a Felix project in the current directory");

        cmd.SetHandler(async () =>
        {
            await RunSetupInteractive(felixPs1);
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
            await ShowVersionUI();
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

            var normalizedSubArgs = subArgs.Length == 0 ? Array.Empty<string>() : subArgs;
            var subCommand = normalizedSubArgs.Length == 0 ? "list" : normalizedSubArgs[0];
            if (string.Equals(subCommand, "list", StringComparison.OrdinalIgnoreCase))
            {
                await ShowProcessSessionsUI();
                return;
            }

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
        var psi = CreateFelixProcessStartInfo(felixPs1, args, createNoWindow: false);

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

    static async Task ExecuteFelixRichCommand(string felixPs1, string commandLabel, params string[] args)
    {
        var commandArgs = new List<string>(args) { "--format", "json" };
        var psi = CreateFelixProcessStartInfo(felixPs1, commandArgs, createNoWindow: true);
        using var process = new Process { StartInfo = psi };
        var state = new FelixRichRunState { CommandLabel = commandLabel };
        bool wasCancelled = false;
        int cancelPressCount = 0;
        int forceExitInitiated = 0;
        var forceExitRequested = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);

        ConsoleCancelEventHandler? cancelHandler = (_, eventArgs) =>
        {
            eventArgs.Cancel = true;
            wasCancelled = true;

            var pressCount = Interlocked.Increment(ref cancelPressCount);

            lock (_renderSync)
            {
                if (pressCount == 1)
                {
                    state.TerminationReason = "cancel requested";
                    AnsiConsole.MarkupLine("[yellow]Cancellation requested.[/] [grey]Press Ctrl+C again to force exit.[/]");
                }
                else if (pressCount == 2)
                {
                    state.TerminationReason = "forced after second Ctrl+C";
                    AnsiConsole.MarkupLine("[red]Force exiting...[/] [grey]Killing child process tree.[/]");
                }
            }

            if (pressCount < 2)
                return;

            if (Interlocked.Exchange(ref forceExitInitiated, 1) != 0)
                return;

            forceExitRequested.TrySetResult(true);

            try
            {
                if (!process.HasExited)
                    process.Kill(entireProcessTree: true);
            }
            catch
            {
            }

            Environment.ExitCode = 130;
            Environment.Exit(130);
        };

        lock (_renderSync)
        {
            AnsiConsole.Clear();
            AnsiConsole.Write(new Rule($"[cyan]{commandLabel.EscapeMarkup()}[/]").RuleStyle(Style.Parse("cyan dim")));
            AnsiConsole.WriteLine();
        }

        Console.CancelKeyPress += cancelHandler;

        try
        {
            process.Start();

            var stdoutTask = ConsumeFelixOutputAsync(process.StandardOutput, state);
            var stderrTask = ConsumeFelixErrorAsync(process.StandardError, state);
            var waitForExitTask = process.WaitForExitAsync();

            await Task.WhenAny(waitForExitTask, forceExitRequested.Task);

            if (forceExitRequested.Task.IsCompleted)
            {
                try
                {
                    if (!process.HasExited)
                        process.Kill(entireProcessTree: true);
                }
                catch
                {
                }
            }

            await Task.WhenAll(stdoutTask, stderrTask, waitForExitTask);

            RenderFelixRunSummary(state, wasCancelled ? 130 : process.ExitCode, wasCancelled);
            Environment.ExitCode = wasCancelled ? 130 : process.ExitCode;
        }
        finally
        {
            Console.CancelKeyPress -= cancelHandler;

            if (!process.HasExited)
            {
                try { process.Kill(entireProcessTree: true); } catch { }
            }
        }
    }

    static ProcessStartInfo CreateFelixProcessStartInfo(string felixPs1, IEnumerable<string> args, bool createNoWindow)
    {
        var quotedArgs = string.Join(" ", args.Select(QuotePowerShellArgument));
        var pwshPath = FindPowerShell();

        var psi = new ProcessStartInfo
        {
            FileName = pwshPath,
            Arguments = $"-NoProfile -File \"{felixPs1}\" {quotedArgs}",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = false,
            CreateNoWindow = createNoWindow
        };

        if (!string.IsNullOrEmpty(_felixInstallDir))
            psi.Environment["FELIX_INSTALL_DIR"] = _felixInstallDir;
        if (!string.IsNullOrEmpty(_felixProjectRoot))
            psi.Environment["FELIX_PROJECT_ROOT"] = _felixProjectRoot;

        return psi;
    }

    static string QuotePowerShellArgument(string value)
    {
        if (string.IsNullOrEmpty(value))
            return "\"\"";

        return value.Any(ch => char.IsWhiteSpace(ch) || ch == '"')
            ? $"\"{value.Replace("\"", "\\\"", StringComparison.Ordinal)}\""
            : value;
    }

    static async Task ConsumeFelixOutputAsync(StreamReader reader, FelixRichRunState state)
    {
        while (true)
        {
            var line = await reader.ReadLineAsync();
            if (line == null)
                break;

            if (string.IsNullOrWhiteSpace(line))
                continue;

            RenderFelixOutputLine(line, state);
        }
    }

    static async Task ConsumeFelixErrorAsync(StreamReader reader, FelixRichRunState state)
    {
        while (true)
        {
            var line = await reader.ReadLineAsync();
            if (line == null)
                break;

            if (string.IsNullOrWhiteSpace(line))
                continue;

            state.Errors++;
            lock (_renderSync)
                RenderFelixDetailLine("STDERR", "red", line.Trim().EscapeMarkup());
        }
    }

    static void RenderFelixOutputLine(string line, FelixRichRunState state)
    {
        var trimmed = line.Trim();
        try
        {
            using var doc = JsonDocument.Parse(trimmed);
            var root = doc.RootElement;
            if (!root.TryGetProperty("type", out var typeElement) || !root.TryGetProperty("data", out var dataElement))
            {
                lock (_renderSync)
                    AnsiConsole.MarkupLine($"[grey]{trimmed.EscapeMarkup()}[/]");
                return;
            }

            RenderFelixEvent(typeElement.GetString() ?? string.Empty, dataElement, state);
        }
        catch (JsonException)
        {
            lock (_renderSync)
                AnsiConsole.MarkupLine($"[grey]{trimmed.EscapeMarkup()}[/]");
        }
    }

    static void RenderFelixEvent(string eventType, JsonElement data, FelixRichRunState state)
    {
        switch (eventType)
        {
            case "run_started":
                {
                    state.RunId = GetJsonString(data, "run_id");
                    state.RequirementId = GetJsonString(data, "requirement_id");
                    var body = new Markup(
                        $"[grey]Run ID[/] [white]{(state.RunId ?? "init").EscapeMarkup()}[/]\n" +
                        $"[grey]Requirement[/] [white]{(state.RequirementId ?? "loop").EscapeMarkup()}[/]");
                    lock (_renderSync)
                        AnsiConsole.Write(new Panel(body)
                        {
                            Header = new PanelHeader("[cyan]Run Started[/]"),
                            Border = BoxBorder.Rounded,
                            BorderStyle = Style.Parse("cyan")
                        });
                    break;
                }
            case "iteration_started":
                {
                    state.Iteration = GetJsonInt(data, "iteration");
                    state.MaxIterations = GetJsonInt(data, "max_iterations");
                    state.LatestMode = GetJsonString(data, "mode");
                    var mode = (state.LatestMode ?? "running").ToUpperInvariant().EscapeMarkup();
                    var label = state.Iteration.HasValue && state.MaxIterations.HasValue
                        ? $"Iteration {state.Iteration}/{state.MaxIterations} • {mode}"
                        : $"{mode}";
                    lock (_renderSync)
                    {
                        AnsiConsole.WriteLine();
                        AnsiConsole.Write(new Rule($"[yellow]{label}[/]").RuleStyle(Style.Parse("yellow dim")));
                        AnsiConsole.WriteLine();
                    }
                    break;
                }
            case "iteration_completed":
                {
                    var outcome = GetJsonString(data, "outcome") ?? "unknown";
                    var color = string.Equals(outcome, "success", StringComparison.OrdinalIgnoreCase) ? "green" : "red";
                    lock (_renderSync)
                        RenderFelixDetailLine("Iteration", color, outcome.EscapeMarkup());
                    break;
                }
            case "log":
                {
                    var level = GetJsonString(data, "level") ?? "info";
                    var component = GetJsonString(data, "component");
                    var message = GetJsonString(data, "message") ?? string.Empty;
                    if (string.Equals(level, "warn", StringComparison.OrdinalIgnoreCase)) state.Warnings++;
                    if (string.Equals(level, "error", StringComparison.OrdinalIgnoreCase)) state.Errors++;
                    var color = level switch
                    {
                        "debug" => "grey",
                        "info" => "white",
                        "warn" => "yellow",
                        "error" => "red",
                        _ => "white"
                    };
                    var detail = string.IsNullOrWhiteSpace(component)
                        ? message.EscapeMarkup()
                        : $"[grey][[{component.EscapeMarkup()}]][/] {message.EscapeMarkup()}";
                    lock (_renderSync)
                        RenderFelixDetailLine(level.ToUpperInvariant(), color, detail);
                    break;
                }
            case "agent_execution_started":
                {
                    state.AgentName = GetJsonString(data, "agent_name") ?? state.AgentName;
                    lock (_renderSync)
                        RenderFelixDetailLine("Agent", "cyan", $"{(state.AgentName ?? "unknown").EscapeMarkup()} [grey]started[/]");
                    break;
                }
            case "agent_execution_completed":
                {
                    var duration = GetJsonDouble(data, "duration_seconds");
                    if (duration.HasValue)
                        state.DurationSeconds = duration;
                    lock (_renderSync)
                        RenderFelixDetailLine("Agent", "green", $"execution complete{(duration.HasValue ? $" [grey]({duration.Value:F1}s)[/]" : string.Empty)}");
                    break;
                }
            case "validation_started":
                {
                    var validationType = GetJsonString(data, "validation_type") ?? "validation";
                    lock (_renderSync)
                        RenderFelixDetailLine("Validation", "blue", $"started [grey]({validationType.EscapeMarkup()})[/]");
                    break;
                }
            case "validation_command_started":
                {
                    var command = GetJsonString(data, "command") ?? string.Empty;
                    lock (_renderSync)
                        RenderFelixDetailLine("Running", "blue", command.EscapeMarkup());
                    break;
                }
            case "validation_command_completed":
                {
                    var passed = GetJsonBool(data, "passed") == true;
                    if (passed) state.ValidationsPassed++; else state.ValidationsFailed++;
                    var label = passed ? "passed" : $"failed (exit {GetJsonInt(data, "exit_code") ?? -1})";
                    var color = passed ? "green" : "red";
                    lock (_renderSync)
                        RenderFelixDetailLine("Validation", color, label.EscapeMarkup());
                    break;
                }
            case "task_completed":
                {
                    var signal = GetJsonString(data, "signal") ?? string.Empty;
                    if (signal.Contains("FAIL", StringComparison.OrdinalIgnoreCase)) state.TasksFailed++; else state.TasksCompleted++;
                    lock (_renderSync)
                        RenderFelixDetailLine("Task", "green", signal.EscapeMarkup());
                    break;
                }
            case "state_transitioned":
                {
                    var from = GetJsonString(data, "from") ?? "unknown";
                    var to = GetJsonString(data, "to") ?? "unknown";
                    state.LatestMode = to;
                    lock (_renderSync)
                        RenderFelixDetailLine("State", "grey", $"{from.EscapeMarkup()} [grey]->[/] {to.EscapeMarkup()}");
                    break;
                }
            case "artifact_created":
                {
                    var path = GetJsonString(data, "path") ?? string.Empty;
                    lock (_renderSync)
                        RenderFelixDetailLine("Artifact", "grey", path.EscapeMarkup());
                    break;
                }
            case "error_occurred":
                {
                    state.Errors++;
                    var errorType = GetJsonString(data, "error_type") ?? "error";
                    var message = GetJsonString(data, "message") ?? string.Empty;
                    lock (_renderSync)
                        RenderFelixDetailLine("Error", "red", $"{errorType.EscapeMarkup()} [grey]-[/] {message.EscapeMarkup()}");
                    break;
                }
            case "run_completed":
                {
                    state.CompletionStatus = GetJsonString(data, "status") ?? state.CompletionStatus;
                    var duration = GetJsonDouble(data, "duration_seconds");
                    if (duration.HasValue)
                        state.DurationSeconds = duration;
                    break;
                }
            default:
                {
                    lock (_renderSync)
                        RenderFelixDetailLine("Event", "grey", eventType.EscapeMarkup());
                    break;
                }
        }
    }

    static void RenderFelixDetailLine(string category, string color, string detail)
    {
        var paddedCategory = category.PadRight(FelixCategoryColumnWidth).EscapeMarkup();
        AnsiConsole.MarkupLine($"[{color}]{paddedCategory}[/] {detail}");
    }

    static void RenderFelixRunSummary(FelixRichRunState state, int exitCode, bool wasCancelled)
    {
        var status = wasCancelled
            ? "cancelled"
            : string.IsNullOrWhiteSpace(state.CompletionStatus)
                ? (exitCode == 0 ? "success" : "failed")
                : state.CompletionStatus!;
        var color = exitCode == 0 && !wasCancelled ? "green" : wasCancelled ? "yellow" : "red";

        var table = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Field[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Value[/]"));

        table.AddRow("Status", $"[{color}]{status.EscapeMarkup()}[/]");
        table.AddRow("Exit Code", $"[{color}]{exitCode}[/]");
        if (!string.IsNullOrWhiteSpace(state.TerminationReason)) table.AddRow("Termination", $"[white]{state.TerminationReason!.EscapeMarkup()}[/]");
        if (!string.IsNullOrWhiteSpace(state.RequirementId)) table.AddRow("Requirement", $"[white]{state.RequirementId!.EscapeMarkup()}[/]");
        if (!string.IsNullOrWhiteSpace(state.RunId)) table.AddRow("Run ID", $"[white]{state.RunId!.EscapeMarkup()}[/]");
        if (!string.IsNullOrWhiteSpace(state.AgentName)) table.AddRow("Agent", $"[white]{state.AgentName!.EscapeMarkup()}[/]");
        if (!string.IsNullOrWhiteSpace(state.LatestMode)) table.AddRow("Last Mode", $"[white]{state.LatestMode!.EscapeMarkup()}[/]");
        if (state.Iteration.HasValue && state.MaxIterations.HasValue) table.AddRow("Iteration", $"[white]{state.Iteration}/{state.MaxIterations}[/]");
        if (state.DurationSeconds.HasValue) table.AddRow("Duration", $"[white]{state.DurationSeconds.Value:F1}s[/]");
        table.AddRow("Warnings", state.Warnings == 0 ? "[grey]0[/]" : $"[yellow]{state.Warnings}[/]");
        table.AddRow("Errors", state.Errors == 0 ? "[grey]0[/]" : $"[red]{state.Errors}[/]");
        table.AddRow("Tasks", $"[green]{state.TasksCompleted} complete[/] / [red]{state.TasksFailed} failed[/]");
        table.AddRow("Validations", $"[green]{state.ValidationsPassed} passed[/] / [red]{state.ValidationsFailed} failed[/]");

        lock (_renderSync)
        {
            AnsiConsole.WriteLine();
            AnsiConsole.Write(new Panel(table)
            {
                Header = new PanelHeader($"[{color}]Execution Summary[/]"),
                Border = BoxBorder.Rounded,
                BorderStyle = Style.Parse(color)
            });
            AnsiConsole.WriteLine();
        }
    }

    static string? GetJsonString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) || value.ValueKind == JsonValueKind.Null)
            return null;

        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString(),
            JsonValueKind.Number => value.ToString(),
            JsonValueKind.True => bool.TrueString,
            JsonValueKind.False => bool.FalseString,
            _ => value.ToString()
        };
    }

    static int? GetJsonInt(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) || value.ValueKind != JsonValueKind.Number)
            return null;

        return value.TryGetInt32(out var number) ? number : null;
    }

    static double? GetJsonDouble(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) || value.ValueKind != JsonValueKind.Number)
            return null;

        return value.TryGetDouble(out var number) ? number : null;
    }

    static bool? GetJsonBool(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value))
            return null;

        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => null
        };
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
            var id = req.GetProperty("id").GetString() ?? "";
            var title = req.TryGetProperty("title", out var titleProp) ? titleProp.GetString() ?? ""
                      : req.TryGetProperty("spec_path", out var spProp) ? spProp.GetString() ?? ""
                      : "";
            var status = req.GetProperty("status").GetString() ?? "";
            var priority = req.TryGetProperty("priority", out var p) ? p.GetString() : "medium";
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

            if (title.Length > 57) title = title.Substring(0, 54) + "...";

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

    static async Task ShowVersionUI()
    {
        var installDir = GetInstallDirectory();
        var installedVersion = GetInstalledVersion(installDir);
        var embeddedVersion = ReadEmbeddedVersion();
        var currentVersion = installedVersion ?? embeddedVersion;

        string branch = "-";
        string commit = "-";
        try
        {
            branch = (await CaptureGitOutputAsync("rev-parse --abbrev-ref HEAD")) ?? "-";
            commit = (await CaptureGitOutputAsync("rev-parse --short HEAD")) ?? "-";
        }
        catch { }

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Felix Version[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var table = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Field[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Value[/]"));

        table.AddRow("Version", $"[white]{currentVersion.EscapeMarkup()}[/]");
        table.AddRow("Embedded", $"[grey]{embeddedVersion.EscapeMarkup()}[/]");
        table.AddRow("Installed", string.IsNullOrWhiteSpace(installedVersion) ? "[grey]not installed[/]" : $"[white]{installedVersion!.EscapeMarkup()}[/]");
        table.AddRow("Repository", $"[white]{_felixProjectRoot.EscapeMarkup()}[/]");
        table.AddRow("Branch", $"[white]{branch.EscapeMarkup()}[/]");
        table.AddRow("Commit", $"[white]{commit.EscapeMarkup()}[/]");

        AnsiConsole.Write(new Panel(table)
        {
            Header = new PanelHeader("[cyan]Version Information[/]"),
            Border = BoxBorder.Rounded,
            BorderStyle = Style.Parse("cyan")
        });
        AnsiConsole.WriteLine();
    }

    static async Task<string?> CaptureGitOutputAsync(string gitArguments)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "git",
            Arguments = gitArguments,
            WorkingDirectory = _felixProjectRoot,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = Process.Start(psi);
        if (process == null)
            return null;

        var output = (await process.StandardOutput.ReadToEndAsync()).Trim();
        await process.WaitForExitAsync();
        return process.ExitCode == 0 && !string.IsNullOrWhiteSpace(output) ? output : null;
    }

    sealed record ActiveSessionInfo(string SessionId, string RequirementId, int Pid, string Agent, string Status, DateTime StartTimeUtc);

    static Task ShowProcessSessionsUI()
    {
        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Active Sessions[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var sessions = ReadActiveSessions();
        if (sessions.Count == 0)
        {
            AnsiConsole.MarkupLine("[grey]No active sessions.[/]");
            AnsiConsole.WriteLine();
            return Task.CompletedTask;
        }

        var table = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Session[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Requirement[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Agent[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]PID[/]").RightAligned().NoWrap())
            .AddColumn(new TableColumn("[yellow]Duration[/]").RightAligned().NoWrap())
            .AddColumn(new TableColumn("[yellow]Status[/]").Centered().NoWrap());

        foreach (var session in sessions.OrderByDescending(session => session.StartTimeUtc))
        {
            var duration = DateTime.UtcNow - session.StartTimeUtc;
            var durationText = duration.TotalHours >= 1 ? duration.ToString(@"hh\:mm\:ss") : duration.ToString(@"mm\:ss");
            var statusColor = string.Equals(session.Status, "running", StringComparison.OrdinalIgnoreCase) ? "green" : "yellow";
            table.AddRow(
                session.SessionId.EscapeMarkup(),
                session.RequirementId.EscapeMarkup(),
                session.Agent.EscapeMarkup(),
                session.Pid.ToString(),
                durationText,
                $"[{statusColor}]{session.Status.EscapeMarkup()}[/]");
        }

        AnsiConsole.Write(table);
        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine("[grey]Use [cyan]felix procs kill <session-id>[/] or [cyan]felix procs kill all[/] to terminate sessions.[/]");
        return Task.CompletedTask;
    }

    static List<ActiveSessionInfo> ReadActiveSessions()
    {
        var sessionsPath = Path.Combine(_felixProjectRoot, ".felix", "sessions.json");
        if (!File.Exists(sessionsPath))
            return new List<ActiveSessionInfo>();

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(sessionsPath));
            if (doc.RootElement.ValueKind != JsonValueKind.Array)
                return new List<ActiveSessionInfo>();

            var sessions = new List<ActiveSessionInfo>();
            foreach (var session in doc.RootElement.EnumerateArray())
            {
                var pid = GetJsonInt(session, "pid");
                var sessionId = GetJsonString(session, "session_id");
                var requirementId = GetJsonString(session, "requirement_id") ?? "-";
                var agent = GetJsonString(session, "agent") ?? "-";
                var status = GetJsonString(session, "status") ?? "unknown";
                var startTimeText = GetJsonString(session, "start_time");

                if (string.IsNullOrWhiteSpace(sessionId) || !pid.HasValue)
                    continue;

                if (!IsProcessRunning(pid.Value))
                    continue;

                var startTimeUtc = DateTime.TryParse(startTimeText, out var parsedStart)
                    ? parsedStart.ToUniversalTime()
                    : DateTime.UtcNow;

                sessions.Add(new ActiveSessionInfo(sessionId!, requirementId, pid.Value, agent, status, startTimeUtc));
            }

            return sessions;
        }
        catch
        {
            return new List<ActiveSessionInfo>();
        }
    }

    static bool IsProcessRunning(int processId)
    {
        try
        {
            using var process = Process.GetProcessById(processId);
            return !process.HasExited;
        }
        catch
        {
            return false;
        }
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

            AnsiConsole.Clear();
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

        AnsiConsole.Clear();
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

        AnsiConsole.Clear();
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

    static void UpdateSpecStatusUI(string requirementId, string status)
    {
        if (!IsValidRequirementId(requirementId))
        {
            AnsiConsole.MarkupLine("[red]Invalid requirement ID format. Expected S-NNNN (for example S-0001).[/]");
            Environment.ExitCode = 1;
            return;
        }

        var normalizedStatus = NormalizeRequirementStatus(status);
        var allowedStatuses = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "draft", "planned", "in_progress", "blocked", "complete", "done"
        };
        if (!allowedStatuses.Contains(normalizedStatus))
        {
            AnsiConsole.MarkupLine($"[red]Invalid status '{status.EscapeMarkup()}'. Allowed: {string.Join(", ", allowedStatuses).EscapeMarkup()}[/]");
            Environment.ExitCode = 1;
            return;
        }

        var document = LoadRequirementsDocument();
        var requirements = GetRequirementsArray(document);
        var requirement = FindRequirementNode(requirements, requirementId);
        if (requirement == null)
        {
            AnsiConsole.MarkupLine($"[red]Requirement {requirementId.EscapeMarkup()} not found in requirements.json.[/]");
            Environment.ExitCode = 1;
            return;
        }

        requirement["status"] = normalizedStatus;
        SaveRequirementsDocument(document);

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Specification Status Updated[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var summary = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Field[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Value[/]"));
        summary.AddRow("Requirement", requirementId.EscapeMarkup());
        summary.AddRow("Title", (GetJsonString(requirement.AsObject(), "title") ?? "-").EscapeMarkup());
        summary.AddRow("Status", RenderStatusMarkup(normalizedStatus));

        AnsiConsole.Write(summary);
        AnsiConsole.WriteLine();
        Environment.ExitCode = 0;
    }

    static void DeleteSpecUI(string requirementId, bool assumeYes)
    {
        if (!IsValidRequirementId(requirementId))
        {
            AnsiConsole.MarkupLine("[red]Invalid requirement ID format. Expected S-NNNN (for example S-0001).[/]");
            Environment.ExitCode = 1;
            return;
        }

        var document = LoadRequirementsDocument();
        var requirements = GetRequirementsArray(document);
        var requirement = FindRequirementNode(requirements, requirementId);
        if (requirement == null)
        {
            AnsiConsole.MarkupLine($"[red]Requirement {requirementId.EscapeMarkup()} not found in requirements.json.[/]");
            Environment.ExitCode = 1;
            return;
        }

        var specPathValue = GetJsonString(requirement.AsObject(), "spec_path") ?? string.Empty;
        var specPath = string.IsNullOrWhiteSpace(specPathValue)
            ? Path.Combine(_felixProjectRoot, "specs", requirementId + ".md")
            : Path.GetFullPath(Path.Combine(_felixProjectRoot, specPathValue.Replace('/', Path.DirectorySeparatorChar)));

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[yellow]Delete Specification[/]").RuleStyle(Style.Parse("yellow dim")));
        AnsiConsole.WriteLine();

        var details = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Field[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Value[/]"));
        details.AddRow("Requirement", requirementId.EscapeMarkup());
        details.AddRow("Title", (GetJsonString(requirement.AsObject(), "title") ?? "-").EscapeMarkup());
        details.AddRow("Path", specPath.EscapeMarkup());
        details.AddRow("File", File.Exists(specPath) ? Path.GetFileName(specPath).EscapeMarkup() : "[grey](not found)[/]");
        AnsiConsole.Write(details);
        AnsiConsole.WriteLine();

        if (!assumeYes && !AnsiConsole.Confirm("Delete this specification?", false))
        {
            AnsiConsole.MarkupLine("[grey]Deletion cancelled.[/]");
            Environment.ExitCode = 0;
            return;
        }

        if (File.Exists(specPath))
            File.Delete(specPath);

        for (var index = 0; index < requirements.Count; index++)
        {
            if (requirements[index] is JsonObject reqObj && string.Equals(GetJsonString(reqObj, "id"), requirementId, StringComparison.OrdinalIgnoreCase))
            {
                requirements.RemoveAt(index);
                break;
            }
        }

        SaveRequirementsDocument(document);
        AnsiConsole.MarkupLine($"[green]Deleted specification {requirementId.EscapeMarkup()}.[/]");
        Environment.ExitCode = 0;
    }

    static void RunSpecFixUI(bool fixDuplicates)
    {
        var specsDir = Path.Combine(_felixProjectRoot, "specs");
        if (!Directory.Exists(specsDir))
        {
            AnsiConsole.MarkupLine($"[red]Specs directory not found: {specsDir.EscapeMarkup()}[/]");
            Environment.ExitCode = 1;
            return;
        }

        var document = LoadRequirementsDocument();
        var requirements = GetRequirementsArray(document);
        var specFiles = Directory.GetFiles(specsDir, "S-*.md", SearchOption.TopDirectoryOnly)
            .Select(path => new FileInfo(path))
            .OrderBy(file => file.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();

        var added = new List<string>();
        var updated = new List<string>();
        var duplicates = new List<string>();
        var fixedItems = new List<string>();
        var errors = new List<string>();
        var processedIds = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var allSpecIds = specFiles
            .Select(file => TryParseRequirementId(file.Name))
            .Where(id => id != null)
            .Select(id => int.Parse(id!.AsSpan(2)))
            .ToList();
        var maxSpecId = allSpecIds.Count > 0 ? allSpecIds.Max() : 0;

        var existingById = requirements
            .OfType<JsonObject>()
            .Select(node => node.DeepClone().AsObject())
            .Where(node => !string.IsNullOrWhiteSpace(GetJsonString(node, "id")))
            .ToDictionary(node => GetJsonString(node, "id")!, node => node, StringComparer.OrdinalIgnoreCase);

        var currentSpecFiles = new List<FileInfo>();
        foreach (var originalFile in specFiles)
        {
            var specFile = originalFile;
            var reqId = TryParseRequirementId(specFile.Name);
            if (reqId == null)
            {
                errors.Add($"Invalid filename format: {specFile.Name}");
                continue;
            }

            if (processedIds.ContainsKey(reqId))
            {
                if (!fixDuplicates)
                {
                    duplicates.Add(specFile.Name);
                    continue;
                }

                maxSpecId = GetNextAvailableSpecNumber(maxSpecId + 1, specsDir);
                var newReqId = $"S-{maxSpecId:D4}";
                var newFileName = reqId + specFile.Name.Substring(reqId.Length);
                newFileName = newFileName.Replace(reqId, newReqId, StringComparison.OrdinalIgnoreCase);
                var newPath = Path.Combine(specsDir, newFileName);
                File.Move(specFile.FullName, newPath);
                fixedItems.Add($"{specFile.Name} -> {newFileName}");
                specFile = new FileInfo(newPath);
                reqId = newReqId;
            }

            processedIds[reqId] = specFile.Name;

            if (existingById.TryGetValue(reqId, out var existing))
            {
                var relativePath = ToRequirementRelativeSpecPath(specFile.Name);
                if (!string.Equals(GetJsonString(existing, "spec_path"), relativePath, StringComparison.OrdinalIgnoreCase))
                    updated.Add(reqId);
                existingById.Remove(reqId);
            }
            else
            {
                added.Add(reqId);
            }

            currentSpecFiles.Add(specFile);
        }

        var orphaned = existingById.Keys.OrderBy(id => id, StringComparer.OrdinalIgnoreCase).ToList();
        var defaultStatus = added.Count > 0 ? PromptForDefaultSpecStatus() : "draft";
        var rebuiltRequirements = new JsonArray();

        foreach (var specFile in currentSpecFiles.OrderBy(file => file.Name, StringComparer.OrdinalIgnoreCase))
        {
            var reqId = TryParseRequirementId(specFile.Name)!;
            var original = requirements
                .OfType<JsonObject>()
                .FirstOrDefault(node => string.Equals(GetJsonString(node, "id"), reqId, StringComparison.OrdinalIgnoreCase));

            var metaPath = Path.Combine(specsDir, Path.GetFileNameWithoutExtension(specFile.Name) + ".meta.json");
            var meta = LoadOptionalJsonObject(metaPath);
            var resolvedStatus = GetJsonString(original?.AsObject() ?? new JsonObject(), "status") ?? defaultStatus;
            var metaStatus = GetJsonString(meta ?? new JsonObject(), "status");
            if (!string.IsNullOrWhiteSpace(metaStatus))
                resolvedStatus = metaStatus!;

            var title = GetSpecTitle(specFile.FullName, reqId, GetJsonString(original?.AsObject() ?? new JsonObject(), "title"));
            var reqNode = new JsonObject
            {
                ["id"] = reqId,
                ["spec_path"] = ToRequirementRelativeSpecPath(specFile.Name),
                ["status"] = resolvedStatus
            };

            if (!string.IsNullOrWhiteSpace(title))
                reqNode["title"] = title;
            if (GetJsonBool(original?.AsObject() ?? new JsonObject(), "commit_on_complete", false))
                reqNode["commit_on_complete"] = true;

            rebuiltRequirements.Add(reqNode);

            if (original == null && !File.Exists(metaPath))
            {
                var newMeta = new JsonObject
                {
                    ["status"] = resolvedStatus,
                    ["priority"] = "medium",
                    ["tags"] = new JsonArray(),
                    ["depends_on"] = new JsonArray(),
                    ["updated_at"] = DateTime.Now.ToString("yyyy-MM-dd")
                };
                File.WriteAllText(metaPath, newMeta.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine);
            }
        }

        var sortedRequirements = rebuiltRequirements
            .OfType<JsonObject>()
            .OrderBy(node => GetJsonString(node, "id"), StringComparer.OrdinalIgnoreCase)
            .Cast<JsonNode>()
            .ToArray();
        document["requirements"] = new JsonArray(sortedRequirements);
        SaveRequirementsDocument(document);

        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Specification Fix[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var summary = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Metric[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Count[/]").RightAligned().NoWrap());
        summary.AddRow("Total specs", currentSpecFiles.Count.ToString());
        summary.AddRow("Added", added.Count.ToString());
        summary.AddRow("Updated", updated.Count.ToString());
        summary.AddRow("Fixed duplicates", fixedItems.Count.ToString());
        summary.AddRow("Duplicate skips", duplicates.Count.ToString());
        summary.AddRow("Orphaned", orphaned.Count.ToString());
        summary.AddRow("Errors", errors.Count.ToString());
        AnsiConsole.Write(summary);
        AnsiConsole.WriteLine();

        if (fixedItems.Count > 0)
            AnsiConsole.MarkupLine($"[cyan]Fixed:[/] {string.Join(", ", fixedItems.Select(item => item.EscapeMarkup()))}");
        if (duplicates.Count > 0)
            AnsiConsole.MarkupLine($"[magenta]Duplicates skipped:[/] {string.Join(", ", duplicates.Select(item => item.EscapeMarkup()))}");
        if (orphaned.Count > 0)
            AnsiConsole.MarkupLine($"[yellow]Orphaned:[/] {string.Join(", ", orphaned.Select(item => item.EscapeMarkup()))}");
        if (errors.Count > 0)
            AnsiConsole.MarkupLine($"[red]Errors:[/] {string.Join(" | ", errors.Select(item => item.EscapeMarkup()))}");

        Environment.ExitCode = errors.Count == 0 ? 0 : 1;
    }

    static JsonObject LoadRequirementsDocument()
    {
        var path = Path.Combine(_felixProjectRoot, ".felix", "requirements.json");
        if (!File.Exists(path))
            return new JsonObject { ["requirements"] = new JsonArray() };

        try
        {
            var raw = File.ReadAllText(path, Encoding.UTF8).Trim();
            if (string.IsNullOrWhiteSpace(raw))
                return new JsonObject { ["requirements"] = new JsonArray() };

            var node = JsonNode.Parse(raw);
            if (node is JsonArray array)
                return new JsonObject { ["requirements"] = array };
            if (node is JsonObject obj)
            {
                if (obj["requirements"] is JsonObject singleReq)
                    obj["requirements"] = new JsonArray(singleReq);
                else if (obj["requirements"] is not JsonArray)
                    obj["requirements"] = new JsonArray();
                return obj;
            }
        }
        catch { }

        return new JsonObject { ["requirements"] = new JsonArray() };
    }

    static JsonArray GetRequirementsArray(JsonObject document)
    {
        if (document["requirements"] is JsonArray array)
            return array;

        var created = new JsonArray();
        document["requirements"] = created;
        return created;
    }

    static JsonObject? FindRequirementNode(JsonArray requirements, string requirementId)
        => requirements
            .OfType<JsonObject>()
            .FirstOrDefault(node => string.Equals(GetJsonString(node, "id"), requirementId, StringComparison.OrdinalIgnoreCase));

    static void SaveRequirementsDocument(JsonObject document)
    {
        var path = Path.Combine(_felixProjectRoot, ".felix", "requirements.json");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, document.ToJsonString(new JsonSerializerOptions { WriteIndented = true }) + Environment.NewLine, Encoding.UTF8);
    }

    static bool IsValidRequirementId(string requirementId)
        => System.Text.RegularExpressions.Regex.IsMatch(requirementId, "^S-\\d{4}$", System.Text.RegularExpressions.RegexOptions.IgnoreCase);

    static string NormalizeRequirementStatus(string status)
        => string.Equals(status, "in-progress", StringComparison.OrdinalIgnoreCase) ? "in_progress" : status.ToLowerInvariant();

    static string? TryParseRequirementId(string fileName)
    {
        var match = System.Text.RegularExpressions.Regex.Match(fileName, "^(S-\\d{4})", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        return match.Success ? match.Groups[1].Value.ToUpperInvariant() : null;
    }

    static int GetNextAvailableSpecNumber(int startFrom, string specsDir)
    {
        var nextId = startFrom;
        while (File.Exists(Path.Combine(specsDir, $"S-{nextId:D4}.md")) || Directory.GetFiles(specsDir, $"S-{nextId:D4}-*.md").Length > 0)
        {
            nextId++;
        }
        return nextId;
    }

    static string ToRequirementRelativeSpecPath(string fileName)
        => $"specs/{fileName}";

    static string PromptForDefaultSpecStatus()
    {
        var selected = AnsiConsole.Prompt(
            new SelectionPrompt<string>()
                .Title("[cyan]Default status for newly discovered specs:[/]")
                .AddChoices(new[] { "draft", "planned", "in_progress", "blocked", "done", "complete" }));

        return selected;
    }

    static JsonObject? LoadOptionalJsonObject(string path)
    {
        if (!File.Exists(path))
            return null;

        try
        {
            return JsonNode.Parse(File.ReadAllText(path))?.AsObject();
        }
        catch
        {
            return null;
        }
    }

    static string? GetSpecTitle(string specPath, string requirementId, string? existingTitle)
    {
        var fallbackTitle = string.IsNullOrWhiteSpace(existingTitle) ? null : existingTitle.Trim();
        if (!File.Exists(specPath))
            return fallbackTitle;

        try
        {
            foreach (var line in File.ReadLines(specPath, Encoding.UTF8))
            {
                var match = System.Text.RegularExpressions.Regex.Match(line, "^\\s*#\\s+(.+?)\\s*$");
                if (!match.Success)
                    continue;

                var heading = match.Groups[1].Value.Trim();
                if (string.IsNullOrWhiteSpace(heading))
                    break;

                var prefixPattern = $"^(?:{System.Text.RegularExpressions.Regex.Escape(requirementId)})\\s*[:\\-\\u2013\\u2014]\\s*(.+)$";
                var normalized = System.Text.RegularExpressions.Regex.Match(heading, prefixPattern);
                var title = normalized.Success ? normalized.Groups[1].Value.Trim() : heading;
                return string.IsNullOrWhiteSpace(title) ? fallbackTitle : title;
            }
        }
        catch { }

        return fallbackTitle;
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
            release = await AnsiConsole.Status()
                .Spinner(Spinner.Known.Dots)
                .StartAsync("Checking GitHub releases...", _ => GetLatestGitHubReleaseAsync(DefaultUpdateRepo));
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

        RenderUpdateOverview(plan, installDir, releaseRid, updateAvailable, checkOnly);
        AnsiConsole.MarkupLine($"[grey]Source:[/] https://github.com/{DefaultUpdateRepo}/releases/latest");

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
            var prompt = BuildUpdateActionPrompt(plan, installDir);

            if (!AnsiConsole.Confirm(prompt))
            {
                AnsiConsole.MarkupLine("[grey]Update cancelled.[/]");
                return 0;
            }
        }

        string stageRoot;
        try
        {
            stageRoot = await AnsiConsole.Status()
                .Spinner(Spinner.Known.Dots)
                .StartAsync("Preparing update...", async ctx =>
                {
                    return await DownloadAndStageReleaseAsync(plan, message =>
                    {
                        ctx.Status(message);
                        ctx.Refresh();
                    });
                });
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

        AnsiConsole.WriteLine();
        RenderUpdateSuccess(plan, installDir, addedToPath);
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

        return new UpdateReleasePlan(
            currentVersion,
            targetVersion,
            zipAsset,
            checksumAsset,
            GetAcceptedChecksumFileNames(zipAsset.Name, targetVersion).ToArray(),
            hasInstalledCopy);
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

    internal static IEnumerable<string> GetAcceptedChecksumFileNames(string assetName, string targetVersion)
    {
        yield return assetName;

        const string latestMarker = "latest-";
        var markerIndex = assetName.IndexOf(latestMarker, StringComparison.OrdinalIgnoreCase);
        if (markerIndex >= 0)
        {
            var versionedName = string.Concat(
                assetName.AsSpan(0, markerIndex),
                targetVersion,
                "-",
                assetName.AsSpan(markerIndex + latestMarker.Length));

            if (!string.Equals(versionedName, assetName, StringComparison.OrdinalIgnoreCase))
            {
                yield return versionedName;
            }
        }
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

    static void RenderUpdateOverview(UpdateReleasePlan plan, string installDir, string releaseRid, bool updateAvailable, bool checkOnly)
    {
        AnsiConsole.Clear();
        AnsiConsole.Write(new Rule("[cyan]Felix Update[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var statusMarkup = !plan.HasInstalledCopy
            ? "[yellow]Ready to install[/]"
            : updateAvailable
                ? "[yellow]Update available[/]"
                : "[green]Up to date[/]";

        var actionMarkup = checkOnly
            ? "[grey]Check only[/]"
            : updateAvailable
                ? "[cyan]Will stage installer after confirmation[/]"
                : "[grey]No action needed[/]";

        var summaryTable = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(updateAvailable ? Color.Yellow : Color.Green3)
            .AddColumn(new TableColumn("[yellow]Field[/]").RightAligned())
            .AddColumn(new TableColumn("[yellow]Value[/]"));

        summaryTable.AddRow("[grey]Status[/]", statusMarkup);
        summaryTable.AddRow("[grey]Current[/]", $"[white]{plan.CurrentVersion.EscapeMarkup()}[/]");
        summaryTable.AddRow("[grey]Latest[/]", $"[white]{plan.TargetVersion.EscapeMarkup()}[/]");
        summaryTable.AddRow("[grey]Platform[/]", $"[white]{releaseRid.EscapeMarkup()}[/]");
        summaryTable.AddRow("[grey]Install Dir[/]", $"[grey]{installDir.EscapeMarkup()}[/]");
        summaryTable.AddRow("[grey]Package[/]", $"[grey]{plan.ZipAsset.Name.EscapeMarkup()}[/]");
        summaryTable.AddRow("[grey]Action[/]", actionMarkup);

        AnsiConsole.Write(summaryTable);
        AnsiConsole.WriteLine();

        var nextStepMessage = !plan.HasInstalledCopy
            ? "Felix did not find an installed CLI in the standard install directory. Continuing will install the latest packaged release there and wire it into your user PATH when needed."
            : updateAvailable
                ? "Felix will download the published release zip, verify the checksum, stage the payload, and hand off to the updater helper after this process exits."
                : "The installed CLI already matches the latest published GitHub release for this platform.";

        if (checkOnly)
        {
            nextStepMessage += " This run only checks availability and does not modify the installation.";
        }

        var panel = new Panel($"[grey]{nextStepMessage.EscapeMarkup()}[/]")
        {
            Header = new PanelHeader("Next", Justify.Left),
            Border = BoxBorder.Rounded,
            BorderStyle = new Style(Color.Grey)
        };

        AnsiConsole.Write(panel);
        AnsiConsole.WriteLine();
    }

    static string BuildUpdateActionPrompt(UpdateReleasePlan plan, string installDir)
    {
        return plan.HasInstalledCopy
            ? $"Replace Felix {plan.CurrentVersion} with {plan.TargetVersion} in {installDir}?"
            : $"Install Felix {plan.TargetVersion} to {installDir}?";
    }

    static void RenderUpdateSuccess(UpdateReleasePlan plan, string installDir, bool addedToPath)
    {
        var resultsTable = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Green3)
            .AddColumn(new TableColumn("[yellow]Step[/]"))
            .AddColumn(new TableColumn("[yellow]Result[/]"));

        resultsTable.AddRow("[green]Downloaded package[/]", $"[grey]{plan.ZipAsset.Name.EscapeMarkup()}[/]");
        resultsTable.AddRow("[green]Verified checksum[/]", $"[grey]{plan.ChecksumAsset.Name.EscapeMarkup()}[/]");
        resultsTable.AddRow("[green]Staged payload[/]", $"[grey]{installDir.EscapeMarkup()}[/]");

        if (addedToPath)
        {
            resultsTable.AddRow("[green]Updated PATH[/]", $"[grey]{installDir.EscapeMarkup()}[/]");
        }

        AnsiConsole.Write(resultsTable);
        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine($"[green]Felix {plan.TargetVersion.EscapeMarkup()} staged successfully.[/]");
        AnsiConsole.MarkupLine("[grey]The update helper will replace the installed files after this process exits.[/]");
        AnsiConsole.MarkupLine("[grey]Run 'felix version' again in a few seconds to confirm the new version.[/]");
    }

    static async Task<string> DownloadAndStageReleaseAsync(UpdateReleasePlan plan, Action<string>? onProgress = null)
    {
        var stageRoot = Path.Combine(Path.GetTempPath(), $"felix-update-{Guid.NewGuid():N}");
        Directory.CreateDirectory(stageRoot);

        var zipPath = Path.Combine(stageRoot, plan.ZipAsset.Name);
        var checksumPath = Path.Combine(stageRoot, plan.ChecksumAsset.Name);
        var payloadDir = Path.Combine(stageRoot, "payload");

        using var client = CreateGitHubHttpClient();

        onProgress?.Invoke($"Downloading {plan.ZipAsset.Name}...");
        await DownloadFileAsync(client, plan.ZipAsset.DownloadUrl, zipPath);

        onProgress?.Invoke($"Downloading {plan.ChecksumAsset.Name}...");
        await DownloadFileAsync(client, plan.ChecksumAsset.DownloadUrl, checksumPath);

        onProgress?.Invoke("Verifying checksum...");
        VerifyDownloadedChecksum(checksumPath, zipPath, plan.AcceptedChecksumFileNames);

        onProgress?.Invoke("Extracting release payload...");
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

    internal static void VerifyDownloadedChecksum(string checksumPath, string filePath, IEnumerable<string> expectedFileNames)
    {
        var expectedNames = expectedFileNames
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var checksumEntry = File.ReadAllLines(checksumPath)
            .Select(line => line.Trim())
            .Where(line => !string.IsNullOrWhiteSpace(line))
            .Select(ParseChecksumLine)
            .Where(result => result.HasValue)
            .Select(result => result!.Value)
            .FirstOrDefault(result => expectedNames.Contains(result.FileName, StringComparer.OrdinalIgnoreCase));

        if (string.IsNullOrWhiteSpace(checksumEntry.Hash))
        {
            throw new InvalidOperationException($"Checksum file did not include an entry for any of: {string.Join(", ", expectedNames)}.");
        }

        using var sha = SHA256.Create();
        using var stream = File.OpenRead(filePath);
        var actualHash = Convert.ToHexString(sha.ComputeHash(stream));
        if (!string.Equals(actualHash, checksumEntry.Hash, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"Checksum mismatch for {checksumEntry.FileName}. Expected {checksumEntry.Hash}, got {actualHash}.");
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

case "$PARENT_PID" in
    ''|*[!0-9]*)
        PARENT_PID=0
        ;;
esac

if [ "$PARENT_PID" -gt 0 ] 2>/dev/null; then
    while kill -0 "$PARENT_PID" 2>/dev/null; do
        sleep 1
    done
fi

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
    // Handles bare arrays, wrapped arrays, and legacy wrapped single-object payloads.
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

                    if (root.TryGetProperty(key, out var single) && single.ValueKind == JsonValueKind.Object)
                        return $"[{single.GetRawText()}]";
                }

                // Single-value object fallback
                foreach (var prop in root.EnumerateObject())
                {
                    if (prop.Value.ValueKind == JsonValueKind.Array)
                        return prop.Value.GetRawText();

                    if (prop.Value.ValueKind == JsonValueKind.Object)
                        return $"[{prop.Value.GetRawText()}]";
                }
                return "[]";
            }

            if (raw.StartsWith("["))
                return raw;

            if (raw.StartsWith("{"))
                return $"[{raw}]";

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
            await ExecuteFelixRichCommand(felixPs1, "Run Next Requirement", "run-next");
        }
        else if (command == "Run Agent")
            await RunAgentInteractive(felixPs1);
        else if (command == "Run Loop")
        {
            AnsiConsole.Clear();
            await ExecuteFelixRichCommand(felixPs1, "Continuous Loop", "loop");
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

        await ShowListUI(felixPs1, statusFilter, null, null, null, false);
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

    static async Task UseAgentInteractive(string felixPs1, string subCommand = "use")
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

        var selectedModel = await PromptAgentModel(felixPs1, selected);

        AnsiConsole.Clear();
        if (string.Equals(selectedModel, selected.ModelDisplay, StringComparison.OrdinalIgnoreCase) || string.IsNullOrWhiteSpace(selectedModel))
            await ExecutePowerShell(felixPs1, "agent", subCommand, selected.Key);
        else
            await ExecutePowerShell(felixPs1, "agent", subCommand, selected.Key, "--model", selectedModel);
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
        {
            AnsiConsole.MarkupLine("[grey]Some providers remain uninstalled. Use 'felix agent install-help <name>' for setup guidance if needed.[/]");
        }

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
        {
            await UseAgentSetupInteractive(felixPs1);
        }

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

    static Task<string?> PromptAgentModel(string felixPs1, ConfiguredAgent agent)
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
        await ExecuteFelixRichCommand(felixPs1, "Run Requirement", "run", reqId);
    }

    sealed record ConfiguredAgent(string Key, string Name, string Provider, string ModelDisplay, bool IsCurrent)
    {
        internal static readonly ConfiguredAgent Back = new("__back__", "< Back>", "", "", false);
    }

    sealed record ConfiguredAgentDetails(string Key, string Name, string Provider, string Adapter, string ModelDisplay, bool IsCurrent, string Executable);

    sealed record SpecFixResult(
        int TotalSpecs,
        List<string> Added,
        List<string> Updated,
        List<string> Duplicates,
        List<string> Fixed,
        List<string> Orphaned,
        List<string> Errors);

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
        {
            candidateDirs.AddRange(roots.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
        }

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
            candidates.Add(Path.Combine(dir, "copilot.bat"));
            candidates.Add(Path.Combine(dir, "copilot.cmd"));
            candidates.Add(Path.Combine(dir, "copilot.exe"));
            candidates.Add(Path.Combine(dir, "copilot.ps1"));
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
    {
        return path.Trim().TrimEnd('\\', '/').ToLowerInvariant();
    }

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
        {
            choices.Add(new ConfiguredAgent("__keep__", "Keep current", "", "", false));
        }
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
            AnsiConsole.MarkupLine($"[grey]Project:[/] {validation.ProjectName!.EscapeMarkup()} [grey][{validation.ProjectId?.EscapeMarkup()}][/]");
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

    internal sealed record ApiKeyValidationResult(bool IsValid, string? ErrorMessage, string? ProjectName, string? ProjectId, string? OrganizationId, string? ExpiresAt);

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

    static string? ResolveAgentExecutablePath(string executable)
    {
        if (string.IsNullOrWhiteSpace(executable))
            return null;

        if (File.Exists(executable))
            return Path.GetFullPath(executable);

        var onPath = FindExecutableOnPath(executable);
        if (!string.IsNullOrWhiteSpace(onPath))
            return onPath;

        if (string.Equals(executable, "copilot", StringComparison.OrdinalIgnoreCase))
            return GetCopilotExecutableCandidates().FirstOrDefault(File.Exists);

        return null;
    }

    static async Task<string> RunProcessCaptureAsync(string fileName, string arguments)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            WorkingDirectory = _felixProjectRoot,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = Process.Start(psi);
        if (process == null)
            throw new InvalidOperationException("Failed to start process.");

        var stdout = await process.StandardOutput.ReadToEndAsync();
        var stderr = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        if (process.ExitCode != 0)
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(stderr) ? stdout : stderr);

        return string.IsNullOrWhiteSpace(stdout) ? stderr : stdout;
    }

    sealed record ProcessCaptureAttempt(bool Success, string Output, bool TimedOut);

    static async Task<ProcessCaptureAttempt> TryRunProcessCaptureAsync(string fileName, string arguments, int timeoutMilliseconds)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            WorkingDirectory = _felixProjectRoot,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = Process.Start(psi);
        if (process == null)
            return new ProcessCaptureAttempt(false, "Failed to start process.", false);

        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        using var cts = new CancellationTokenSource(timeoutMilliseconds);

        try
        {
            await process.WaitForExitAsync(cts.Token);
        }
        catch (OperationCanceledException)
        {
            try { process.Kill(true); } catch { }
            return new ProcessCaptureAttempt(false, string.Empty, true);
        }

        var stdout = await stdoutTask;
        var stderr = await stderrTask;
        var output = string.IsNullOrWhiteSpace(stdout) ? stderr : stdout;
        return new ProcessCaptureAttempt(process.ExitCode == 0, output, false);
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
            $"[grey]{"".PadRight(draftWidth, '█')}[/]" +
            $"[green]{"".PadRight(completeWidth, '█')}[/]" +
            $"[blue]{"".PadRight(doneWidth, '█')}[/]" +
            $"[yellow]{"".PadRight(inProgressWidth, '█')}[/]" +
            $"[cyan1]{"".PadRight(plannedWidth, '█')}[/]" +
            $"[red]{"".PadRight(blockedWidth, '█')}[/]");
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

        return $"[white]{commands.Count} command{(commands.Count == 1 ? "" : "s")}[/]";
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
        AnsiConsole.Clear();
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
