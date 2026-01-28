using System.Configuration;
using System.Data;
using System.Windows;
using Hardcodet.Wpf.TaskbarNotification;

namespace FelixTrayManager;

/// <summary>
/// Interaction logic for App.xaml
/// </summary>
public partial class App : Application
{
    private TaskbarIcon? _notifyIcon;

    private void Application_Startup(object sender, StartupEventArgs e)
    {
        // Initialize the system tray icon
        _notifyIcon = new TaskbarIcon
        {
            IconSource = new System.Windows.Media.Imaging.BitmapImage(
                new Uri("pack://application:,,,/Resources/felix-idle.ico")),
            ToolTipText = "Felix: Stopped"
        };

        // Set up context menu
        var contextMenu = new System.Windows.Controls.ContextMenu();
        
        var startMenuItem = new System.Windows.Controls.MenuItem { Header = "Start Felix" };
        var stopMenuItem = new System.Windows.Controls.MenuItem { Header = "Stop Felix" };
        var settingsMenuItem = new System.Windows.Controls.MenuItem { Header = "Settings" };
        var aboutMenuItem = new System.Windows.Controls.MenuItem { Header = "About" };
        var exitMenuItem = new System.Windows.Controls.MenuItem { Header = "Exit" };

        contextMenu.Items.Add(startMenuItem);
        contextMenu.Items.Add(stopMenuItem);
        contextMenu.Items.Add(new System.Windows.Controls.Separator());
        contextMenu.Items.Add(settingsMenuItem);
        contextMenu.Items.Add(aboutMenuItem);
        contextMenu.Items.Add(new System.Windows.Controls.Separator());
        contextMenu.Items.Add(exitMenuItem);

        exitMenuItem.Click += (s, args) => Application.Current.Shutdown();

        _notifyIcon.ContextMenu = contextMenu;

        // No main window - run minimized to tray
    }

    private void Application_Exit(object sender, ExitEventArgs e)
    {
        _notifyIcon?.Dispose();
    }
}

