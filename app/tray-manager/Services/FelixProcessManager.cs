using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using FelixTrayManager.Models;

namespace FelixTrayManager.Services
{
    /// <summary>
    /// Manages the Felix agent PowerShell process lifecycle
    /// </summary>
    public class FelixProcessManager : IDisposable
    {
        private Process? _felixProcess;
        private readonly object _processLock = new object();
        private CancellationTokenSource? _monitorCts;
        private Task? _monitorTask;
        private bool _disposed;

        /// <summary>
        /// Current state of the Felix agent process
        /// </summary>
        public enum ProcessState
        {
            Stopped,
            Starting,
            Running,
            Error
        }

        private ProcessState _currentState = ProcessState.Stopped;
        private string? _lastErrorMessage;

        /// <summary>
        /// Gets the current state of the Felix process
        /// </summary>
        public ProcessState CurrentState
        {
            get
            {
                lock (_processLock)
                {
                    return _currentState;
                }
            }
            private set
            {
                lock (_processLock)
                {
                    if (_currentState != value)
                    {
                        _currentState = value;
                        StateChanged?.Invoke(this, new ProcessStateChangedEventArgs(value, _lastErrorMessage));
                    }
                }
            }
        }

        /// <summary>
        /// Gets the last error message if CurrentState is Error
        /// </summary>
        public string? LastErrorMessage
        {
            get
            {
                lock (_processLock)
                {
                    return _lastErrorMessage;
                }
            }
        }

        /// <summary>
        /// Gets whether the Felix agent is currently running
        /// </summary>
        public bool IsRunning
        {
            get
            {
                lock (_processLock)
                {
                    return _felixProcess != null && !_felixProcess.HasExited;
                }
            }
        }

        /// <summary>
        /// Event raised when the process state changes
        /// </summary>
        public event EventHandler<ProcessStateChangedEventArgs>? StateChanged;

        /// <summary>
        /// Event raised when process output is received (for logging)
        /// </summary>
        public event EventHandler<ProcessOutputEventArgs>? OutputReceived;

        /// <summary>
        /// Starts the Felix agent process
        /// </summary>
        /// <param name="settings">Application settings containing project path and max iterations</param>
        /// <returns>True if started successfully, false otherwise</returns>
        public async Task<bool> StartAsync(AppSettings settings)
        {
            // Validate settings
            if (!settings.IsValid())
            {
                SetErrorState("Invalid configuration. Please configure at least one valid agent in Settings.");
                return false;
            }

            // Get the first enabled agent or use legacy mode
            string? agentScriptPath = null;
            string? projectPath = null;

            if (settings.Agents != null && settings.Agents.Count > 0)
            {
                // New agent-based configuration
                var agent = settings.Agents.FirstOrDefault(a => a.Enabled && a.IsValid());
                if (agent == null)
                {
                    SetErrorState("No enabled agents configured. Please enable at least one agent in Settings.");
                    return false;
                }

                agentScriptPath = agent.AgentPath;
                projectPath = agent.ProjectPath;
            }
            else if (!string.IsNullOrWhiteSpace(settings.ProjectPath))
            {
                // Legacy mode - use ProjectPath
                projectPath = settings.ProjectPath;
                agentScriptPath = Path.Combine(settings.ProjectPath, "felix-agent.ps1");
            }
            else
            {
                SetErrorState("No agents configured. Please add an agent in Settings.");
                return false;
            }

            lock (_processLock)
            {
                // Prevent duplicate instances
                if (IsRunning)
                {
                    SetErrorState("Felix agent is already running.");
                    return false;
                }

                CurrentState = ProcessState.Starting;
            }

            try
            {
                // Find PowerShell executable
                var powershellPath = FindPowerShellExecutable();
                if (string.IsNullOrEmpty(powershellPath))
                {
                    SetErrorState("PowerShell not found in PATH. Please install PowerShell.");
                    return false;
                }

                // Validate agent script exists
                if (!File.Exists(agentScriptPath))
                {
                    SetErrorState($"felix-agent.ps1 not found at: {agentScriptPath}");
                    return false;
                }

                // Prepare process start info
                var startInfo = new ProcessStartInfo
                {
                    FileName = powershellPath,
                    Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{agentScriptPath}\" \"{projectPath}\"",
                    WorkingDirectory = projectPath,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden
                };

                // Add max iterations if specified
                if (settings.MaxIterations > 0)
                {
                    startInfo.Arguments += $" -MaxIterations {settings.MaxIterations}";
                }

                // Create and start the process
                var process = new Process { StartInfo = startInfo };

                // Attach output handlers
                process.OutputDataReceived += (sender, e) =>
                {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        OutputReceived?.Invoke(this, new ProcessOutputEventArgs(e.Data, false));
                    }
                };

                process.ErrorDataReceived += (sender, e) =>
                {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        OutputReceived?.Invoke(this, new ProcessOutputEventArgs(e.Data, true));
                    }
                };

                // Attach exit handler
                process.EnableRaisingEvents = true;
                process.Exited += OnProcessExited;

                // Start the process
                if (!process.Start())
                {
                    SetErrorState("Failed to start PowerShell process.");
                    process.Dispose();
                    return false;
                }

                // Begin reading output asynchronously
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();

                lock (_processLock)
                {
                    _felixProcess = process;
                    CurrentState = ProcessState.Running;
                    _lastErrorMessage = null;
                }

                // Start health monitoring
                StartHealthMonitoring();

                // Log successful start
                OutputReceived?.Invoke(this, new ProcessOutputEventArgs(
                    $"Felix agent started successfully (PID: {process.Id})", false));

                return true;
            }
            catch (Exception ex)
            {
                SetErrorState($"Failed to start Felix agent: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Stops the Felix agent process gracefully
        /// </summary>
        /// <param name="forceKill">If true, forcefully terminates the process. If false, attempts graceful shutdown.</param>
        /// <returns>True if stopped successfully, false otherwise</returns>
        public async Task<bool> StopAsync(bool forceKill = false)
        {
            Process? processToStop;

            lock (_processLock)
            {
                if (_felixProcess == null || _felixProcess.HasExited)
                {
                    CurrentState = ProcessState.Stopped;
                    return true;
                }

                processToStop = _felixProcess;
            }

            try
            {
                // Stop health monitoring
                StopHealthMonitoring();

                if (forceKill)
                {
                    // Force kill the process
                    OutputReceived?.Invoke(this, new ProcessOutputEventArgs(
                        "Force stopping Felix agent...", false));
                    
                    processToStop.Kill(entireProcessTree: true);
                    
                    // Wait up to 5 seconds for process to exit
                    await Task.Run(() => processToStop.WaitForExit(5000));
                }
                else
                {
                    // Graceful shutdown - close main window first, then wait
                    OutputReceived?.Invoke(this, new ProcessOutputEventArgs(
                        "Stopping Felix agent gracefully...", false));

                    // Try to close gracefully
                    processToStop.CloseMainWindow();

                    // Wait up to 10 seconds for graceful shutdown
                    var exited = await Task.Run(() => processToStop.WaitForExit(10000));

                    // If still running after graceful attempt, force kill
                    if (!exited && !processToStop.HasExited)
                    {
                        OutputReceived?.Invoke(this, new ProcessOutputEventArgs(
                            "Graceful shutdown timed out. Force stopping...", false));
                        processToStop.Kill(entireProcessTree: true);
                        await Task.Run(() => processToStop.WaitForExit(5000));
                    }
                }

                lock (_processLock)
                {
                    _felixProcess?.Dispose();
                    _felixProcess = null;
                    CurrentState = ProcessState.Stopped;
                    _lastErrorMessage = null;
                }

                OutputReceived?.Invoke(this, new ProcessOutputEventArgs(
                    "Felix agent stopped successfully", false));

                return true;
            }
            catch (Exception ex)
            {
                SetErrorState($"Failed to stop Felix agent: {ex.Message}");
                return false;
            }
        }

        /// <summary>
        /// Finds the PowerShell executable in the system PATH
        /// </summary>
        private string? FindPowerShellExecutable()
        {
            // Try pwsh (PowerShell Core) first, then powershell (Windows PowerShell)
            var powershellCommands = new[] { "pwsh.exe", "powershell.exe" };

            foreach (var cmd in powershellCommands)
            {
                var path = FindExecutableInPath(cmd);
                if (!string.IsNullOrEmpty(path))
                {
                    return path;
                }
            }

            // Try well-known locations on Windows
            var wellKnownPaths = new[]
            {
                @"C:\Program Files\PowerShell\7\pwsh.exe",
                @"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
            };

            foreach (var path in wellKnownPaths)
            {
                if (File.Exists(path))
                {
                    return path;
                }
            }

            return null;
        }

        /// <summary>
        /// Finds an executable in the system PATH
        /// </summary>
        private string? FindExecutableInPath(string executableName)
        {
            var pathEnv = Environment.GetEnvironmentVariable("PATH");
            if (string.IsNullOrEmpty(pathEnv))
            {
                return null;
            }

            var paths = pathEnv.Split(Path.PathSeparator);

            foreach (var path in paths)
            {
                try
                {
                    var fullPath = Path.Combine(path.Trim(), executableName);
                    if (File.Exists(fullPath))
                    {
                        return fullPath;
                    }
                }
                catch
                {
                    // Ignore invalid paths
                    continue;
                }
            }

            return null;
        }

        /// <summary>
        /// Handles process exit events
        /// </summary>
        private void OnProcessExited(object? sender, EventArgs e)
        {
            var process = sender as Process;
            var exitCode = process?.ExitCode ?? -1;

            lock (_processLock)
            {
                if (_felixProcess == process)
                {
                    // Check if this was an unexpected termination
                    if (CurrentState == ProcessState.Running)
                    {
                        SetErrorState($"Felix agent stopped unexpectedly (exit code: {exitCode})");
                    }
                    else
                    {
                        CurrentState = ProcessState.Stopped;
                    }

                    _felixProcess?.Dispose();
                    _felixProcess = null;
                }
            }

            OutputReceived?.Invoke(this, new ProcessOutputEventArgs(
                $"Felix agent process exited with code: {exitCode}", exitCode != 0));
        }

        /// <summary>
        /// Starts background health monitoring of the process
        /// </summary>
        private void StartHealthMonitoring()
        {
            // Stop any existing monitoring
            StopHealthMonitoring();

            _monitorCts = new CancellationTokenSource();
            var token = _monitorCts.Token;

            _monitorTask = Task.Run(async () =>
            {
                while (!token.IsCancellationRequested)
                {
                    try
                    {
                        await Task.Delay(2000, token); // Check every 2 seconds

                        lock (_processLock)
                        {
                            // Verify process is still alive
                            if (_felixProcess != null && _felixProcess.HasExited)
                            {
                                // Process died unexpectedly
                                if (CurrentState == ProcessState.Running)
                                {
                                    SetErrorState("Felix agent process terminated unexpectedly");
                                    _felixProcess.Dispose();
                                    _felixProcess = null;
                                }
                            }
                        }
                    }
                    catch (OperationCanceledException)
                    {
                        // Expected when stopping
                        break;
                    }
                    catch (Exception ex)
                    {
                        Debug.WriteLine($"Health monitoring error: {ex.Message}");
                    }
                }
            }, token);
        }

        /// <summary>
        /// Stops background health monitoring
        /// </summary>
        private void StopHealthMonitoring()
        {
            _monitorCts?.Cancel();
            _monitorTask?.Wait(TimeSpan.FromSeconds(3));
            _monitorCts?.Dispose();
            _monitorCts = null;
            _monitorTask = null;
        }

        /// <summary>
        /// Sets the error state with a message
        /// </summary>
        private void SetErrorState(string errorMessage)
        {
            lock (_processLock)
            {
                _lastErrorMessage = errorMessage;
                CurrentState = ProcessState.Error;
            }

            // Also log to output
            OutputReceived?.Invoke(this, new ProcessOutputEventArgs($"ERROR: {errorMessage}", true));
        }

        /// <summary>
        /// Disposes of resources
        /// </summary>
        public void Dispose()
        {
            if (_disposed)
                return;

            StopHealthMonitoring();

            lock (_processLock)
            {
                if (_felixProcess != null && !_felixProcess.HasExited)
                {
                    try
                    {
                        _felixProcess.Kill(entireProcessTree: true);
                        _felixProcess.WaitForExit(5000);
                    }
                    catch
                    {
                        // Best effort cleanup
                    }
                }

                _felixProcess?.Dispose();
                _felixProcess = null;
            }

            _disposed = true;
        }
    }

    /// <summary>
    /// Event arguments for process state changes
    /// </summary>
    public class ProcessStateChangedEventArgs : EventArgs
    {
        public FelixProcessManager.ProcessState NewState { get; }
        public string? ErrorMessage { get; }

        public ProcessStateChangedEventArgs(FelixProcessManager.ProcessState newState, string? errorMessage)
        {
            NewState = newState;
            ErrorMessage = errorMessage;
        }
    }

    /// <summary>
    /// Event arguments for process output
    /// </summary>
    public class ProcessOutputEventArgs : EventArgs
    {
        public string Output { get; }
        public bool IsError { get; }
        public DateTime Timestamp { get; }

        public ProcessOutputEventArgs(string output, bool isError)
        {
            Output = output;
            IsError = isError;
            Timestamp = DateTime.Now;
        }
    }
}
