using System;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;
using FelixTrayManager.Models;

namespace FelixTrayManager.Services
{
    /// <summary>
    /// Monitors felix/state.json for changes and provides state updates
    /// </summary>
    public class StateMonitor : IDisposable
    {
        private readonly DispatcherTimer _pollTimer;
        private string _projectPath;
        private readonly JsonSerializerOptions _jsonOptions;
        private FelixState? _lastState;
        private bool _disposed;

        /// <summary>
        /// Current Felix state, null if not available or error
        /// </summary>
        public FelixState? CurrentState
        {
            get => _lastState;
            private set
            {
                var oldState = _lastState;
                _lastState = value;
                
                // Raise event if state changed
                if (HasStateChanged(oldState, value))
                {
                    StateChanged?.Invoke(this, new StateChangedEventArgs(value));
                }
            }
        }

        /// <summary>
        /// Event raised when the Felix state changes
        /// </summary>
        public event EventHandler<StateChangedEventArgs>? StateChanged;

        /// <summary>
        /// Event raised when there's an error reading the state file
        /// </summary>
        public event EventHandler<StateErrorEventArgs>? StateError;

        /// <summary>
        /// Creates a new StateMonitor for the specified project path
        /// </summary>
        /// <param name="projectPath">Path to the Felix project root directory</param>
        /// <param name="pollIntervalMs">Polling interval in milliseconds (default: 2500ms)</param>
        public StateMonitor(string projectPath, int pollIntervalMs = 2500)
        {
            if (string.IsNullOrWhiteSpace(projectPath))
            {
                throw new ArgumentException("Project path cannot be null or empty", nameof(projectPath));
            }

            _projectPath = projectPath;

            _jsonOptions = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
                AllowTrailingCommas = true
            };

            // Create timer for polling
            _pollTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(pollIntervalMs)
            };
            _pollTimer.Tick += OnPollTick;
        }

        /// <summary>
        /// Starts monitoring the state file
        /// </summary>
        public void Start()
        {
            if (_disposed)
            {
                throw new ObjectDisposedException(nameof(StateMonitor));
            }

            // Do an immediate poll
            PollStateFile();

            // Start the timer
            _pollTimer.Start();
        }

        /// <summary>
        /// Stops monitoring the state file
        /// </summary>
        public void Stop()
        {
            _pollTimer.Stop();
        }

        /// <summary>
        /// Gets whether the monitor is currently running
        /// </summary>
        public bool IsRunning => _pollTimer.IsEnabled;

        /// <summary>
        /// Updates the project path and restarts monitoring if currently running
        /// </summary>
        /// <param name="newProjectPath">New project path to monitor</param>
        public void UpdateProjectPath(string newProjectPath)
        {
            if (string.IsNullOrWhiteSpace(newProjectPath))
            {
                throw new ArgumentException("Project path cannot be null or empty", nameof(newProjectPath));
            }

            var wasRunning = IsRunning;
            
            if (wasRunning)
            {
                Stop();
            }

            _projectPath = newProjectPath;
            _lastState = null;

            if (wasRunning)
            {
                Start();
            }
        }

        /// <summary>
        /// Manually triggers a state file poll
        /// </summary>
        public void PollNow()
        {
            PollStateFile();
        }

        /// <summary>
        /// Timer tick handler
        /// </summary>
        private void OnPollTick(object? sender, EventArgs e)
        {
            PollStateFile();
        }

        /// <summary>
        /// Polls the state.json file and updates CurrentState
        /// </summary>
        private void PollStateFile()
        {
            try
            {
                var stateFilePath = Path.Combine(_projectPath, "felix", "state.json");

                // Check if file exists
                if (!File.Exists(stateFilePath))
                {
                    // File doesn't exist - this might be normal if Felix hasn't run yet
                    // Set state to null but don't raise error
                    CurrentState = null;
                    return;
                }

                // Read and parse the file
                var json = File.ReadAllText(stateFilePath);
                
                if (string.IsNullOrWhiteSpace(json))
                {
                    // Empty file - treat as no state
                    CurrentState = null;
                    return;
                }

                var state = JsonSerializer.Deserialize<FelixState>(json, _jsonOptions);
                
                if (state == null)
                {
                    StateError?.Invoke(this, new StateErrorEventArgs("Deserialized state is null"));
                    return;
                }

                // Update current state
                CurrentState = state;
            }
            catch (JsonException jsonEx)
            {
                // Malformed JSON - raise error event
                StateError?.Invoke(this, new StateErrorEventArgs($"Invalid JSON in state.json: {jsonEx.Message}"));
                CurrentState = null;
            }
            catch (IOException ioEx)
            {
                // File access error - raise error event but don't crash
                StateError?.Invoke(this, new StateErrorEventArgs($"Error reading state.json: {ioEx.Message}"));
                CurrentState = null;
            }
            catch (Exception ex)
            {
                // Unexpected error
                StateError?.Invoke(this, new StateErrorEventArgs($"Unexpected error polling state: {ex.Message}"));
                CurrentState = null;
            }
        }

        /// <summary>
        /// Determines if the state has meaningfully changed
        /// </summary>
        private bool HasStateChanged(FelixState? oldState, FelixState? newState)
        {
            // Both null - no change
            if (oldState == null && newState == null)
            {
                return false;
            }

            // One is null - changed
            if (oldState == null || newState == null)
            {
                return true;
            }

            // Compare key fields that affect UI
            return oldState.Status != newState.Status ||
                   oldState.CurrentRequirementId != newState.CurrentRequirementId ||
                   oldState.CurrentIteration != newState.CurrentIteration ||
                   oldState.LastIterationOutcome != newState.LastIterationOutcome ||
                   oldState.BlockedTask != newState.BlockedTask;
        }

        /// <summary>
        /// Disposes of resources
        /// </summary>
        public void Dispose()
        {
            if (_disposed)
                return;

            Stop();
            _pollTimer.Tick -= OnPollTick;

            _disposed = true;
        }
    }

    /// <summary>
    /// Event arguments for state changes
    /// </summary>
    public class StateChangedEventArgs : EventArgs
    {
        public FelixState? State { get; }

        public StateChangedEventArgs(FelixState? state)
        {
            State = state;
        }
    }

    /// <summary>
    /// Event arguments for state monitoring errors
    /// </summary>
    public class StateErrorEventArgs : EventArgs
    {
        public string ErrorMessage { get; }
        public DateTime Timestamp { get; }

        public StateErrorEventArgs(string errorMessage)
        {
            ErrorMessage = errorMessage;
            Timestamp = DateTime.Now;
        }
    }
}
