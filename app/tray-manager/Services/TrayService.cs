using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Forms;
using Application = System.Windows.Application;

namespace FelixTrayApp.Services;

public class TrayService : IDisposable
{
    private readonly NotifyIcon _notifyIcon;

    public TrayService()
    {
        _notifyIcon = new NotifyIcon
        {
            Icon = LoadAppIcon(),
            Visible = true,
            Text = "Felix Tray App"
        };

        var contextMenu = new ContextMenuStrip();
        contextMenu.Items.Add("Open", null, OnOpen);
        contextMenu.Items.Add("Settings", null, OnSettings);
        contextMenu.Items.Add("-");
        contextMenu.Items.Add("Exit", null, OnExit);

        _notifyIcon.ContextMenuStrip = contextMenu;
        _notifyIcon.DoubleClick += (s, e) => OnOpen(s, e);
    }

    private Icon LoadAppIcon()
    {
        try
        {
            // Try to load from Assets folder relative to executable
            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            var iconPath = Path.Combine(baseDir, "Assets", "app.ico");
            
            if (File.Exists(iconPath))
            {
                return new Icon(iconPath);
            }
            
            // Try alternate location (for development)
            iconPath = Path.Combine(baseDir, @"..\..\..\Assets\app.ico");
            if (File.Exists(Path.GetFullPath(iconPath)))
            {
                return new Icon(Path.GetFullPath(iconPath));
            }
        }
        catch
        {
            // Fallback to default icon if loading fails
        }
        
        // Create a simple colored square as fallback
        using var bitmap = new Bitmap(32, 32);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.Clear(Color.DodgerBlue);
        using var pen = new Pen(Color.White, 2);
        graphics.DrawRectangle(pen, 4, 4, 24, 24);
        
        return Icon.FromHandle(bitmap.GetHicon());
    }

    private void OnOpen(object? sender, EventArgs e)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            ((App)Application.Current).ShowMainWindow();
        });
    }

    private void OnSettings(object? sender, EventArgs e)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            ((App)Application.Current).ShowMainWindow();
            // TODO: Navigate to settings page
        });
    }

    private void OnExit(object? sender, EventArgs e)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            Application.Current.Shutdown();
        });
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
    }

    public void ShowNotification(string title, string message, ToolTipIcon icon = ToolTipIcon.Info)
    {
        _notifyIcon.ShowBalloonTip(3000, title, message, icon);
    }
}
