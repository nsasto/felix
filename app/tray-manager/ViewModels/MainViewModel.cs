using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows.Input;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using FelixTrayApp.Services;

namespace FelixTrayApp.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private readonly AgentStorageService _storageService;

    [ObservableProperty]
    private ObservableCollection<AgentItem> _agents;

    [ObservableProperty]
    private ObservableCollection<AgentItem> _filteredAgents;

    [ObservableProperty]
    private string _searchText = string.Empty;

    [ObservableProperty]
    private string _userName = Environment.UserName;

    [ObservableProperty]
    private bool _showAgentsList = true;

    [ObservableProperty]
    private bool _showAgentSettings = false;

    [ObservableProperty]
    private AgentItem? _selectedAgent;

    [ObservableProperty]
    private bool _showRunHistoryView = false;

    [ObservableProperty]
    private ObservableCollection<RunHistoryItem> _runHistoryItems = new();

    [ObservableProperty]
    private RunHistoryItem? _selectedRun;

    [ObservableProperty]
    private string _reportContent = string.Empty;

    [ObservableProperty]
    private string _outputLogContent = string.Empty;

    [ObservableProperty]
    private string _planSnapshotContent = string.Empty;

    public MainViewModel()
    {
        _storageService = new AgentStorageService();
        
        // Load agents from file
        var loadedAgents = _storageService.LoadAgents();
        
        if (loadedAgents.Count == 0)
        {
            // Initialize with sample data if no saved agents
            loadedAgents = new System.Collections.Generic.List<AgentItem>
            {
                new AgentItem
                {
                    Name = "DESKTOP-PC",
                    FriendlyName = "Main Desktop Agent",
                    AgentPath = @"C:\projects\felix\felix-agent.ps1",
                    ProjectFolder = @"C:\projects\roboza\felix",
                    Status = "Idle",
                    LastRun = new DateTime(2026, 1, 29, 10, 30, 0),
                    LastFeatureName = "S-0023: Tray Manager UI",
                    IsActive = true,
                    EnableLogging = true
                },
                new AgentItem
                {
                    Name = "LAPTOP-2",
                    FriendlyName = "Laptop Agent",
                    AgentPath = @"C:\dev\felix\felix-agent.ps1",
                    ProjectFolder = @"C:\dev\roboza\felix",
                    Status = "Busy",
                    LastRun = new DateTime(2026, 1, 29, 11, 15, 0),
                    LastFeatureName = "S-0022: Windows Tray Enhancements",
                    IsActive = true,
                    EnableLogging = true
                },
                new AgentItem
                {
                    Name = "WORKSTATION-3",
                    FriendlyName = "",
                    AgentPath = @"D:\work\felix\felix-agent.ps1",
                    ProjectFolder = @"D:\work\roboza\felix",
                    Status = "Error",
                    LastRun = new DateTime(2026, 1, 28, 15, 45, 0),
                    LastFeatureName = "S-0021: Agent Orchestration",
                    IsActive = false,
                    EnableLogging = false
                }
            };
        }

        _agents = new ObservableCollection<AgentItem>(loadedAgents);
        _filteredAgents = new ObservableCollection<AgentItem>(_agents);
    }

    partial void OnSearchTextChanged(string value)
    {
        FilterAgents();
    }

    private void FilterAgents()
    {
        if (string.IsNullOrWhiteSpace(SearchText))
        {
            FilteredAgents = new ObservableCollection<AgentItem>(Agents);
        }
        else
        {
            var filtered = Agents.Where(a => 
                a.Name.Contains(SearchText, StringComparison.OrdinalIgnoreCase) ||
                a.FriendlyName.Contains(SearchText, StringComparison.OrdinalIgnoreCase) ||
                a.LastFeatureName.Contains(SearchText, StringComparison.OrdinalIgnoreCase));
            FilteredAgents = new ObservableCollection<AgentItem>(filtered);
        }
    }

    [RelayCommand]
    private void AddAgent()
    {
        // Generate unique agent name based on machine name
        var baseName = Environment.MachineName;
        var agentName = baseName;
        var counter = 2;
        
        while (Agents.Any(a => a.Name.Equals(agentName, StringComparison.OrdinalIgnoreCase)))
        {
            agentName = $"{baseName}-{counter}";
            counter++;
        }
        
        var newAgent = new AgentItem
        {
            ProjectFolder = "",
            Name = agentName,
            FriendlyName = $"Agent {agentName}",
            AgentPath = "",
            Status = "Idle",
            LastRun = null,
            LastFeatureName = "",
            IsActive = true,
            EnableLogging = true
        };
        
        SelectedAgent = newAgent;
        ShowAgentSettings = true;
        ShowAgentsList = false;
    }

    [RelayCommand]
    private void ConfigureAgent(AgentItem agent)
    {
        SelectedAgent = agent;
        ShowAgentSettings = true;
        ShowAgentsList = false;
    }

    [RelayCommand]
    private void BrowseAgentPath()
    {
        if (SelectedAgent == null) return;

        var dialog = new OpenFileDialog
        {
            Filter = "PowerShell Scripts (*.ps1)|*.ps1|All Files (*.*)|*.*",
            Title = "Select Agent Script",
            CheckFileExists = true
        };

        if (!string.IsNullOrWhiteSpace(SelectedAgent.AgentPath))
        {
            try
            {
                dialog.InitialDirectory = System.IO.Path.GetDirectoryName(SelectedAgent.AgentPath);
            }
            catch { }
        }

        if (dialog.ShowDialog() == true)
        {
            SelectedAgent.AgentPath = dialog.FileName;
        }
    }

    [RelayCommand]
    private void SaveAgent()
    {
        if (SelectedAgent == null) return;

        // If it's a new agent, add it to the collection
        if (!Agents.Contains(SelectedAgent))
        {
            Agents.Add(SelectedAgent);
        }

        // Save to file
        _storageService.SaveAgents(Agents);

        FilterAgents();
        CancelSettings();
    }

    [RelayCommand]
    private void CancelSettings()
    {
        SelectedAgent = null;
        ShowAgentSettings = false;
        ShowAgentsList = true;
    }

    [RelayCommand]
    private void DeleteAgent()
    {
        if (SelectedAgent == null) return;

        Agents.Remove(SelectedAgent);
        
        // Save to file
        _storageService.SaveAgents(Agents);
        
        FilterAgents();
        CancelSettings();
    }

    [RelayCommand]
    private void ToggleAgentActive(AgentItem agent)
    {
        agent.IsActive = !agent.IsActive;
        
        // Save to file
        _storageService.SaveAgents(Agents);
        // Save to file
        _storageService.SaveAgents(Agents);
        
        System.Diagnostics.Debug.WriteLine($"Agent {agent.Name} is now {(agent.IsActive ? "active" : "inactive")}");
    }

    [RelayCommand]
    private void ShowRunHistory(AgentItem agent)
    {
        SelectedAgent = agent;
        LoadRunHistory(agent);
        ShowRunHistoryView = true;
        ShowAgentsList = false;
        ShowAgentSettings = false;
    }

    private void LoadRunHistory(AgentItem agent)
    {
        RunHistoryItems.Clear();
        SelectedRun = null;
        
        if (string.IsNullOrWhiteSpace(agent.ProjectFolder))
            return;

        var runsFolder = System.IO.Path.Combine(agent.ProjectFolder, "runs");
        
        if (!System.IO.Directory.Exists(runsFolder))
            return;

        try
        {
            var runDirs = System.IO.Directory.GetDirectories(runsFolder)
                .OrderByDescending(d => d);

            foreach (var runDir in runDirs)
            {
                var dirName = System.IO.Path.GetFileName(runDir);
                
                // Parse timestamp from folder name (format: 2026-01-28T09-22-23)
                if (DateTime.TryParseExact(dirName, "yyyy-MM-ddTHH-mm-ss", 
                    System.Globalization.CultureInfo.InvariantCulture, 
                    System.Globalization.DateTimeStyles.None, out var startTime))
                {
                    RunHistoryItems.Add(new RunHistoryItem
                    {
                        RunId = dirName,
                        StartTime = startTime,
                        FolderPath = runDir
                    });
                }
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error loading run history: {ex.Message}");
        }
    }

    [RelayCommand]
    private void BackToAgentsList()
    {
        SelectedAgent = null;
        SelectedRun = null;
        ShowRunHistoryView = false;
        ShowAgentSettings = false;
        ShowAgentsList = true;
    }

    partial void OnSelectedRunChanged(RunHistoryItem? value)
    {
        if (value == null)
        {
            ReportContent = string.Empty;
            OutputLogContent = string.Empty;
            PlanSnapshotContent = string.Empty;
            return;
        }

        LoadRunDetails(value);
    }

    private void LoadRunDetails(RunHistoryItem run)
    {
        try
        {
            var reportPath = System.IO.Path.Combine(run.FolderPath, "report.md");
            ReportContent = System.IO.File.Exists(reportPath) 
                ? System.IO.File.ReadAllText(reportPath) 
                : "No report found.";

            var outputPath = System.IO.Path.Combine(run.FolderPath, "output.log");
            OutputLogContent = System.IO.File.Exists(outputPath) 
                ? System.IO.File.ReadAllText(outputPath) 
                : "No output log found.";

            var planPath = System.IO.Path.Combine(run.FolderPath, "plan.snapshot.md");
            PlanSnapshotContent = System.IO.File.Exists(planPath) 
                ? System.IO.File.ReadAllText(planPath) 
                : "No plan snapshot found.";
        }
        catch (Exception ex)
        {
            ReportContent = $"Error loading report: {ex.Message}";
            OutputLogContent = $"Error loading output log: {ex.Message}";
            PlanSnapshotContent = $"Error loading plan snapshot: {ex.Message}";
        }
    }

    [RelayCommand]
    private void BrowseProjectFolder()
    {
        if (SelectedAgent == null) return;

        var dialog = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = "Select Project Folder",
            ShowNewFolderButton = true
        };

        if (!string.IsNullOrWhiteSpace(SelectedAgent.ProjectFolder))
        {
            dialog.SelectedPath = SelectedAgent.ProjectFolder;
        }

        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            SelectedAgent.ProjectFolder = dialog.SelectedPath;
        }
    }
}
