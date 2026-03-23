using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Felix.Cli;

internal static class CopilotBridgeCommand
{
    private static readonly Regex ModelUnavailableRegex = new(
        "Model\\s+\"[^\"]+\"\\s+from\\s+--model\\s+flag\\s+is\\s+not\\s+available",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = false
    };

    internal sealed class CopilotBridgeRequest
    {
        public string Executable { get; set; } = "copilot";
        public string Prompt { get; set; } = string.Empty;
        public string WorkingDirectory { get; set; } = ".";
        public string? Model { get; set; }
        public bool AllowAll { get; set; } = true;
        public bool NoAskUser { get; set; } = true;
        public int? MaxAutopilotContinues { get; set; }
        public string? CustomAgent { get; set; }
        public bool MirrorOutputToStdErr { get; set; }
        public Dictionary<string, string?> Environment { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    }

    internal sealed class CopilotBridgeResponse
    {
        public bool UsedBridge { get; set; }
        public bool Succeeded { get; set; }
        public int ExitCode { get; set; }
        public string Output { get; set; } = string.Empty;
        public string StdOut { get; set; } = string.Empty;
        public string StdErr { get; set; } = string.Empty;
        public string? Error { get; set; }
        public string? Signal { get; set; }
        public bool RetriedWithoutModel { get; set; }
        public string ResolvedExecutable { get; set; } = string.Empty;
        public string WorkingDirectory { get; set; } = string.Empty;
        public List<string> Arguments { get; set; } = new();
    }

    private sealed record LaunchSpec(string FileName, IReadOnlyList<string> Arguments);

    private sealed record ProcessResult(string StdOut, string StdErr, int ExitCode)
    {
        public string CombinedOutput
        {
            get
            {
                if (string.IsNullOrWhiteSpace(StdErr))
                    return StdOut;
                if (string.IsNullOrWhiteSpace(StdOut))
                    return StdErr;
                return StdOut + Environment.NewLine + StdErr;
            }
        }
    }

    internal static async Task<int> ExecuteAsync(string[] args)
    {
        var requestFile = ParseRequestFile(args);
        if (string.IsNullOrWhiteSpace(requestFile))
        {
            Console.Error.WriteLine("Missing required option: --request-file <path>");
            return 2;
        }

        if (!File.Exists(requestFile))
        {
            Console.Error.WriteLine($"Request file not found: {requestFile}");
            return 2;
        }

        CopilotBridgeRequest? request;
        try
        {
            request = JsonSerializer.Deserialize<CopilotBridgeRequest>(await File.ReadAllTextAsync(requestFile), JsonOptions);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to parse bridge request: {ex.Message}");
            return 2;
        }

        if (request is null)
        {
            Console.Error.WriteLine("Bridge request payload was empty.");
            return 2;
        }

        var response = await RunAsync(request);
        await Console.Out.WriteAsync(JsonSerializer.Serialize(response, JsonOptions));
        return 0;
    }

    internal static async Task<CopilotBridgeResponse> RunAsync(CopilotBridgeRequest request)
    {
        var resolvedExecutable = ResolveCopilotExecutable(request.Executable);
        if (resolvedExecutable is null)
        {
            var message = $"Agent executable not found: '{request.Executable}'.";
            return new CopilotBridgeResponse
            {
                UsedBridge = true,
                Succeeded = false,
                ExitCode = 127,
                Output = message,
                StdErr = message,
                Error = "AgentExecutableNotFound",
                ResolvedExecutable = string.Empty,
                WorkingDirectory = string.IsNullOrWhiteSpace(request.WorkingDirectory) ? Directory.GetCurrentDirectory() : request.WorkingDirectory,
                Arguments = BuildArguments(request, includeModel: true)
            };
        }

        var workingDirectory = string.IsNullOrWhiteSpace(request.WorkingDirectory)
            ? Directory.GetCurrentDirectory()
            : request.WorkingDirectory;

        var attemptedArgs = BuildArguments(request, includeModel: true);
        var firstRun = await RunProcessAsync(resolvedExecutable, workingDirectory, attemptedArgs, request.Environment, request.MirrorOutputToStdErr);

        var finalRun = firstRun;
        var retriedWithoutModel = false;
        var finalArgs = attemptedArgs;

        if (!string.IsNullOrWhiteSpace(request.Model) && ModelUnavailableRegex.IsMatch(firstRun.CombinedOutput))
        {
            retriedWithoutModel = true;
            finalArgs = BuildArguments(request, includeModel: false);
            finalRun = await RunProcessAsync(resolvedExecutable, workingDirectory, finalArgs, request.Environment, request.MirrorOutputToStdErr);
        }

        var finalOutput = finalRun.CombinedOutput;
        return new CopilotBridgeResponse
        {
            UsedBridge = true,
            Succeeded = finalRun.ExitCode == 0,
            ExitCode = finalRun.ExitCode,
            Output = finalOutput,
            StdOut = finalRun.StdOut,
            StdErr = finalRun.StdErr,
            Error = ResolveKnownError(finalOutput),
            Signal = ExtractCompletionSignal(finalOutput),
            RetriedWithoutModel = retriedWithoutModel,
            ResolvedExecutable = resolvedExecutable,
            WorkingDirectory = workingDirectory,
            Arguments = finalArgs
        };
    }

    internal static List<string> BuildArguments(CopilotBridgeRequest request, bool includeModel)
    {
        var args = new List<string> { "--autopilot", "-s", "--no-color" };

        if (request.AllowAll)
            args.Add("--yolo");

        if (request.NoAskUser)
            args.Add("--no-ask-user");

        if (request.MaxAutopilotContinues.HasValue)
        {
            args.Add("--max-autopilot-continues");
            args.Add(request.MaxAutopilotContinues.Value.ToString());
        }

        if (!string.IsNullOrWhiteSpace(request.CustomAgent))
        {
            args.Add("--agent");
            args.Add(request.CustomAgent);
        }

        if (includeModel && !string.IsNullOrWhiteSpace(request.Model))
        {
            args.Add("--model");
            args.Add(request.Model);
        }

        args.Add("-p");
        args.Add(request.Prompt ?? string.Empty);
        return args;
    }

    internal static string? ExtractCompletionSignal(string output)
    {
        if (string.IsNullOrWhiteSpace(output))
            return null;

        var signals = output
            .Split(["\r\n", "\n", "\r"], StringSplitOptions.None)
            .Select(line => line.Trim())
            .Select(line => line switch
            {
                "<promise>PLAN_COMPLETE</promise>" => "PLAN_COMPLETE",
                "<promise>PLANNING_COMPLETE</promise>" => "PLANNING_COMPLETE",
                "<promise>TASK_COMPLETE</promise>" => "TASK_COMPLETE",
                "<promise>ALL_COMPLETE</promise>" => "ALL_COMPLETE",
                _ => null
            })
            .Where(signal => signal is not null)
            .ToList();

        if (signals.Count == 0)
            return null;

        if (signals.Contains("ALL_COMPLETE", StringComparer.Ordinal))
            return "ALL_COMPLETE";
        if (signals.Contains("TASK_COMPLETE", StringComparer.Ordinal))
            return "TASK_COMPLETE";
        if (signals.Contains("PLAN_COMPLETE", StringComparer.Ordinal) || signals.Contains("PLANNING_COMPLETE", StringComparer.Ordinal))
            return "PLAN_COMPLETE";
        return null;
    }

    internal static bool IsModelUnavailable(string output) => ModelUnavailableRegex.IsMatch(output ?? string.Empty);

    private static string? ParseRequestFile(string[] args)
    {
        for (var index = 0; index < args.Length; index++)
        {
            if (!string.Equals(args[index], "--request-file", StringComparison.OrdinalIgnoreCase))
                continue;

            if (index + 1 >= args.Length)
                return null;

            return args[index + 1];
        }

        return null;
    }

    private static string? ResolveCopilotExecutable(string executable)
    {
        if (string.IsNullOrWhiteSpace(executable))
            return null;

        if (File.Exists(executable))
            return NormalizeResolvedCopilotPath(Path.GetFullPath(executable));

        var fromPath = FindExecutableOnPath(executable);
        if (fromPath is not null)
            return NormalizeResolvedCopilotPath(fromPath);

        if (string.Equals(executable, "copilot", StringComparison.OrdinalIgnoreCase))
            return Program.GetCopilotExecutableCandidates().FirstOrDefault(File.Exists) is { } candidate
                ? NormalizeResolvedCopilotPath(candidate)
                : null;

        return null;
    }

    private static string NormalizeResolvedCopilotPath(string resolvedPath)
    {
        // Return the resolved path as-is. Invoking copilot.ps1 directly via
        // 'pwsh -File copilot.ps1' (handled by CreateLaunchSpec) correctly
        // populates $MyInvocation.MyCommand.Path inside the script.
        // Preferring .bat/.cmd siblings is deliberately avoided because npm shims
        // call copilot.ps1 via 'powershell -Command' which leaves
        // $MyInvocation.MyCommand.Path empty, breaking copilot's own shim.
        return resolvedPath;
    }

    private static string? FindExecutableOnPath(string executableName)
    {
        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
            return null;

        foreach (var root in pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            foreach (var candidate in GetExecutableCandidates(executableName))
            {
                var fullPath = Path.Combine(root, candidate);
                if (File.Exists(fullPath))
                    return fullPath;
            }
        }

        return null;
    }

    private static IEnumerable<string> GetExecutableCandidates(string executableName)
    {
        if (!OperatingSystem.IsWindows())
            return new[] { executableName };

        if (!string.IsNullOrWhiteSpace(Path.GetExtension(executableName)))
            return new[] { executableName };

        return new[] { executableName + ".exe", executableName + ".ps1", executableName + ".cmd", executableName + ".bat", executableName };
    }

    private static LaunchSpec CreateLaunchSpec(string resolvedExecutable, IReadOnlyList<string> arguments)
    {
        var extension = Path.GetExtension(resolvedExecutable);
        if (OperatingSystem.IsWindows() && (extension.Equals(".cmd", StringComparison.OrdinalIgnoreCase) || extension.Equals(".bat", StringComparison.OrdinalIgnoreCase)))
        {
            return new LaunchSpec("cmd.exe", new[] { "/d", "/c", resolvedExecutable }.Concat(arguments).ToList());
        }

        if (extension.Equals(".ps1", StringComparison.OrdinalIgnoreCase))
        {
            return new LaunchSpec(FindPowerShellHost(), new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", resolvedExecutable }.Concat(arguments).ToList());
        }

        return new LaunchSpec(resolvedExecutable, arguments.ToList());
    }

    private static async Task<ProcessResult> RunProcessAsync(string resolvedExecutable, string workingDirectory, IReadOnlyList<string> arguments, IReadOnlyDictionary<string, string?> environment, bool mirrorOutputToStdErr)
    {
        var launchSpec = CreateLaunchSpec(resolvedExecutable, arguments);
        var startInfo = new ProcessStartInfo
        {
            FileName = launchSpec.FileName,
            WorkingDirectory = workingDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        foreach (var argument in launchSpec.Arguments)
            startInfo.ArgumentList.Add(argument);

        foreach (var entry in environment)
            startInfo.Environment[entry.Key] = entry.Value ?? string.Empty;

        // If calling a .ps1 wrapper directly, prepend its directory to PATH so that
        // Get-Command inside the script can find itself (needed by self-referential
        // bootstrapper scripts like the GitHub Copilot CLI shim).
        var ext = Path.GetExtension(resolvedExecutable);
        if (OperatingSystem.IsWindows() && ext.Equals(".ps1", StringComparison.OrdinalIgnoreCase))
        {
            var scriptDir = Path.GetDirectoryName(resolvedExecutable);
            if (!string.IsNullOrEmpty(scriptDir))
            {
                var currentPath = startInfo.Environment.TryGetValue("PATH", out var p) ? p ?? string.Empty : Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
                if (!currentPath.Split(';').Any(d => string.Equals(d.Trim(), scriptDir, StringComparison.OrdinalIgnoreCase)))
                    startInfo.Environment["PATH"] = scriptDir + ";" + currentPath;
            }
        }

        using var process = new Process { StartInfo = startInfo };
        process.Start();

        var stdoutTask = PumpReaderAsync(process.StandardOutput, mirrorOutputToStdErr, mirrorErrors: false);
        var stderrTask = PumpReaderAsync(process.StandardError, mirrorOutputToStdErr, mirrorErrors: true);

        await Task.WhenAll(stdoutTask, stderrTask, process.WaitForExitAsync());

        return new ProcessResult(await stdoutTask, await stderrTask, process.ExitCode);
    }

    private static async Task<string> PumpReaderAsync(StreamReader reader, bool mirrorToStdErr, bool mirrorErrors)
    {
        var builder = new StringBuilder();
        var firstLine = true;

        while (true)
        {
            var line = await reader.ReadLineAsync();
            if (line is null)
                break;

            if (!firstLine)
                builder.AppendLine();

            builder.Append(line);
            firstLine = false;

            if (mirrorToStdErr)
            {
                if (mirrorErrors)
                    await Console.Error.WriteLineAsync(line);
                else
                    await Console.Error.WriteLineAsync(line);
            }
        }

        return builder.ToString();
    }

    private static string? ResolveKnownError(string output)
    {
        var match = ModelUnavailableRegex.Match(output ?? string.Empty);
        return match.Success ? match.Value.Trim() : null;
    }

    private static string FindPowerShellHost()
    {
        if (OperatingSystem.IsWindows())
        {
            var pwsh7 = @"C:\Program Files\PowerShell\7\pwsh.exe";
            if (File.Exists(pwsh7))
                return pwsh7;
        }

        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (!string.IsNullOrWhiteSpace(pathValue))
        {
            foreach (var root in pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                var pwshCandidate = Path.Combine(root, OperatingSystem.IsWindows() ? "pwsh.exe" : "pwsh");
                if (File.Exists(pwshCandidate))
                    return pwshCandidate;
            }
        }

        return OperatingSystem.IsWindows() ? "powershell.exe" : "pwsh";
    }
}