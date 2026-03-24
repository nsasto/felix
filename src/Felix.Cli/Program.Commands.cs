using System.CommandLine;

namespace Felix.Cli;

partial class Program
{
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
}
