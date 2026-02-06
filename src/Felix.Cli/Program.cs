using System.CommandLine;
using System.Diagnostics;
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

        // Add commands
        rootCommand.AddCommand(CreateRunCommand(felixPs1));
        rootCommand.AddCommand(CreateLoopCommand(felixPs1));
        rootCommand.AddCommand(CreateStatusCommand(felixPs1));
        rootCommand.AddCommand(CreateListCommand(felixPs1));
        rootCommand.AddCommand(CreateValidateCommand(felixPs1));
        rootCommand.AddCommand(CreateDepsCommand(felixPs1));
        rootCommand.AddCommand(CreateSpecCommand(felixPs1));
        rootCommand.AddCommand(CreateVersionCommand(felixPs1));

        return await rootCommand.InvokeAsync(args);
    }

    static Command CreateRunCommand(string felixPs1)
    {
        var reqIdArg = new Argument<string>("requirement-id", "Requirement ID (e.g., S-0001)");
        var formatOpt = new Option<string>("--format", () => "rich", "Output format");
        var verboseOpt = new Option<bool>("--verbose", "Enable verbose logging");
        var quietOpt = new Option<bool>("--quiet", "Suppress non-essential output");

        var cmd = new Command("run", "Execute a single requirement")
        {
            reqIdArg,
            formatOpt,
            verboseOpt,
            quietOpt
        };

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

    static Command CreateLoopCommand(string felixPs1)
    {
        var maxIterOpt = new Option<int?>("--max-iterations", "Maximum iterations");
        var formatOpt = new Option<string>("--format", () => "rich", "Output format");

        var cmd = new Command("loop", "Run agent in continuous loop mode")
        {
            maxIterOpt,
            formatOpt
        };

        cmd.SetHandler(async (maxIter, format) =>
        {
            var args = new List<string> { "loop" };
            if (maxIter.HasValue) args.AddRange(new[] { "--max-iterations", maxIter.Value.ToString() });
            if (format != "rich") args.AddRange(new[] { "--format", format });

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, maxIterOpt, formatOpt);

        return cmd;
    }

    static Command CreateStatusCommand(string felixPs1)
    {
        var reqIdArg = new Argument<string?>("requirement-id", "Requirement ID (optional, shows summary if omitted)")
        {
            Arity = ArgumentArity.ZeroOrOne
        };
        var formatOpt = new Option<string>("--format", () => "rich", "Output format");

        var cmd = new Command("status", "Show requirement status")
        {
            reqIdArg,
            formatOpt
        };

        cmd.SetHandler(async (reqId, format) =>
        {
            var args = new List<string> { "status" };
            if (!string.IsNullOrEmpty(reqId)) args.Add(reqId);
            if (format != "rich") args.AddRange(new[] { "--format", format });

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, reqIdArg, formatOpt);

        return cmd;
    }

    static Command CreateListCommand(string felixPs1)
    {
        var statusOpt = new Option<string?>("--status", "Filter by status");
        var priorityOpt = new Option<string?>("--priority", "Filter by priority");
        var labelsOpt = new Option<string?>("--labels", "Filter by labels (comma-separated)");
        var blockedByOpt = new Option<string?>("--blocked-by", "Filter by blocker type");
        var withDepsOpt = new Option<bool>("--with-deps", "Show dependencies inline");
        var formatOpt = new Option<string>("--format", () => "rich", "Output format");

        var cmd = new Command("list", "List all requirements")
        {
            statusOpt,
            priorityOpt,
            labelsOpt,
            blockedByOpt,
            withDepsOpt,
            formatOpt
        };

        cmd.SetHandler(async (status, priority, labels, blockedBy, withDeps, format) =>
        {
            var args = new List<string> { "list" };
            if (status != null) args.AddRange(new[] { "--status", status });
            if (priority != null) args.AddRange(new[] { "--priority", priority });
            if (labels != null) args.AddRange(new[] { "--labels", labels });
            if (blockedBy != null) args.AddRange(new[] { "--blocked-by", blockedBy });
            if (withDeps) args.Add("--with-deps");
            if (format != "rich") args.AddRange(new[] { "--format", format });

            await ExecutePowerShell(felixPs1, args.ToArray());
        }, statusOpt, priorityOpt, labelsOpt, blockedByOpt, withDepsOpt, formatOpt);

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

    static Command CreateVersionCommand(string felixPs1)
    {
        var cmd = new Command("version", "Show version information");

        cmd.SetHandler(async () =>
        {
            await ExecutePowerShell(felixPs1, "version");
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
}
