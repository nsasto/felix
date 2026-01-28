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

    // Context menu items (need references for enable/disable logic)
    private MenuItem? _startMenuItem;
    private MenuItem? _stopMenuItem;
    private MenuItem? _settingsMenuItem;
    private MenuItem? _aboutMenuItem;
    private MenuItem? _exitMenuItem;

    private void Application_Startup(object sender, StartupEventArgs e)
    {
        // Initialize service managers
        _settingsManager = new SettingsManager();
        _processManager = new FelixProcessManager();
        _stateMonitor = new StateMonitor(_settingsManager.Settings.ProjectPath);
        _trayIconManager = new TrayIconManager(_processManager, _stateMonitor);

        // Subscribe to process state changes for menu updates
        _processManager.StateChanged += OnProcessStateChanged;

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

        // No main window - run minimized to tray
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
            MessageBox.Show(
                "Please configure a valid Felix project path in Settings before starting.",
                "Invalid Configuration",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        // Start the Felix agent
        var success = await _processManager.StartAsync(_settingsManager.Settings);

        if (!success)
        {
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
            await _processManager.StopAsync(forceKill: false);
        }
    }

    /// <summary>
    /// Handles Settings menu item click
    /// </summary>
    private void OnSettingsClick(object sender, RoutedEventArgs e)
    {
        // TODO: Open Settings window (Phase 8)
        MessageBox.Show(
            "Settings window coming soon in Phase 8.",
            "Settings",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    /// <summary>
    /// Handles About menu item click
    /// </summary>
    private void OnAboutClick(object sender, RoutedEventArgs e)
    {
        // TODO: Open About dialog (Phase 9)
        MessageBox.Show(
            "Felix Tray Manager\nVersion 1.0.0\n\nWindows system tray manager for Felix autonomous agent",
            "About Felix Tray Manager",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    /// <summary>
    /// Handles Exit menu item click
    /// </summary>
    private async void OnExitClick(object sender, RoutedEventArgs e)
    {
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
                return; // User cancelled exit
            }

            if (result == MessageBoxResult.Yes)
            {
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
                    break;

                case FelixProcessManager.ProcessState.Error:
                    _startMenuItem.IsEnabled = true;
                    _stopMenuItem.IsEnabled = false;
                    break;
            }
        });
    }

    private void Application_Exit(object sender, ExitEventArgs e)
    {
        // Unsubscribe from events
        if (_processManager != null)
        {
            _processManager.StateChanged -= OnProcessStateChanged;
        }

        // Clean up services
        _stateMonitor?.Stop();
        _trayIconManager?.Dispose();
        _processManager?.Dispose();
        _stateMonitor?.Dispose();
    }
}

