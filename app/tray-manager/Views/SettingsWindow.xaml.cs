using System;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
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
            ProjectPath = _settingsManager.Settings.ProjectPath,
            AutoStartOnLogin = _settingsManager.Settings.AutoStartOnLogin,
            MaxIterations = _settingsManager.Settings.MaxIterations,
            RunInBackgroundOnClose = _settingsManager.Settings.RunInBackgroundOnClose
        };

        LoadSettings();
        ValidateProjectPath();
    }

    /// <summary>
    /// Loads settings into UI controls
    /// </summary>
    private void LoadSettings()
    {
        ProjectPathTextBox.Text = _workingSettings.ProjectPath;
        MaxIterationsTextBox.Text = _workingSettings.MaxIterations.ToString();
        AutoStartCheckBox.IsChecked = _workingSettings.AutoStartOnLogin;
        RunInBackgroundCheckBox.IsChecked = _workingSettings.RunInBackgroundOnClose;
    }

    /// <summary>
    /// Handles Browse button click to select project folder
    /// </summary>
    private void OnBrowseClick(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog
        {
            Title = "Select Felix Project Folder",
            InitialDirectory = string.IsNullOrEmpty(_workingSettings.ProjectPath) 
                ? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
                : _workingSettings.ProjectPath
        };

        if (dialog.ShowDialog() == true)
        {
            ProjectPathTextBox.Text = dialog.FolderName;
            _hasUnsavedChanges = true;
        }
    }

    /// <summary>
    /// Validates the project path when it changes
    /// </summary>
    private void OnProjectPathChanged(object sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        ValidateProjectPath();
        _hasUnsavedChanges = true;
    }

    /// <summary>
    /// Validates that the project path contains a felix/ directory
    /// </summary>
    private void ValidateProjectPath()
    {
        var path = ProjectPathTextBox.Text;

        if (string.IsNullOrWhiteSpace(path))
        {
            ShowValidationMessage("Project path is required.");
            SaveButton.IsEnabled = false;
            return;
        }

        if (!Directory.Exists(path))
        {
            ShowValidationMessage("The specified directory does not exist.");
            SaveButton.IsEnabled = false;
            return;
        }

        var felixDir = Path.Combine(path, "felix");
        if (!Directory.Exists(felixDir))
        {
            ShowValidationMessage("The selected directory does not contain a 'felix' folder. Please select a valid Felix project directory.");
            SaveButton.IsEnabled = false;
            return;
        }

        // Valid path
        HideValidationMessage();
        SaveButton.IsEnabled = true;
    }

    /// <summary>
    /// Shows validation error message
    /// </summary>
    private void ShowValidationMessage(string message)
    {
        ValidationMessage.Text = message;
        ValidationMessage.Visibility = Visibility.Visible;
    }

    /// <summary>
    /// Hides validation error message
    /// </summary>
    private void HideValidationMessage()
    {
        ValidationMessage.Visibility = Visibility.Collapsed;
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
            ProjectPathTextBox.Text = defaults.ProjectPath;
            MaxIterationsTextBox.Text = defaults.MaxIterations.ToString();
            AutoStartCheckBox.IsChecked = defaults.AutoStartOnLogin;
            RunInBackgroundCheckBox.IsChecked = defaults.RunInBackgroundOnClose;
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
        _workingSettings.ProjectPath = ProjectPathTextBox.Text;
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
        // Validate project path
        if (string.IsNullOrWhiteSpace(ProjectPathTextBox.Text))
        {
            MessageBox.Show("Project path is required.", "Validation Error", MessageBoxButton.OK, MessageBoxImage.Warning);
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
