using System;
using System.ComponentModel;
using System.Windows;
using FelixTrayApp.Services;
using Wpf.Ui;
using Wpf.Ui.Appearance;

namespace FelixTrayApp.Views;

public partial class MainWindow
{
    private readonly WindowSettingsService _settingsService;

    public MainWindow()
    {
        InitializeComponent();

        _settingsService = new WindowSettingsService();

        // Apply theme
        SystemThemeWatcher.Watch(this);
        ApplicationThemeManager.Apply(ApplicationTheme.Dark, Wpf.Ui.Controls.WindowBackdropType.Mica);

        // Load window settings
        LoadWindowSettings();

        // Hide to tray on close instead of shutting down
        Closing += OnClosing;
        StateChanged += OnStateChanged;
        SizeChanged += OnSizeChanged;
        LocationChanged += OnLocationChanged;
    }

    private void LoadWindowSettings()
    {
        var settings = _settingsService.LoadSettings();
        
        Width = settings.Width;
        Height = settings.Height;
        
        if (!double.IsNaN(settings.Left))
            Left = settings.Left;
        
        if (!double.IsNaN(settings.Top))
            Top = settings.Top;
        
        if (settings.IsMaximized)
            WindowState = WindowState.Maximized;
    }

    private void SaveWindowSettings()
    {
        var settings = new WindowSettings
        {
            Width = WindowState == WindowState.Normal ? Width : RestoreBounds.Width,
            Height = WindowState == WindowState.Normal ? Height : RestoreBounds.Height,
            Left = WindowState == WindowState.Normal ? Left : RestoreBounds.Left,
            Top = WindowState == WindowState.Normal ? Top : RestoreBounds.Top,
            IsMaximized = WindowState == WindowState.Maximized
        };
        
        _settingsService.SaveSettings(settings);
    }

    private void OnSizeChanged(object? sender, SizeChangedEventArgs e)
    {
        if (WindowState == WindowState.Normal)
        {
            SaveWindowSettings();
        }
    }

    private void OnLocationChanged(object? sender, EventArgs e)
    {
        if (WindowState == WindowState.Normal)
        {
            SaveWindowSettings();
        }
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        // Save settings before hiding
        SaveWindowSettings();
        
        // Don't actually close, just hide
        e.Cancel = true;
        Hide();
    }

    private void OnStateChanged(object? sender, EventArgs e)
    {
        // Save maximized state
        SaveWindowSettings();
        
        // Hide to tray when minimized
        if (WindowState == WindowState.Minimized)
        {
            Hide();
        }
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        // Save settings and hide window (keep app running in tray)
        SaveWindowSettings();
        Hide();
    }
}
