using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Microsoft.Win32;
using FelixTrayManager.Models;
using FelixTrayManager.Services;

namespace FelixTrayManager.Views;

/// <summary>
/// Interaction logic for SettingsWindow.xaml
/// </summary>
public partial class SettingsWindow : Window
{
    private readonly SettingsManager _settingsManager;
    private readonly AppSettings _workingSettings;
    private ObservableCollection<AgentConfig> _agentsCollection;
    private bool _hasUnsavedChanges = false;

    // Registry key for Windows startup
    private const string StartupRegistryKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ApplicationName = "FelixTrayManager";

    public SettingsWindow(SettingsManager settingsManager)
    {
        InitializeComponent();
        _settingsManager = settingsManager ?? throw new ArgumentNullException(nameof(settingsManager));
        
        // Create a working copy of settings
        _workingSettings = new AppSettings
        {
            ServerEndpoint = _settingsManager.Settings.ServerEndpoint,
            Agents = new System.Collections.Generic.List<AgentConfig>(_settingsManager.Settings.Agents),
            AutoStartOnLogin = _settingsManager.Settings.AutoStartOnLogin,
            MaxIterations = _settingsManager.Settings.MaxIterations,
            RunInBackgroundOnClose = _settingsManager.Settings.RunInBackgroundOnClose
        };

        // Create observable collection for data binding
        _agentsCollection = new ObservableCollection<AgentConfig>(_workingSettings.Agents);
        
        LoadSettings();
    }

    /// <summary>
    /// Loads settings into UI controls
    /// </summary>
    private void LoadSettings()
    {
        ServerEndpointTextBox.Text = _workingSettings.ServerEndpoint;
        AgentsDataGrid.ItemsSource = _agentsCollection;
        MaxIterationsTextBox.Text = _workingSettings.MaxIterations.ToString();
        AutoStartCheckBox.IsChecked = _workingSettings.AutoStartOnLogin;
        RunInBackgroundCheckBox.IsChecked = _workingSettings.RunInBackgroundOnClose;
    }

    /// <summary>
    /// Handles Test Connection button click
    /// </summary>
    private async void OnTestConnectionClick(object sender, RoutedEventArgs e)
    {
        var endpoint = ServerEndpointTextBox.Text?.Trim();
        
        if (string.IsNullOrWhiteSpace(endpoint))
        {
            ConnectionStatusMessage.Text = "❌ Please enter a server endpoint URL";
            ConnectionStatusMessage.Foreground = System.Windows.Media.Brushes.Red;
            return;
        }

        // Show testing message
        ConnectionStatusMessage.Text = "⏳ Testing connection...";
        ConnectionStatusMessage.Foreground = System.Windows.Media.Brushes.Gray;
        TestConnectionButton.IsEnabled = false;

        try
        {
            var (success, message) = await _settingsManager.TestConnectionAsync(endpoint);
            
            ConnectionStatusMessage.Text = message;
            ConnectionStatusMessage.Foreground = success 
                ? System.Windows.Media.Brushes.Green 
                : System.Windows.Media.Brushes.Red;
        }
        finally
        {
            TestConnectionButton.IsEnabled = true;
        }
    }

    /// <summary>
    /// Handles Add Agent button click
    /// </summary>
    private void OnAddAgentClick(object sender, RoutedEventArgs e)
    {
        // Generate unique name
        var uniqueName = _workingSettings.GenerateUniqueAgentName();
        
        var dialog = new AgentEditDialog(uniqueName)
        {
            Owner = this
        };

        if (dialog.ShowDialog() == true)
        {
            _agentsCollection.Add(dialog.Agent);
            _hasUnsavedChanges = true;
        }
    }

    /// <summary>
    /// Handles Edit Agent button click
    /// </summary>
    private void OnEditAgentClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button button && button.Tag is AgentConfig agent)
        {
            var dialog = new AgentEditDialog(agent)
            {
                Owner = this
            };

            if (dialog.ShowDialog() == true)
            {
                // Update the agent in the collection
                var index = _agentsCollection.IndexOf(agent);
                if (index >= 0)
                {
                    _agentsCollection[index] = dialog.Agent;
                    _hasUnsavedChanges = true;
                    
                    // Refresh the DataGrid
                    AgentsDataGrid.Items.Refresh();
                }
            }
        }
    }

    /// <summary>
    /// Handles Remove Agent button click
    /// </summary>
    private void OnRemoveAgentClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button button && button.Tag is AgentConfig agent)
        {
            var result = MessageBox.Show(
                $"Are you sure you want to remove agent '{agent.DisplayName}'?",
                "Confirm Remove",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);

            if (result == MessageBoxResult.Yes)
            {
                _agentsCollection.Remove(agent);
                _hasUnsavedChanges = true;
            }
        }
    }

    /// <summary>
    /// Only allow numeric input for Max Iterations
    /// </summary>
    private void OnNumericPreviewTextInput(object sender, TextCompositionEventArgs e)
    {
        // Only allow digits
        e.Handled = !IsTextNumeric(e.Text);
    }

    /// <summary>
    /// Checks if text contains only numeric characters
    /// </summary>
    private static bool IsTextNumeric(string text)
    {
        return Regex.IsMatch(text, "^[0-9]+$");
    }

    /// <summary>
    /// Handles Reset to Defaults button click
    /// </summary>
    private void OnResetClick(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show(
            "Are you sure you want to reset all settings to their default values?",
            "Confirm Reset",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);

        if (result == MessageBoxResult.Yes)
        {
            var defaults = AppSettings.CreateDefault();
            ServerEndpointTextBox.Text = defaults.ServerEndpoint;
            _agentsCollection.Clear();
            MaxIterationsTextBox.Text = defaults.MaxIterations.ToString();
            AutoStartCheckBox.IsChecked = defaults.AutoStartOnLogin;
            RunInBackgroundCheckBox.IsChecked = defaults.RunInBackgroundOnClose;
            ConnectionStatusMessage.Text = string.Empty;
            _hasUnsavedChanges = true;
        }
    }

    /// <summary>
    /// Handles Cancel button click
    /// </summary>
    private void OnCancelClick(object sender, RoutedEventArgs e)
    {
        if (_hasUnsavedChanges)
        {
            var result = MessageBox.Show(
                "You have unsaved changes. Are you sure you want to cancel?",
                "Unsaved Changes",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);

            if (result == MessageBoxResult.No)
                return;
        }

        DialogResult = false;
        Close();
    }

    /// <summary>
    /// Handles Save button click
    /// </summary>
    private void OnSaveClick(object sender, RoutedEventArgs e)
    {
        // Validate all inputs
        if (!ValidateInputs())
            return;

        // Update working settings from UI
        _workingSettings.ServerEndpoint = ServerEndpointTextBox.Text.Trim();
        _workingSettings.Agents = _agentsCollection.ToList();
        _workingSettings.MaxIterations = int.Parse(MaxIterationsTextBox.Text);
        _workingSettings.AutoStartOnLogin = AutoStartCheckBox.IsChecked ?? false;
        _workingSettings.RunInBackgroundOnClose = RunInBackgroundCheckBox.IsChecked ?? true;

        // Apply auto-start setting
        ApplyAutoStartSetting(_workingSettings.AutoStartOnLogin);

        // Save settings
        try
        {
            _settingsManager.SaveSettings(_workingSettings);
            _hasUnsavedChanges = false;

            MessageBox.Show(
                "Settings saved successfully.",
                "Success",
                MessageBoxButton.OK,
                MessageBoxImage.Information);

            DialogResult = true;
            Close();
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"Failed to save settings: {ex.Message}",
                "Save Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    /// <summary>
    /// Validates all input fields
    /// </summary>
    private bool ValidateInputs()
    {
        // Validate server endpoint
        if (string.IsNullOrWhiteSpace(ServerEndpointTextBox.Text))
        {
            MessageBox.Show("Server endpoint is required.", "Validation Error", MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }

        if (!Uri.TryCreate(ServerEndpointTextBox.Text.Trim(), UriKind.Absolute, out _))
        {
            MessageBox.Show("Server endpoint must be a valid URL.", "Validation Error", MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }

        // Validate max iterations
        if (string.IsNullOrWhiteSpace(MaxIterationsTextBox.Text) || !int.TryParse(MaxIterationsTextBox.Text, out int maxIterations))
        {
            MessageBox.Show("Please enter a valid number for maximum iterations.", "Validation Error", MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }

        if (maxIterations < 1 || maxIterations > 10000)
        {
            MessageBox.Show("Maximum iterations must be between 1 and 10000.", "Validation Error", MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }

        // Validate agent configurations
        foreach (var agent in _agentsCollection)
        {
            if (!agent.IsValid())
            {
                MessageBox.Show(
                    $"Agent '{agent.DisplayName}' has an invalid configuration. Please check the agent path.",
                    "Validation Error",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
                return false;
            }
        }

        return true;
    }

    /// <summary>
    /// Applies or removes auto-start registry entry
    /// </summary>
    private void ApplyAutoStartSetting(bool enable)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(StartupRegistryKey, writable: true);
            if (key == null)
            {
                MessageBox.Show(
                    "Failed to access Windows startup registry key.",
                    "Auto-start Error",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
                return;
            }

            if (enable)
            {
                // Add registry entry with path to executable
                var exePath = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName;
                if (!string.IsNullOrEmpty(exePath))
                {
                    key.SetValue(ApplicationName, $"\"{exePath}\"");
                }
            }
            else
            {
                // Remove registry entry
                if (key.GetValue(ApplicationName) != null)
                {
                    key.DeleteValue(ApplicationName);
                }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"Failed to update auto-start setting: {ex.Message}",
                "Auto-start Error",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }
}
