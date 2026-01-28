using System.Configuration;
using System.Data;
using System.Windows;
using System.Windows.Controls;
using Hardcodet.Wpf.TaskbarNotification;
using FelixTrayManager.Services;

namespace FelixTrayManager;

/// <summary>
/// Interaction logic for App.xaml
/// </summary>
public partial class App : Application
{
    private TrayIconManager? _trayIconManager;
    private FelixProcessManager? _processManager;
    private StateMonitor? _stateMonitor;
    private SettingsManager? _settingsManager;
    private Logger? _logger;

    // Context menu items (need references for enable/disable logic)
    private MenuItem? _startMenuItem;
    private MenuItem? _stopMenuItem;
    private MenuItem? _settingsMenuItem;
    private MenuItem? _aboutMenuItem;
    private MenuItem? _exitMenuItem;

    private void Application_Startup(object sender, StartupEventArgs e)
    {
        // Initialize logger first
        _logger = new Logger();
        _logger.Info("Application starting...");

        // Rotate log if needed (keep logs under 10MB)
        _logger.RotateIfNeeded();

        try
        {
            // Initialize service managers
            _settingsManager = new SettingsManager();
            _logger.Info("Settings manager initialized");

            _processManager = new FelixProcessManager();
            _logger.Info("Process manager initialized");

            _stateMonitor = new StateMonitor(_settingsManager.Settings.ProjectPath);
            _logger.Info($"State monitor initialized (watching: {_settingsManager.Settings.ProjectPath})");

            _trayIconManager = new TrayIconManager(_processManager, _stateMonitor);
            _logger.Info("Tray icon manager initialized");

            // Subscribe to process state changes for menu updates
            _processManager.StateChanged += OnProcessStateChanged;

            // Subscribe to process output for logging
            _processManager.OutputReceived += OnProcessOutputReceived;

        // Set up context menu
        var contextMenu = new ContextMenu();
        
        _startMenuItem = new MenuItem { Header = "Start Felix" };
        _stopMenuItem = new MenuItem { Header = "Stop Felix", IsEnabled = false };
        _settingsMenuItem = new MenuItem { Header = "Settings" };
        _aboutMenuItem = new MenuItem { Header = "About" };
        _exitMenuItem = new MenuItem { Header = "Exit" };

        // Attach event handlers
        _startMenuItem.Click += OnStartFelixClick;
        _stopMenuItem.Click += OnStopFelixClick;
        _settingsMenuItem.Click += OnSettingsClick;
        _aboutMenuItem.Click += OnAboutClick;
        _exitMenuItem.Click += OnExitClick;

        contextMenu.Items.Add(_startMenuItem);
        contextMenu.Items.Add(_stopMenuItem);
        contextMenu.Items.Add(new Separator());
        contextMenu.Items.Add(_settingsMenuItem);
        contextMenu.Items.Add(_aboutMenuItem);
        contextMenu.Items.Add(new Separator());
        contextMenu.Items.Add(_exitMenuItem);

        _trayIconManager.TaskbarIcon.ContextMenu = contextMenu;

            // Start state monitoring
            _stateMonitor.Start();
            _logger.Info("State monitoring started");

            // No main window - run minimized to tray
            _logger.Info("Application startup complete - running in system tray");
        }
        catch (Exception ex)
        {
            _logger?.Error("Application startup failed", ex);
            MessageBox.Show(
                $"Failed to start Felix Tray Manager: {ex.Message}",
                "Startup Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Application.Current.Shutdown(1);
        }
    }

    /// <summary>
    /// Handles Start Felix menu item click
    /// </summary>
    private async void OnStartFelixClick(object sender, RoutedEventArgs e)
    {
        if (_processManager == null || _settingsManager == null)
            return;

        // Validate settings before starting
        if (!_settingsManager.Settings.IsValid())
        {
            _logger?.Warning("Cannot start Felix: Invalid project path configuration");
            
            // Show configuration error notification
            _trayIconManager?.ShowNotification(
                "Configuration Error",
                "Please configure a valid Felix project path in Settings before starting.",
                Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Warning);
            
            MessageBox.Show(
                "Please configure a valid Felix project path in Settings before starting.",
                "Invalid Configuration",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        _logger?.Info($"User initiated Felix start (project: {_settingsManager.Settings.ProjectPath})");

        // Start the Felix agent
        var success = await _processManager.StartAsync(_settingsManager.Settings);

        if (!success)
        {
            _logger?.Error($"Failed to start Felix: {_processManager.LastErrorMessage}");
            MessageBox.Show(
                $"Failed to start Felix agent: {_processManager.LastErrorMessage}",
                "Start Failed",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    /// <summary>
    /// Handles Stop Felix menu item click
    /// </summary>
    private async void OnStopFelixClick(object sender, RoutedEventArgs e)
    {
        if (_processManager == null)
            return;

        // Ask for confirmation
        var result = MessageBox.Show(
            "Are you sure you want to stop the Felix agent?",
            "Confirm Stop",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);

        if (result == MessageBoxResult.Yes)
        {
            _logger?.Info("User initiated Felix stop");
            await _processManager.StopAsync(forceKill: false);
        }
        else
        {
            _logger?.Debug("User cancelled Felix stop");
        }
    }

    /// <summary>
    /// Handles Settings menu item click
    /// </summary>
    private void OnSettingsClick(object sender, RoutedEventArgs e)
    {
        if (_settingsManager == null)
            return;

        _logger?.Debug("Opening Settings window");

        // Open Settings window
        var settingsWindow = new Views.SettingsWindow(_settingsManager);
        var result = settingsWindow.ShowDialog();

        // If settings were saved, update state monitor with new project path
        if (result == true && _stateMonitor != null)
        {
            _logger?.Info($"Settings updated. New project path: {_settingsManager.Settings.ProjectPath}");
            _stateMonitor.UpdateProjectPath(_settingsManager.Settings.ProjectPath);
        }
    }

    /// <summary>
    /// Handles About menu item click
    /// </summary>
    private void OnAboutClick(object sender, RoutedEventArgs e)
    {
        _logger?.Debug("Opening About dialog");
        
        // Open About dialog
        var aboutWindow = new Views.AboutWindow();
        aboutWindow.ShowDialog();
    }

    /// <summary>
    /// Handles Exit menu item click
    /// </summary>
    private async void OnExitClick(object sender, RoutedEventArgs e)
    {
        _logger?.Info("User initiated application exit");

        // Stop Felix if running
        if (_processManager != null && _processManager.IsRunning)
        {
            var result = MessageBox.Show(
                "Felix agent is currently running. Stop it before exiting?",
                "Confirm Exit",
                MessageBoxButton.YesNoCancel,
                MessageBoxImage.Question);

            if (result == MessageBoxResult.Cancel)
            {
                _logger?.Debug("User cancelled application exit");
                return; // User cancelled exit
            }

            if (result == MessageBoxResult.Yes)
            {
                _logger?.Info("Stopping Felix agent before exit");
                await _processManager.StopAsync(forceKill: false);
            }
        }

        // Shutdown application
        Application.Current.Shutdown();
    }

    /// <summary>
    /// Handles process state changes to update menu item states
    /// </summary>
    private void OnProcessStateChanged(object? sender, ProcessStateChangedEventArgs e)
    {
        // Log state change
        _logger?.Info($"Felix process state changed: {e.NewState}" + 
            (e.ErrorMessage != null ? $" - {e.ErrorMessage}" : ""));

        // Update menu items on UI thread
        Dispatcher.Invoke(() =>
        {
            if (_startMenuItem == null || _stopMenuItem == null)
                return;

            switch (e.NewState)
            {
                case FelixProcessManager.ProcessState.Stopped:
                    _startMenuItem.IsEnabled = true;
                    _stopMenuItem.IsEnabled = false;
                    break;

                case FelixProcessManager.ProcessState.Starting:
                    _startMenuItem.IsEnabled = false;
                    _stopMenuItem.IsEnabled = false;
                    break;

                case FelixProcessManager.ProcessState.Running:
                    _startMenuItem.IsEnabled = false;
                    _stopMenuItem.IsEnabled = true;
                    // Show success notification
                    _trayIconManager?.ShowNotification(
                        "Felix Started",
                        "Felix agent is now running and monitoring your project.",
                        Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Info);
                    break;

                case FelixProcessManager.ProcessState.Error:
                    _startMenuItem.IsEnabled = true;
                    _stopMenuItem.IsEnabled = false;
                    // Show error notification
                    var errorMsg = e.ErrorMessage ?? "An unknown error occurred";
                    _trayIconManager?.ShowNotification(
                        "Felix Error",
                        errorMsg,
                        Hardcodet.Wpf.TaskbarNotification.BalloonIcon.Error);
                    break;
            }
        });
    }

    /// <summary>
    /// Handles process output for logging
    /// </summary>
    private void OnProcessOutputReceived(object? sender, ProcessOutputEventArgs e)
    {
        // Log process output (prefix with [Felix] to distinguish from tray app logs)
        if (e.IsError)
        {
            _logger?.Error($"[Felix Agent] {e.Output}");
        }
        else
        {
            _logger?.Debug($"[Felix Agent] {e.Output}");
        }
    }

    private void Application_Exit(object sender, ExitEventArgs e)
    {
        _logger?.Info("Application shutting down...");

        // Unsubscribe from events
        if (_processManager != null)
        {
            _processManager.StateChanged -= OnProcessStateChanged;
            _processManager.OutputReceived -= OnProcessOutputReceived;
        }

        // Clean up services
        _stateMonitor?.Stop();
        _trayIconManager?.Dispose();
        _processManager?.Dispose();
        _stateMonitor?.Dispose();

        // Dispose logger last (so we can log cleanup events)
        _logger?.Dispose();
    }
}

