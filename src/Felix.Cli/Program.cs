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
using System.Text.RegularExpressions;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
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
        public bool HasContractViolation { get; set; }
        public string? LastAgentResponseContent { get; set; }
        public int LastAgentResponseLength { get; set; }
        public bool ExitHandlerSeen { get; set; }
        public DateTimeOffset? ExitHandlerSeenAtUtc { get; set; }
        public bool IsVerbose { get; init; }
        public bool IsDebug { get; init; }
        public bool IsSync { get; init; }
    }

    static async Task<int> Main(string[] args)
    {
        if (args.Length > 0 && string.Equals(args[0], "copilot-bridge", StringComparison.OrdinalIgnoreCase))
            return await CopilotBridgeCommand.ExecuteAsync(args.Skip(1).ToArray());

        var rootCommand = new RootCommand("Felix - Autonomous agent executor");

        // 'felix install' extracts PS scripts from the embedded zip � no PS needed yet.
        // Register it unconditionally so it works before any scripts are on disk.
        rootCommand.AddCommand(CreateInstallCommand());

        // -- Resolve felix.ps1 ------------------------------------------------
        // Priority 1: walk up from exe dir (finds local dev repo � dev workflow unchanged)
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

        // -- Set shared env-var context ----------------------------------------
        // FELIX_INSTALL_DIR ? directory that contains felix.ps1 (core/, commands/, plugins/)
        // FELIX_PROJECT_ROOT ? current working directory (the project being worked on)
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
        var debugOpt = new Option<bool>("--debug", "Enable debug mode and log full prompt artifacts per attempt");
        var quietOpt = new Option<bool>("--quiet", "Suppress non-essential output");
        var syncOpt = new Option<bool>("--sync", "Temporarily enable sync (overrides config)");

        var cmd = new Command("run", "Execute a single requirement")
        {
            reqIdArg,
            verboseOpt,
            debugOpt,
            quietOpt,
            syncOpt
        };
        cmd.AddOption(formatOpt);

        cmd.SetHandler(async (reqId, format, verbose, debug, quiet, sync) =>
        {
            var args = new List<string> { "run", reqId };
            if (verbose) args.Add("--verbose");
            if (debug) args.Add("--debug");
            if (quiet) args.Add("--quiet");
            if (sync) args.Add("--sync");

            if (string.Equals(format, "rich", StringComparison.OrdinalIgnoreCase))
                await ExecuteFelixRichCommand(felixPs1, "Run Requirement", args.ToArray());
            else
            {
                args.AddRange(new[] { "--format", format });
                await ExecutePowerShell(felixPs1, args.ToArray());
            }
        }, reqIdArg, formatOpt, verboseOpt, debugOpt, quietOpt, syncOpt);

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
        var verboseOpt = new Option<bool>("--verbose", "Enable verbose logging");
        verboseOpt.AddAlias("-Verbose");
        var debugOpt = new Option<bool>("--debug", "Enable debug mode and log full prompt artifacts per attempt");

        var cmd = new Command("run-next", "Claim and run next available requirement (local or server-assigned)")
        {
            syncOpt,
            verboseOpt,
            debugOpt,
        };
        cmd.AddOption(formatOpt);

        cmd.SetHandler(async (sync, verbose, debug, format) =>
        {
            var args = new List<string> { "run-next" };
            if (sync) args.Add("--sync");
            if (verbose) args.Add("--verbose");
            if (debug) args.Add("--debug");

            if (string.Equals(format, "rich", StringComparison.OrdinalIgnoreCase))
                await ExecuteFelixRichCommand(felixPs1, "Run Next Requirement", args.ToArray());
            else
            {
                args.AddRange(new[] { "--format", format });
                await ExecutePowerShell(felixPs1, args.ToArray());
            }
        }, syncOpt, verboseOpt, debugOpt, formatOpt);

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
        var state = new FelixRichRunState
        {
            CommandLabel = commandLabel,
            IsVerbose = args.Contains("--verbose", StringComparer.OrdinalIgnoreCase),
            IsDebug = args.Contains("--debug", StringComparer.OrdinalIgnoreCase),
            IsSync = args.Contains("--sync", StringComparer.OrdinalIgnoreCase),
        };
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

            while (true)
            {
                var completed = await Task.WhenAny(waitForExitTask, forceExitRequested.Task, Task.Delay(500));
                if (completed == waitForExitTask || completed == forceExitRequested.Task)
                    break;

                if (!state.ExitHandlerSeen || state.ExitHandlerSeenAtUtc is null || process.HasExited)
                    continue;

                var elapsedSinceExitIntent = DateTimeOffset.UtcNow - state.ExitHandlerSeenAtUtc.Value;
                if (elapsedSinceExitIntent <= TimeSpan.FromSeconds(8))
                    continue;

                lock (_renderSync)
                    RenderFelixDetailLine("INFO", "yellow", "Process did not exit after exit-handler signal; forcing termination");

                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch
                {
                }

                break;
            }

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

            // Wait for process to fully exit first
            await waitForExitTask;

            // Forcibly close our reader ends of the pipe. This immediately unblocks any
            // pending ReadLineAsync in stdoutTask/stderrTask — necessary because grandchild
            // processes spawned by droid (Node workers, python, etc.) inherit the write end
            // of the pipe and keep it open after PowerShell exits.
            try { process.StandardOutput.Close(); } catch { }
            try { process.StandardError.Close(); } catch { }
            await Task.WhenAll(stdoutTask, stderrTask);

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
        try
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
        catch (ObjectDisposedException) { }
        catch (IOException) { }
    }

    static async Task ConsumeFelixErrorAsync(StreamReader reader, FelixRichRunState state)
    {
        try
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
        catch (ObjectDisposedException) { }
        catch (IOException) { }
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
            if (trimmed.Contains("[EXIT-HANDLER] About to call exit", StringComparison.OrdinalIgnoreCase))
            {
                state.ExitHandlerSeen = true;
                state.ExitHandlerSeenAtUtc ??= DateTimeOffset.UtcNow;
            }

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
                    var flags = new List<string>();
                    if (state.IsVerbose) flags.Add("verbose");
                    if (state.IsDebug) flags.Add("debug");
                    if (state.IsSync) flags.Add("sync");
                    var flagsLine = flags.Count > 0
                        ? $"[grey]Flags[/] [cyan]{string.Join(", ", flags).EscapeMarkup()}[/]"
                        : "[grey]Flags[/] [grey]none[/]";
                    lock (_renderSync)
                    {
                        AnsiConsole.Write(new Panel(body)
                        {
                            Header = new PanelHeader("[cyan]Run Started[/]"),
                            Border = BoxBorder.Rounded,
                            BorderStyle = Style.Parse("cyan")
                        });
                        AnsiConsole.MarkupLine(flagsLine);
                        AnsiConsole.WriteLine();
                    }
                    break;
                }
            case "iteration_started":
                {
                    state.Iteration = GetJsonInt(data, "iteration");
                    state.MaxIterations = GetJsonInt(data, "max_iterations");
                    state.LatestMode = GetJsonString(data, "mode");
                    var mode = (state.LatestMode ?? "running").ToUpperInvariant().EscapeMarkup();
                    var label = state.Iteration.HasValue && state.MaxIterations.HasValue
                        ? $"Iteration {state.Iteration}/{state.MaxIterations} � {mode}"
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
                    if (message.Contains("Contract violation", StringComparison.OrdinalIgnoreCase))
                    {
                        state.HasContractViolation = true;
                        // Retroactively display the last agent response to help diagnose
                        if (state.LastAgentResponseContent is { } cachedResp)
                        {
                            lock (_renderSync)
                            {
                                RenderFelixDetailLine("Response", "yellow",
                                    $"[yellow](response that triggered violation — {state.LastAgentResponseLength} chars)[/]");
                                foreach (var respLine in cachedResp.Split('\n').Take(40))
                                    AnsiConsole.MarkupLine($"  [grey]{respLine.EscapeMarkup()}[/]");
                            }
                            state.LastAgentResponseContent = null;
                        }
                    }
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
            case "agent_response":
                {
                    var content = GetJsonString(data, "content") ?? string.Empty;
                    var length = GetJsonInt(data, "length") ?? 0;
                    var truncated = GetJsonBool(data, "truncated") == true;

                    // Cache so contract violation handler can display it retroactively
                    state.LastAgentResponseContent = content;
                    state.LastAgentResponseLength = length;

                    var suffix = truncated
                        ? $" [grey](first 3000 of {length} chars - see output.log for full)[/]"
                        : $" [grey]({length} chars)[/]";
                    lock (_renderSync)
                    {
                        RenderFelixDetailLine("Response", "cyan", suffix);

                        if (TryExtractJsonResponse(content, out var responseJson, out var hadEnvelopeText))
                        {
                            if (hadEnvelopeText)
                                RenderFelixDetailLine("Format", "yellow", "Response included non-JSON wrapper text; parsed inner JSON payload");

                            RenderResponseJsonFields(responseJson);
                        }
                        else
                        {
                            foreach (var responseLine in content.Split('\n').Take(40))
                                AnsiConsole.MarkupLine($"  [grey]{responseLine.EscapeMarkup()}[/]");
                        }
                    }
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

    static string? GetJsonString(JsonObject obj, string propertyName)
    {
        var value = obj[propertyName];
        return value switch
        {
            null => null,
            JsonValue jsonValue when jsonValue.TryGetValue<string>(out var stringValue) => stringValue,
            JsonValue jsonValue when jsonValue.TryGetValue<int>(out var intValue) => intValue.ToString(),
            JsonValue jsonValue when jsonValue.TryGetValue<long>(out var longValue) => longValue.ToString(),
            JsonValue jsonValue when jsonValue.TryGetValue<double>(out var doubleValue) => doubleValue.ToString(),
            JsonValue jsonValue when jsonValue.TryGetValue<bool>(out var boolValue) => boolValue ? bool.TrueString : bool.FalseString,
            _ => value.ToJsonString().Trim('"')
        };
    }

    static int? GetJsonInt(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) || value.ValueKind != JsonValueKind.Number)
            return null;

        return value.TryGetInt32(out var number) ? number : null;
    }

    static int? GetJsonInt(JsonObject obj, string propertyName)
    {
        var value = obj[propertyName];
        if (value is JsonValue jsonValue && jsonValue.TryGetValue<int>(out var intValue))
            return intValue;

        return null;
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

    static bool TryExtractJsonResponse(string content, out JsonElement payload, out bool hadEnvelopeText)
    {
        payload = default;
        hadEnvelopeText = false;

        content ??= string.Empty;
        var trimmed = content.Trim();
        if (trimmed.Length == 0)
            return false;

        if (TryParseJsonPayload(trimmed, out payload))
            return true;

        var fenceMatch = Regex.Match(content, "```json\\s*(\\{.*?\\})\\s*```", RegexOptions.IgnoreCase | RegexOptions.Singleline);
        if (fenceMatch.Success)
        {
            hadEnvelopeText = true;
            if (TryParseJsonPayload(fenceMatch.Groups[1].Value, out payload))
                return true;
        }

        var firstBrace = content.IndexOf('{');
        var lastBrace = content.LastIndexOf('}');
        if (firstBrace >= 0 && lastBrace > firstBrace)
        {
            hadEnvelopeText = true;
            var candidate = content.Substring(firstBrace, lastBrace - firstBrace + 1);
            if (TryParseJsonPayload(candidate, out payload))
                return true;
        }

        return false;
    }

    static bool TryParseJsonPayload(string text, out JsonElement payload)
    {
        payload = default;
        try
        {
            using var doc = JsonDocument.Parse(text);
            if (doc.RootElement.ValueKind != JsonValueKind.Object)
                return false;

            payload = doc.RootElement.Clone();
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    static void RenderResponseJsonFields(JsonElement root)
    {
        foreach (var (key, value) in FlattenJsonFields(root, null))
        {
            RenderFelixDetailLine(key, "grey", value.EscapeMarkup());
        }
    }

    static IEnumerable<(string Key, string Value)> FlattenJsonFields(JsonElement element, string? prefix)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var prop in element.EnumerateObject())
            {
                var nextPrefix = string.IsNullOrWhiteSpace(prefix) ? prop.Name : $"{prefix}.{prop.Name}";
                foreach (var pair in FlattenJsonFields(prop.Value, nextPrefix))
                    yield return pair;
            }

            yield break;
        }

        if (element.ValueKind == JsonValueKind.Array)
        {
            var values = element.EnumerateArray().Select(v => v.ValueKind == JsonValueKind.String ? (v.GetString() ?? string.Empty) : v.ToString());
            yield return (prefix ?? "value", string.Join(", ", values));
            yield break;
        }

        var scalar = element.ValueKind switch
        {
            JsonValueKind.String => element.GetString() ?? string.Empty,
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            JsonValueKind.Null => "null",
            _ => element.ToString()
        };

        yield return (prefix ?? "value", scalar);
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
            LaunchUpdateHelper(stageRoot, installDir, releaseRid, plan.TargetVersion);
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Could not launch the updater helper:[/] {ex.Message.EscapeMarkup()}");
            return 1;
        }

        AnsiConsole.WriteLine();
        RenderUpdateSuccess(plan, installDir, addedToPath, stageRoot);
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

    static void RenderUpdateSuccess(UpdateReleasePlan plan, string installDir, bool addedToPath, string stageRoot = "")
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
        AnsiConsole.MarkupLine("[grey]The updater is running in the background. Wait a few seconds, then run 'felix version' to confirm.[/]");
        if (!string.IsNullOrWhiteSpace(stageRoot))
        {
            var logPath = Path.Combine(stageRoot, "update-log.txt");
            AnsiConsole.MarkupLine($"[grey]If the version does not change, check the update log: {logPath.EscapeMarkup()}[/]");
        }
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

    static void LaunchUpdateHelper(string stageRoot, string installDir, string releaseRid, string targetVersion = "")
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
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{helperScriptPath}\" -ParentPid {Environment.ProcessId} -StageRoot \"{stageRoot}\" -InstallDir \"{installDir}\" -TargetVersion \"{targetVersion}\"",
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
                Arguments = $"\"{helperScriptPath}\" {Environment.ProcessId} \"{stageRoot}\" \"{installDir}\" \"{targetVersion}\"",
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
    [string]$InstallDir,
    [string]$TargetVersion = ''
)

$logFile = Join-Path $StageRoot 'update-log.txt'

function Write-Log {
    param([string]$Message)
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    ""$ts  $Message"" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

try {
    Write-Log 'Update helper started'

    try {
        Wait-Process -Id $ParentPid -ErrorAction SilentlyContinue
    } catch { }

Start - Sleep - Milliseconds 750

    $payloadDir = Join - Path $StageRoot 'payload'
    if (-not (Test-Path -LiteralPath $payloadDir)) {
        throw ""Update payload directory not found: $payloadDir""
    }

    New - Item - ItemType Directory - Path $InstallDir - Force | Out - Null

    Get - ChildItem - LiteralPath $payloadDir - Force | ForEach - Object {
        $destination = Join - Path $InstallDir $_.Name
        Copy - Item - LiteralPath $_.FullName - Destination $destination - Force - ErrorAction Stop
        Write - Log ""Copied: $($_.Name)""
    }

if (-not[string]::IsNullOrWhiteSpace($TargetVersion))
{
        $versionFile = Join - Path $InstallDir 'version.txt'
        Set - Content - LiteralPath $versionFile - Value $TargetVersion - Encoding UTF8 - NoNewline
        Write - Log ""Wrote version.txt: $TargetVersion""
    }

Write - Log 'Update complete'
    Remove - Item - LiteralPath $StageRoot - Recurse - Force - ErrorAction SilentlyContinue
}
catch {
    Write - Log ""Error: $_""
}
";

    internal static string BuildUnixUpdateHelperScript() => """
#!/bin/sh
PARENT_PID="$1"
STAGE_ROOT="$2"
INSTALL_DIR="$3"
TARGET_VERSION="$4"

LOG_FILE="$STAGE_ROOT/update-log.txt"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" >> "$LOG_FILE" 2>/dev/null
}

log 'Update helper started'

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
    log "Error: payload directory not found: $PAYLOAD_DIR"
    exit 1
fi

mkdir -p "$INSTALL_DIR"
if ! cp -R "$PAYLOAD_DIR"/. "$INSTALL_DIR"/; then
    log 'Error: cp failed'
    exit 1
fi
log 'Files copied'

if [ -f "$INSTALL_DIR/felix" ]; then
    chmod +x "$INSTALL_DIR/felix"
fi

if [ -n "$TARGET_VERSION" ]; then
    printf '%s' "$TARGET_VERSION" > "$INSTALL_DIR/version.txt"
    log "Wrote version.txt: $TARGET_VERSION"
fi

log 'Update complete'
rm -rf "$STAGE_ROOT"
""";

    // -- felix install ---------------------------------------------------------

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
            // -- Platform-aware install directory ----------------------------
            var installDir = GetInstallDirectory();

            AnsiConsole.MarkupLine("[cyan]Felix CLI Installer[/]");
            AnsiConsole.MarkupLine("[grey]------------------------------[/]");

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

            // -- PATH setup --------------------------------------------------
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

    // Read requirements.json directly � avoids spawning a PowerShell process just for data.
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
        AnsiConsole.MarkupLine("[cyan1]�������+�������+��+     ��+��+  ��+[/]");
        AnsiConsole.MarkupLine("[cyan1]��+----+��+----+���     ���+��+��++[/]");
        AnsiConsole.MarkupLine("[cyan1]�����+  �����+  ���     ��� +���++[/] ");
        AnsiConsole.MarkupLine("[cyan1]��+--+  ��+--+  ���     ��� ��+��+[/] ");
        AnsiConsole.MarkupLine("[cyan1]���     �������+�������+�����++ ��+[/]");
        AnsiConsole.MarkupLine("[cyan1]+-+     +------++------++-++-+  +-+[/]");
        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine("[grey dim]Autonomous Agent Executor[/]");
        AnsiConsole.WriteLine();

        // Get status data � read file directly, no process spawn
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

        AnsiConsole.MarkupLine($"[green]{"".PadRight(completeWidth, '�')}[/][blue]{"".PadRight(doneWidth, '�')}[/][yellow]{"".PadRight(inProgressWidth, '�')}[/][cyan1]{"".PadRight(plannedWidth, '�')}[/][red]{"".PadRight(Math.Max(0, blockedWidth), '�')}[/]");
        AnsiConsole.WriteLine();

        if (complete > 0) AnsiConsole.MarkupLine($"[green]�[/] Complete {complete}%  ", false);
        if (done > 0) AnsiConsole.MarkupLine($"[blue]�[/] Done {done}%  ", false);
        if (inProgress > 0) AnsiConsole.MarkupLine($"[yellow]�[/] In Progress {inProgress}%  ", false);
        if (planned > 0) AnsiConsole.MarkupLine($"[cyan1]�[/] Planned {planned}%  ", false);
        if (blocked > 0) AnsiConsole.MarkupLine($"[red]�[/] Blocked {blocked}%", false);

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
            Header = new PanelHeader("[yellow]? Help[/]"),
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

    static string? ExtractApiErrorMessage(string? responseBody)
    {
        if (string.IsNullOrWhiteSpace(responseBody))
            return null;

        try
        {
            using var document = JsonDocument.Parse(responseBody);
            if (document.RootElement.ValueKind == JsonValueKind.Object)
            {
                if (document.RootElement.TryGetProperty("detail", out var detail) && detail.ValueKind == JsonValueKind.String)
                    return detail.GetString();
                if (document.RootElement.TryGetProperty("error", out var error) && error.ValueKind == JsonValueKind.String)
                    return error.GetString();
                if (document.RootElement.TryGetProperty("message", out var message) && message.ValueKind == JsonValueKind.String)
                    return message.GetString();
            }
        }
        catch
        {
        }

        return responseBody.Trim();
    }

    static string MaskApiKey(string? apiKey)
    {
        if (string.IsNullOrWhiteSpace(apiKey))
            return "(none - will attempt without key)";

        return apiKey.Length <= 12
            ? apiKey
            : apiKey[..12] + "...";
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
            $"[grey]{"".PadRight(draftWidth, '�')}[/]" +
            $"[green]{"".PadRight(completeWidth, '�')}[/]" +
            $"[blue]{"".PadRight(doneWidth, '�')}[/]" +
            $"[yellow]{"".PadRight(inProgressWidth, '�')}[/]" +
            $"[cyan1]{"".PadRight(plannedWidth, '�')}[/]" +
            $"[red]{"".PadRight(blockedWidth, '�')}[/]");
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
