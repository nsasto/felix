using System.CommandLine;

namespace Felix.Cli;

partial class Program
{
    static async Task<int> Main(string[] args)
    {
        if (args.Length > 0 && string.Equals(args[0], "copilot-bridge", StringComparison.OrdinalIgnoreCase))
            return await CopilotBridgeCommand.ExecuteAsync(args.Skip(1).ToArray());

        var felixPs1 = ResolveFelixScriptPath();

        if (felixPs1 == null || !File.Exists(felixPs1))
        {
            var installOnlyRoot = new RootCommand("Felix - Autonomous agent executor");
            installOnlyRoot.AddCommand(CreateInstallCommand());
            if (args.Length > 0 && args[0] == "install")
                return await installOnlyRoot.InvokeAsync(args);

            Console.Error.WriteLine("Error: felix.ps1 not found.");
            Console.Error.WriteLine("Run 'felix install' to install Felix, or run from inside a Felix repository.");
            return 1;
        }

        _felixInstallDir = Path.GetDirectoryName(felixPs1)!;
        _felixProjectRoot = Directory.GetCurrentDirectory();
        var rootCommand = CreateRootCommand(felixPs1);

        if (args.Length == 0)
        {
            await RunInteractiveDashboard(felixPs1);
            return Environment.ExitCode;
        }

        if (args.Length > 0 && !args[0].StartsWith("-"))
        {
            var knownVerbs = rootCommand.Subcommands
                .Select(c => c.Name)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            knownVerbs.Add("--help");
            knownVerbs.Add("--version");
            if (!knownVerbs.Contains(args[0]))
            {
                await ExecutePowerShell(felixPs1, args);
                return Environment.ExitCode;
            }
        }

        return await rootCommand.InvokeAsync(args);
    }

    internal static RootCommand CreateRootCommand(string felixPs1)
    {
        var rootCommand = new RootCommand("Felix - Autonomous agent executor");
        rootCommand.AddCommand(CreateInstallCommand());

        var formatOpt = new Option<string>("--format", () => "rich", "Output format");
        rootCommand.AddOption(formatOpt);

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
        return rootCommand;
    }

    static string? ResolveFelixScriptPath()
    {
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

        return felixPs1;
    }
}
