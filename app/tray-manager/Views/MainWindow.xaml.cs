using System;
using System.ComponentModel;
using System.Windows;
using Wpf.Ui;
using Wpf.Ui.Appearance;

namespace FelixTrayApp.Views;

public partial class MainWindow
{
    public MainWindow()
    {
        InitializeComponent();

        // Apply theme
        SystemThemeWatcher.Watch(this);
        ApplicationThemeManager.Apply(ApplicationTheme.Dark, Wpf.Ui.Controls.WindowBackdropType.Mica);

        // Hide to tray on close instead of shutting down
        Closing += OnClosing;
        StateChanged += OnStateChanged;
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        // Don't actually close, just hide
        e.Cancel = true;
        Hide();
    }

    private void OnStateChanged(object? sender, EventArgs e)
    {
        // Hide to tray when minimized
        if (WindowState == WindowState.Minimized)
        {
            Hide();
        }
    }
}
