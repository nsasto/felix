using System;
using System.Windows;
using System.Windows.Media.Imaging;
using Hardcodet.Wpf.TaskbarNotification;
using FelixTrayManager.Models;

namespace FelixTrayManager.Services
{
    /// <summary>
    /// Manages the Windows system tray icon, context menu, and visual state
    /// </summary>
    public class TrayIconManager : IDisposable
    {
        private readonly TaskbarIcon _taskbarIcon;
        private readonly FelixProcessManager _processManager;
        private StateMonitor? _stateMonitor;
        private bool _disposed;

        // Icon state URIs
        private static readonly Uri IdleIconUri = new Uri("pack://application:,,,/Resources/felix-idle.ico");
        private static readonly Uri RunningIconUri = new Uri("pack://application:,,,/Resources/felix-running.ico");
        private static readonly Uri ErrorIconUri = new Uri("pack://application:,,,/Resources/felix-error.ico");

        /// <summary>
        /// Current icon state
        /// </summary>
        public enum IconState
        {
            Idle,
            Running,
            Error
        }

        private IconState _currentIconState = IconState.Idle;

        /// <summary>
        /// Creates a new TrayIconManager
        /// </summary>
        /// <param name="processManager">Felix process manager instance</param>
        /// <param name="stateMonitor">Felix state monitor instance (can be null if not configured yet)</param>
        public TrayIconManager(FelixProcessManager processManager, StateMonitor? stateMonitor)
        {
            _processManager = processManager ?? throw new ArgumentNullException(nameof(processManager));
            _stateMonitor = stateMonitor;

            // Initialize the taskbar icon
            _taskbarIcon = new TaskbarIcon
            {
                IconSource = new BitmapImage(IdleIconUri),
                ToolTipText = "Felix: Stopped"
            };

            // Subscribe to process state changes
            _processManager.StateChanged += OnProcessStateChanged;

            // Subscribe to Felix state changes (only if state monitor exists)
            if (_stateMonitor != null)
            {
                _stateMonitor.StateChanged += OnFelixStateChanged;
            }

            // Set up double-click handler
            _taskbarIcon.TrayMouseDoubleClick += OnTrayIconDoubleClick;

            // Initialize to idle state
            UpdateIconState(IconState.Idle, "Felix: Stopped");
        }

        /// <summary>
        /// Gets the TaskbarIcon instance for attaching context menu
        /// </summary>
        public TaskbarIcon TaskbarIcon => _taskbarIcon;

        /// <summary>
        /// Updates the tray icon visual state and tooltip
        /// </summary>
        /// <param name="newState">New icon state</param>
        /// <param name="tooltipText">Tooltip text to display</param>
        public void UpdateIconState(IconState newState, string tooltipText)
        {
            if (_disposed)
                return;

            // Update icon if state changed
            if (_currentIconState != newState)
            {
                _currentIconState = newState;

                Uri iconUri = newState switch
                {
                    IconState.Running => RunningIconUri,
                    IconState.Error => ErrorIconUri,
                    _ => IdleIconUri
                };

                Application.Current.Dispatcher.Invoke(() =>
                {
                    _taskbarIcon.IconSource = new BitmapImage(iconUri);
                });
            }

            // Update tooltip
            Application.Current.Dispatcher.Invoke(() =>
            {
                _taskbarIcon.ToolTipText = tooltipText;
            });
        }

        /// <summary>
        /// Handles process state changes from FelixProcessManager
        /// </summary>
        private void OnProcessStateChanged(object? sender, ProcessStateChangedEventArgs e)
        {
            switch (e.NewState)
            {
                case FelixProcessManager.ProcessState.Stopped:
                    UpdateIconState(IconState.Idle, "Felix: Stopped");
                    break;

                case FelixProcessManager.ProcessState.Starting:
                    UpdateIconState(IconState.Running, "Felix: Starting...");
                    break;

                case FelixProcessManager.ProcessState.Running:
                    // Let state monitor drive the tooltip when running
                    UpdateIconState(IconState.Running, "Felix: Running");
                    break;

                case FelixProcessManager.ProcessState.Error:
                    var errorMessage = e.ErrorMessage ?? "Unknown error";
                    UpdateIconState(IconState.Error, $"Felix: Error - {errorMessage}");
                    break;
            }
        }

        /// <summary>
        /// Handles Felix state changes from StateMonitor
        /// </summary>
        private void OnFelixStateChanged(object? sender, StateChangedEventArgs e)
        {
            // Only update tooltip if process is running
            if (_processManager.CurrentState != FelixProcessManager.ProcessState.Running)
            {
                return;
            }

            var state = e.State;

            if (state == null)
            {
                UpdateIconState(IconState.Running, "Felix: Running");
                return;
            }

            // Determine icon state based on Felix state
            IconState iconState;
            if (state.IsError)
            {
                iconState = IconState.Error;
            }
            else if (state.IsRunning)
            {
                iconState = IconState.Running;
            }
            else
            {
                iconState = IconState.Idle;
            }

            // Generate tooltip with detailed information
            var tooltipText = GenerateTooltipFromState(state);

            UpdateIconState(iconState, tooltipText);
        }

        /// <summary>
        /// Generates a detailed tooltip message from Felix state
        /// </summary>
        private string GenerateTooltipFromState(FelixState state)
        {
            if (state.IsError)
            {
                return state.BlockedTask != null
                    ? $"Felix: Error - {state.BlockedTask}"
                    : "Felix: Error occurred";
            }

            if (state.IsRunning && !string.IsNullOrEmpty(state.CurrentRequirementId))
            {
                return $"Felix: Running - {state.CurrentRequirementId} (Iteration {state.CurrentIteration})";
            }

            if (state.IsRunning)
            {
                return $"Felix: Running - Iteration {state.CurrentIteration}";
            }

            return "Felix: Stopped";
        }

        /// <summary>
        /// Handles double-click on tray icon - shows About dialog
        /// </summary>
        private void OnTrayIconDoubleClick(object? sender, RoutedEventArgs e)
        {
            // TODO: Show About dialog when implemented (Phase 9)
            // For now, show a simple message
            ShowStatusMessage();
        }

        /// <summary>
        /// Shows a status message balloon notification
        /// </summary>
        private void ShowStatusMessage()
        {
            var state = _stateMonitor?.CurrentState;
            var processState = _processManager.CurrentState;

            string title = "Felix Tray Manager";
            string message;

            if (processState == FelixProcessManager.ProcessState.Running && state != null)
            {
                message = state.GetStatusMessage();
            }
            else
            {
                message = $"Process: {processState}";
            }

            _taskbarIcon.ShowBalloonTip(title, message, BalloonIcon.Info);
        }

        /// <summary>
        /// Updates the state monitor instance (used when settings are changed)
        /// </summary>
        /// <param name="stateMonitor">New state monitor instance</param>
        public void UpdateStateMonitor(StateMonitor stateMonitor)
        {
            // Unsubscribe from old state monitor if it exists
            if (_stateMonitor != null)
            {
                _stateMonitor.StateChanged -= OnFelixStateChanged;
            }

            // Subscribe to new state monitor
            _stateMonitor = stateMonitor;
            if (_stateMonitor != null)
            {
                _stateMonitor.StateChanged += OnFelixStateChanged;
            }
        }

        /// <summary>
        /// Shows a balloon notification
        /// </summary>
        /// <param name="title">Notification title</param>
        /// <param name="message">Notification message</param>
        /// <param name="icon">Icon type</param>
        public void ShowNotification(string title, string message, BalloonIcon icon = BalloonIcon.Info)
        {
            if (_disposed)
                return;

            Application.Current.Dispatcher.Invoke(() =>
            {
                _taskbarIcon.ShowBalloonTip(title, message, icon);
            });
        }

        /// <summary>
        /// Disposes of resources
        /// </summary>
        public void Dispose()
        {
            if (_disposed)
                return;

            // Unsubscribe from events
            _processManager.StateChanged -= OnProcessStateChanged;
            if (_stateMonitor != null)
            {
                _stateMonitor.StateChanged -= OnFelixStateChanged;
            }
            _taskbarIcon.TrayMouseDoubleClick -= OnTrayIconDoubleClick;

            // Dispose the taskbar icon
            _taskbarIcon.Dispose();

            _disposed = true;
        }
    }
}
