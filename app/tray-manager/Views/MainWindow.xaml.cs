using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls.Primitives;
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
        
        // Set splitter position in ViewModel and apply to column
        if (DataContext is ViewModels.MainViewModel viewModel)
        {
            viewModel.RunHistorySplitterPosition = settings.RunHistorySplitterPosition;
            
            // Apply to column width when loaded
            Loaded += (s, e) =>
            {
                if (RunHistoryLeftColumn != null)
                {
                    RunHistoryLeftColumn.Width = new GridLength(settings.RunHistorySplitterPosition);
                }
                
                // Apply DataGrid column widths
                if (AgentsDataGrid != null && AgentsDataGrid.Columns.Count >= 5)
                {
                    if (!double.IsNaN(settings.AgentStatusColumnWidth))
                        AgentsDataGrid.Columns[2].Width = settings.AgentStatusColumnWidth;
                    if (!double.IsNaN(settings.AgentLastRunColumnWidth))
                        AgentsDataGrid.Columns[3].Width = settings.AgentLastRunColumnWidth;
                    if (!double.IsNaN(settings.AgentLastFeatureColumnWidth))
                        AgentsDataGrid.Columns[4].Width = settings.AgentLastFeatureColumnWidth;
                    if (!double.IsNaN(settings.AgentOperationsColumnWidth))
                        AgentsDataGrid.Columns[5].Width = settings.AgentOperationsColumnWidth;
                }
            };
        }
    }

    private void SaveWindowSettings()
    {
        var settings = new WindowSettings
        {
            Width = WindowState == WindowState.Normal ? Width : RestoreBounds.Width,
            Height = WindowState == WindowState.Normal ? Height : RestoreBounds.Height,
            Left = WindowState == WindowState.Normal ? Left : RestoreBounds.Left,
            Top = WindowState == WindowState.Normal ? Top : RestoreBounds.Top,
            IsMaximized = WindowState == WindowState.Maximized,
            RunHistorySplitterPosition = (DataContext as ViewModels.MainViewModel)?.RunHistorySplitterPosition ?? 300
        };
        
        // Save DataGrid column widths
        if (AgentsDataGrid != null && AgentsDataGrid.Columns.Count >= 6)
        {
            settings.AgentStatusColumnWidth = AgentsDataGrid.Columns[2].ActualWidth;
            settings.AgentLastRunColumnWidth = AgentsDataGrid.Columns[3].ActualWidth;
            settings.AgentLastFeatureColumnWidth = AgentsDataGrid.Columns[4].ActualWidth;
            settings.AgentOperationsColumnWidth = AgentsDataGrid.Columns[5].ActualWidth;
        }
        
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

    private void GridSplitter_DragCompleted(object sender, DragCompletedEventArgs e)
    {
        // Save the new column width when splitter is moved
        if (RunHistoryLeftColumn != null && DataContext is ViewModels.MainViewModel viewModel)
        {
            viewModel.RunHistorySplitterPosition = RunHistoryLeftColumn.ActualWidth;
            SaveWindowSettings();
        }
    }
}
