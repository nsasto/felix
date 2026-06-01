using System.CommandLine;

namespace Felix.Cli;

partial class Program
{
    static Command CreateRunCommand(string felixPs1, Option<string> formatOpt)
    {
        var reqIdArg = new Argument<string>("requirement-id", "Requirement ID (for example PREFIX-0001)");
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

        // v2 A7: felix run replay <run-id>
        cmd.AddCommand(CreateRunReplaySubcommand(felixPs1));

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
        cmd.AddAlias("init");

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
        var subCmdArg = new Argument<string[]>("subcommand", "build, show, inspect")
        {
            Arity = ArgumentArity.ZeroOrMore
        };
        var reqOpt = new Option<string?>("--requirement", "Requirement ID for context inspection");

        var cmd = new Command("context", "Generate or view project context documentation")
        {
            subCmdArg,
            reqOpt
        };
        cmd.AddOption(formatOpt);

        cmd.SetHandler(async (subArgs, format, req) =>
        {
            // v2: context inspect (A5)
            if (subArgs.Length > 0 && string.Equals(subArgs[0], "inspect", StringComparison.OrdinalIgnoreCase))
            {
                var args = new List<string> { "context", "inspect" };
                if (!string.IsNullOrEmpty(req)) args.AddRange(new[] { "--requirement", req });
                if (format != "rich") args.AddRange(new[] { "--format", format });
                await ExecutePowerShell(felixPs1, args.ToArray());
                return;
            }

            if (string.Equals(format, "rich", StringComparison.OrdinalIgnoreCase)
                && subArgs.Length > 0
                && string.Equals(subArgs[0], "show", StringComparison.OrdinalIgnoreCase))
            {
                await ShowContextMarkdownUI();
                return;
            }

            var cmdArgs = new List<string> { "context" };
            cmdArgs.AddRange(subArgs);
            if (format != "rich") cmdArgs.AddRange(new[] { "--format", format });
            await ExecutePowerShell(felixPs1, cmdArgs.ToArray());
        }, subCmdArg, formatOpt, reqOpt);

        return cmd;
    }

    // ── v2: felix migrate (A6) ─────────────────────────────────────────────

    static Command CreateMigrateCommand(string felixPs1)
    {
        var dryRunOpt = new Option<bool>("--dry-run", "Preview transforms without writing (default if --apply omitted)");
        var applyOpt  = new Option<bool>("--apply", "Write changes to disk (required to execute transforms)");
        var onlyOpt   = new Option<string?>("--only", "Run only the specified transform ID");

        var cmd = new Command("migrate", "Transform v1 Felix repository layout to v2")
        {
            dryRunOpt,
            applyOpt,
            onlyOpt
        };

        cmd.SetHandler(async (dryRun, apply, only) =>
        {
            var args = new List<string> { "migrate" };
            if (dryRun) args.Add("--dry-run");
            if (apply)  args.Add("--apply");
            if (!string.IsNullOrEmpty(only)) args.AddRange(new[] { "--only", only });
            await ExecutePowerShell(felixPs1, args.ToArray());
        }, dryRunOpt, applyOpt, onlyOpt);

        return cmd;
    }

    // ── v2: felix doctor (AS4) ────────────────────────────────────────────

    static Command CreateDoctorCommand(string felixPs1)
    {
        var fixOpt     = new Option<bool>("--fix", "Attempt non-destructive repairs");
        var explainOpt = new Option<string?>("--explain", "Report which .felixignore pattern matches a path");
        var jsonOpt    = new Option<bool>("--json", "Machine-readable output");

        var cmd = new Command("doctor", "Diagnose common Felix operational issues")
        {
            fixOpt,
            explainOpt,
            jsonOpt
        };

        cmd.SetHandler(async (fix, explain, json) =>
        {
            var args = new List<string> { "doctor" };
            if (fix) args.Add("--fix");
            if (!string.IsNullOrEmpty(explain)) args.AddRange(new[] { "--explain", explain });
            if (json) args.Add("--json");
            await ExecutePowerShell(felixPs1, args.ToArray());
        }, fixOpt, explainOpt, jsonOpt);

        return cmd;
    }

    // ── v2: felix plugin (AS1) ────────────────────────────────────────────

    static Command CreatePluginCommand(string felixPs1)
    {
        var cmd = new Command("plugin", "Manage Felix plugins");

        // plugin install <source>
        var installSourceArg = new Argument<string>("source", "Plugin source: ./path, https://url, git+https://..., or <name>");
        var installCmd = new Command("install", "Install a plugin") { installSourceArg };
        installCmd.SetHandler(async (source) =>
        {
            await ExecutePowerShell(felixPs1, "plugin", "install", source);
        }, installSourceArg);

        // plugin list [--remote]
        var remoteOpt  = new Option<bool>("--remote", "List plugins from remote index (requires Phase G)");
        var jsonOpt    = new Option<bool>("--json", "Machine-readable output");
        var listCmd    = new Command("list", "List installed plugins") { remoteOpt, jsonOpt };
        listCmd.SetHandler(async (remote, json) =>
        {
            var args = new List<string> { "plugin", "list" };
            if (remote) args.Add("--remote");
            if (json) args.Add("--json");
            await ExecutePowerShell(felixPs1, args.ToArray());
        }, remoteOpt, jsonOpt);

        // plugin remove <id>
        var removeIdArg = new Argument<string>("id", "Plugin ID to remove");
        var removeCmd   = new Command("remove", "Remove an installed plugin") { removeIdArg };
        removeCmd.SetHandler(async (id) =>
        {
            await ExecutePowerShell(felixPs1, "plugin", "remove", id);
        }, removeIdArg);

        // plugin info <id>
        var infoIdArg = new Argument<string>("id", "Plugin ID to inspect");
        var infoCmd   = new Command("info", "Show details for an installed plugin") { infoIdArg };
        infoCmd.SetHandler(async (id) =>
        {
            await ExecutePowerShell(felixPs1, "plugin", "info", id);
        }, infoIdArg);

        cmd.AddCommand(installCmd);
        cmd.AddCommand(listCmd);
        cmd.AddCommand(removeCmd);
        cmd.AddCommand(infoCmd);
        return cmd;
    }

    // ── v2: felix event (AS2) ─────────────────────────────────────────────

    static Command CreateEventCommand(string felixPs1)
    {
        var cmd = new Command("event", "Query the Felix Event Bus (.felix/events.jsonl)");
        cmd.AddAlias("events");

        // event tail [--kind K] [--run-id ID] [--since 1h]
        var kindOpt  = new Option<string?>("--kind", "Filter by event kind");
        var runIdOpt = new Option<string?>("--run-id", "Filter by run ID");
        var sinceOpt = new Option<string?>("--since", "Time window (e.g. 1h, 30m, 2d)");
        var tailCmd  = new Command("tail", "Stream recent events") { kindOpt, runIdOpt, sinceOpt };
        tailCmd.SetHandler(async (kind, runId, since) =>
        {
            var args = new List<string> { "event", "tail" };
            if (!string.IsNullOrEmpty(kind))  args.AddRange(new[] { "--kind", kind });
            if (!string.IsNullOrEmpty(runId)) args.AddRange(new[] { "--run-id", runId });
            if (!string.IsNullOrEmpty(since)) args.AddRange(new[] { "--since", since });
            await ExecutePowerShell(felixPs1, args.ToArray());
        }, kindOpt, runIdOpt, sinceOpt);

        // event query <expression>
        var exprArg  = new Argument<string>("expression", "jq-like filter expression");
        var queryCmd = new Command("query", "Query events with a filter expression") { exprArg };
        queryCmd.SetHandler(async (expr) =>
        {
            await ExecutePowerShell(felixPs1, "event", "query", expr);
        }, exprArg);

        cmd.AddCommand(tailCmd);
        cmd.AddCommand(queryCmd);
        return cmd;
    }

    // ── v2: felix run replay (A7) — extends the existing run command ──────
    // (registered as a subcommand on the run command via CreateRunReplaySubcommand)

    static Command CreateRunReplaySubcommand(string felixPs1)
    {
        var runIdArg = new Argument<string>("run-id", "Run ID to replay (format: S-NNNN-YYYYMMDD-HHMMSS)");
        var iterOpt  = new Option<int?>("--iteration", "Open a specific iteration (default: latest)");

        var cmd = new Command("replay", "Open the prompt artifact from a previous run") { runIdArg, iterOpt };
        cmd.AddAlias("replay");

        cmd.SetHandler(async (runId, iter) =>
        {
            var args = new List<string> { "run", "replay", runId };
            if (iter.HasValue) args.AddRange(new[] { "--iteration", iter.Value.ToString() });
            await ExecutePowerShell(felixPs1, args.ToArray());
        }, runIdArg, iterOpt);

        return cmd;
    }

    // ── v2: felix skill (B4) ──────────────────────────────────────────────

    static Command CreateSkillCommand(string felixPs1)
    {
        var cmd = new Command("skill", "Manage Felix skills (.felix/skills/<id>/)");

        // skill list [--scope repo|user|all] [--json]
        var scopeOpt = new Option<string?>("--scope", "Filter by scope: repo, user, or all (default)");
        var jsonOpt  = new Option<bool>("--json", "Machine-readable output");
        var listCmd  = new Command("list", "List available skills") { scopeOpt, jsonOpt };
        listCmd.SetHandler(async (scope, json) =>
        {
            var args = new List<string> { "skill", "list" };
            if (!string.IsNullOrEmpty(scope)) args.AddRange(new[] { "--scope", scope });
            if (json) args.Add("--json");
            await ExecutePowerShell(felixPs1, args.ToArray());
        }, scopeOpt, jsonOpt);

        // skill show <id>
        var showIdArg = new Argument<string>("id", "Skill ID to show");
        var showCmd   = new Command("show", "Show skill manifest and prompt") { showIdArg };
        showCmd.SetHandler(async (id) =>
        {
            await ExecutePowerShell(felixPs1, "skill", "show", id);
        }, showIdArg);

        // skill enable <id>
        var enableIdArg = new Argument<string>("id", "Skill ID to enable");
        var enableCmd   = new Command("enable", "Enable a disabled skill") { enableIdArg };
        enableCmd.SetHandler(async (id) =>
        {
            await ExecutePowerShell(felixPs1, "skill", "enable", id);
        }, enableIdArg);

        // skill disable <id>
        var disableIdArg = new Argument<string>("id", "Skill ID to disable");
        var disableCmd   = new Command("disable", "Disable a skill") { disableIdArg };
        disableCmd.SetHandler(async (id) =>
        {
            await ExecutePowerShell(felixPs1, "skill", "disable", id);
        }, disableIdArg);

        // skill install <source> — deferred to Phase G
        var installSourceArg = new Argument<string>("source", "Skill source (deferred to Phase G)");
        var installCmd = new Command("install", "Install a skill (deferred to Phase G)") { installSourceArg };
        installCmd.SetHandler(async (source) =>
        {
            await ExecutePowerShell(felixPs1, "skill", "install", source);
        }, installSourceArg);

        cmd.AddCommand(listCmd);
        cmd.AddCommand(showCmd);
        cmd.AddCommand(enableCmd);
        cmd.AddCommand(disableCmd);
        cmd.AddCommand(installCmd);
        return cmd;
    }
}
