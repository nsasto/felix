using System.Windows;
using FelixTrayApp.Services;
using FelixTrayApp.Views;
using Wpf.Ui;

namespace FelixTrayApp;

public partial class App : Application
{
    private TrayService? _trayService;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Initialize tray service (will create tray icon)
        _trayService = new TrayService();

        // Don't show window on startup - tray only
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayService?.Dispose();
        base.OnExit(e);
    }

    public void ShowMainWindow()
    {
        if (MainWindow == null)
        {
            MainWindow = new MainWindow();
            MainWindow.Closed += (s, e) =>
            {
                MainWindow = null;
            };
        }

        MainWindow.Show();
        MainWindow.WindowState = WindowState.Normal;
        MainWindow.Activate();
    }
}
