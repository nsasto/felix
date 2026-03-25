using System.Diagnostics;
using System.Text.Json;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    static async Task ExecutePowerShell(string felixPs1, params string[] args)
    {
        var psi = CreateFelixProcessStartInfo(felixPs1, args, createNoWindow: false);

        var process = new Process { StartInfo = psi };

        process.OutputDataReceived += (_, e) =>
        {
            if (e.Data != null) Console.WriteLine(e.Data);
        };

        process.ErrorDataReceived += (_, e) =>
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

            await waitForExitTask;

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
                        ? $"Iteration {state.Iteration}/{state.MaxIterations} - {mode}"
                        : mode;
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
                        if (state.LastAgentResponseContent is { } cachedResp)
                        {
                            lock (_renderSync)
                            {
                                RenderFelixDetailLine("Response", "yellow",
                                    $"[yellow](response that triggered violation - {state.LastAgentResponseLength} chars)[/]");
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
        if (process == null) return string.Empty;

        var output = await process.StandardOutput.ReadToEndAsync();
        await process.WaitForExitAsync();
        Environment.ExitCode = process.ExitCode;

        return output;
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
}
