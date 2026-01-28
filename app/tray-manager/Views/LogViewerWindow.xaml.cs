using System;
using System.Windows;
using FelixTrayManager.Services;

namespace FelixTrayManager.Views;

public partial class LogViewerWindow : Window
{
    private readonly FelixProcessManager _processManager;
    private const int MaxLogLines = 5000;

    public LogViewerWindow(FelixProcessManager processManager)
    {
        InitializeComponent();
        _processManager = processManager ?? throw new ArgumentNullException(nameof(processManager));
        _processManager.OutputReceived += OnProcessOutputReceived;
        _processManager.StateChanged += OnProcessStateChanged;
        UpdateStatus();
        LogTextBox.AppendText($"=== Felix Agent Console ===\n[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] Log viewer started\n\n");
    }

    private void OnProcessOutputReceived(object? sender, ProcessOutputEventArgs e)
    {
        Dispatcher.Invoke(() =>
        {
            var timestamp = DateTime.Now.ToString("HH:mm:ss");
            var prefix = e.IsError ? "[ERR]" : "[OUT]";
            LogTextBox.AppendText($"[{timestamp}] {prefix} {e.Output}\n");
            if (LogTextBox.LineCount > MaxLogLines)
            {
                var lines = LogTextBox.Text.Split('\n');
                LogTextBox.Text = string.Join('\n', lines[(lines.Length - MaxLogLines)..]);
            }
            if (AutoScrollCheckBox.IsChecked == true) LogScrollViewer.ScrollToEnd();
        });
    }

    private void OnProcessStateChanged(object? sender, ProcessStateChangedEventArgs e)
    {
        Dispatcher.Invoke(() =>
        {
            UpdateStatus();
            var timestamp = DateTime.Now.ToString("HH:mm:ss");
            LogTextBox.AppendText($"[{timestamp}] [STATE] {e.NewState}\n");
            if (!string.IsNullOrEmpty(e.ErrorMessage)) LogTextBox.AppendText($"[{timestamp}] [ERROR] {e.ErrorMessage}\n");
            if (AutoScrollCheckBox.IsChecked == true) LogScrollViewer.ScrollToEnd();
        });
    }

    private void UpdateStatus()
    {
        StatusText.Text = $"Status: {(_processManager.IsRunning ? "Running" : "Stopped")}";
    }

    private void OnClearClick(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show("Clear log output?", "Confirm", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
        {
            LogTextBox.Clear();
            LogTextBox.AppendText($"=== Log Cleared at {DateTime.Now:HH:mm:ss} ===\n\n");
        }
    }

    private void OnCopyClick(object sender, RoutedEventArgs e)
    {
        try
        {
            Clipboard.SetText(LogTextBox.Text);
            MessageBox.Show("Copied to clipboard", "Success", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Copy failed: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    protected override void OnClosed(EventArgs e)
    {
        base.OnClosed(e);
        _processManager.OutputReceived -= OnProcessOutputReceived;
        _processManager.StateChanged -= OnProcessStateChanged;
    }
}
