using System;
using System.IO;
using System.Windows;
using FelixTrayManager.Models;

namespace FelixTrayManager.Views;

/// <summary>
/// Dialog for adding or editing an agent configuration
/// </summary>
public partial class AgentEditDialog : Window
{
    public AgentConfig Agent { get; private set; }
    private readonly bool _isEditMode;

    /// <summary>
    /// Constructor for adding a new agent
    /// </summary>
    public AgentEditDialog(string uniqueName)
    {
        InitializeComponent();
        _isEditMode = false;
        
        Agent = new AgentConfig
        {
            Name = uniqueName,
            DisplayName = uniqueName,
            Enabled = true,
            LocationType = "local"
        };
        
        HeaderText.Text = "Add Agent";
        LoadAgentData();
    }

    /// <summary>
    /// Constructor for editing an existing agent
    /// </summary>
    public AgentEditDialog(AgentConfig agent)
    {
        InitializeComponent();
        _isEditMode = true;
        
        Agent = new AgentConfig
        {
            Id = agent.Id,
            Name = agent.Name,
            DisplayName = agent.DisplayName,
            AgentPath = agent.AgentPath,
            Enabled = agent.Enabled,
            LocationType = agent.LocationType
        };
        
        HeaderText.Text = "Edit Agent";
        LoadAgentData();
    }

    private void LoadAgentData()
    {
        NameTextBox.Text = Agent.Name;
        DisplayNameTextBox.Text = Agent.DisplayName;
        AgentPathTextBox.Text = Agent.AgentPath;
        EnabledCheckBox.IsChecked = Agent.Enabled;
    }

    private void OnBrowseClick(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = "Select felix-agent.ps1",
            Filter = "PowerShell Scripts (*.ps1)|*.ps1|All Files (*.*)|*.*",
            FileName = "felix-agent.ps1"
        };

        if (!string.IsNullOrEmpty(Agent.AgentPath))
        {
            var directory = Path.GetDirectoryName(Agent.AgentPath);
            if (!string.IsNullOrEmpty(directory) && Directory.Exists(directory))
            {
                dialog.InitialDirectory = directory;
            }
        }

        if (dialog.ShowDialog() == true)
        {
            AgentPathTextBox.Text = dialog.FileName;
        }
    }

    private void OnSaveClick(object sender, RoutedEventArgs e)
    {
        // Validate inputs
        if (string.IsNullOrWhiteSpace(DisplayNameTextBox.Text))
        {
            ShowValidationMessage("Display name is required.");
            return;
        }

        if (string.IsNullOrWhiteSpace(AgentPathTextBox.Text))
        {
            ShowValidationMessage("Agent path is required.");
            return;
        }

        if (!File.Exists(AgentPathTextBox.Text))
        {
            ShowValidationMessage("The specified agent file does not exist.");
            return;
        }

        var fileName = Path.GetFileName(AgentPathTextBox.Text);
        if (!fileName.Equals("felix-agent.ps1", StringComparison.OrdinalIgnoreCase))
        {
            ShowValidationMessage("The selected file must be named 'felix-agent.ps1'.");
            return;
        }

        // Update agent configuration
        Agent.DisplayName = DisplayNameTextBox.Text.Trim();
        Agent.AgentPath = AgentPathTextBox.Text.Trim();
        Agent.Enabled = EnabledCheckBox.IsChecked ?? true;

        DialogResult = true;
        Close();
    }

    private void OnCancelClick(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    private void ShowValidationMessage(string message)
    {
        ValidationMessage.Text = message;
        ValidationMessage.Visibility = Visibility.Visible;
    }
}
