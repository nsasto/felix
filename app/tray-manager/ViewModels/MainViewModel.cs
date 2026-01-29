using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows.Input;
using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using FelixTrayApp.Services;

namespace FelixTrayApp.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private readonly AgentStorageService _storageService;
    private readonly DispatcherTimer _connectionCheckTimer;

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
    private bool _showGlobalSettings = false;

    [ObservableProperty]
    private AgentItem? _selectedAgent;

    [ObservableProperty]
    private bool _showRunHistoryView = false;

    [ObservableProperty]
    private ObservableCollection<RunHistoryItem> _runHistoryItems = new();

    [ObservableProperty]
    private RunHistoryItem? _selectedRun;

    [ObservableProperty]
    private string _planContent = string.Empty;

    [ObservableProperty]
    private string _outputContent = string.Empty;

    [ObservableProperty]
    private string _reportContent = string.Empty;

    [ObservableProperty]
    private double _runHistorySplitterPosition = 300;

    [ObservableProperty]
    private string _selectedTheme = "Dark";

    [ObservableProperty]
    private bool _isLightTheme = false;

    [ObservableProperty]
    private bool _isDarkTheme = true;

    [ObservableProperty]
    private bool _isSystemTheme = false;

    partial void OnSelectedThemeChanged(string value)
    {
        ApplyTheme(value);
    }

    public MainViewModel()
    {
        _storageService = new AgentStorageService();
        
        // Load window settings including splitter position and theme
        var windowSettingsService = new WindowSettingsService();
        var settings = windowSettingsService.LoadSettings();
        RunHistorySplitterPosition = settings.RunHistorySplitterPosition;
        
        // Apply saved theme
        SelectedTheme = settings.Theme;
        IsLightTheme = settings.Theme == "Light";
        IsDarkTheme = settings.Theme == "Dark";
        IsSystemTheme = settings.Theme == "System";
        ApplyTheme(settings.Theme);
        
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
        
        // Update run info for all agents from their /runs folders
        foreach (var agent in _agents)
        {
            UpdateAgentRunInfo(agent);
        }
        
        // Setup periodic connection checking
        _connectionCheckTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(10)
        };
        _connectionCheckTimer.Tick += async (s, e) => await CheckAllConnectionsAsync();
        _connectionCheckTimer.Start();
        
        // Initial connection check
        _ = CheckAllConnectionsAsync();
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
        
        System.Diagnostics.Debug.WriteLine($"Agent {agent.Name} is now {(agent.IsActive ? "active" : "inactive")}");
    }

    [RelayCommand]
    private async void TestConnection()
    {
        if (SelectedAgent == null) return;

        var trayService = ((App)System.Windows.Application.Current).TrayService;

        try
        {
            using var httpClient = new System.Net.Http.HttpClient();
            httpClient.Timeout = TimeSpan.FromSeconds(5);
            
            var response = await httpClient.GetAsync(SelectedAgent.ServerAddress + "/health");
            SelectedAgent.IsConnected = response.IsSuccessStatusCode;
            
            if (response.IsSuccessStatusCode)
            {
                trayService?.ShowNotification(
                    "Connection Test",
                    $"Connected successfully to {SelectedAgent.ServerAddress}",
                    System.Windows.Forms.ToolTipIcon.Info);
            }
            else
            {
                trayService?.ShowNotification(
                    "Connection Test",
                    $"Server responded with status: {response.StatusCode}",
                    System.Windows.Forms.ToolTipIcon.Warning);
            }
        }
        catch (Exception ex)
        {
            SelectedAgent.IsConnected = false;
            trayService?.ShowNotification(
                "Connection Test",
                $"Connection failed: {ex.Message}",
                System.Windows.Forms.ToolTipIcon.Error);
        }
        
        // Save connection status
        _storageService.SaveAgents(Agents);
    }

    private async System.Threading.Tasks.Task CheckAllConnectionsAsync()
    {
        foreach (var agent in Agents)
        {
            if (!agent.IsActive || string.IsNullOrWhiteSpace(agent.ServerAddress))
            {
                agent.IsConnected = false;
                continue;
            }

            try
            {
                using var httpClient = new System.Net.Http.HttpClient();
                httpClient.Timeout = TimeSpan.FromSeconds(3);
                
                var response = await httpClient.GetAsync(agent.ServerAddress + "/health");
                agent.IsConnected = response.IsSuccessStatusCode;
            }
            catch
            {
                agent.IsConnected = false;
            }
            
            // Update run info from /runs folder
            UpdateAgentRunInfo(agent);
        }
        
        // Save updated connection statuses
        _storageService.SaveAgents(Agents);
    }
    
    private void UpdateAgentRunInfo(AgentItem agent)
    {
        if (string.IsNullOrWhiteSpace(agent.ProjectFolder))
        {
            agent.LastRun = null;
            agent.LastFeatureName = "";
            return;
        }

        var runsFolder = System.IO.Path.Combine(agent.ProjectFolder, "runs");
        
        if (!System.IO.Directory.Exists(runsFolder))
        {
            agent.LastRun = null;
            agent.LastFeatureName = "";
            return;
        }

        try
        {
            var runDirs = System.IO.Directory.GetDirectories(runsFolder)
                .OrderByDescending(d => d)
                .FirstOrDefault();

            if (runDirs == null)
            {
                agent.LastRun = null;
                agent.LastFeatureName = "";
                return;
            }

            var dirName = System.IO.Path.GetFileName(runDirs);
            
            // Parse timestamp from folder name (format: 2026-01-28T09-22-23)
            if (DateTime.TryParseExact(dirName, "yyyy-MM-ddTHH-mm-ss", 
                System.Globalization.CultureInfo.InvariantCulture, 
                System.Globalization.DateTimeStyles.None, out var startTime))
            {
                agent.LastRun = startTime;
            }
            else
            {
                agent.LastRun = null;
            }

            // Try to extract feature name from plan-*.md file
            var planFiles = System.IO.Directory.GetFiles(runDirs, "plan-*.md");
            string featureName = "";
            
            if (planFiles.Length > 0)
            {
                // Extract plan ID from filename (e.g., plan-S-0021.md -> S-0021)
                var planFileName = System.IO.Path.GetFileNameWithoutExtension(planFiles[0]);
                var planId = planFileName.Replace("plan-", "");
                
                // Read first line to get the full plan name
                var firstLine = System.IO.File.ReadLines(planFiles[0]).FirstOrDefault() ?? "";
                var planName = firstLine.Replace("# Implementation Plan:", "").Trim();
                
                // Combine ID and name
                featureName = string.IsNullOrWhiteSpace(planName) ? planId : planName;
            }
            else
            {
                // Fallback: Try report.md
                var reportPath = System.IO.Path.Combine(runDirs, "report.md");
                if (System.IO.File.Exists(reportPath))
                {
                    var reportLines = System.IO.File.ReadLines(reportPath).Take(10);
                    foreach (var line in reportLines)
                    {
                        // Look for requirement ID pattern (S-XXXX)
                        if (line.Contains("S-", StringComparison.OrdinalIgnoreCase))
                        {
                            var match = System.Text.RegularExpressions.Regex.Match(line, @"S-\d+[^\n]*");
                            if (match.Success)
                            {
                                featureName = match.Value.Trim();
                                break;
                            }
                        }
                    }
                }
            }
            
            agent.LastFeatureName = featureName;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error updating agent run info: {ex.Message}");
            agent.LastRun = null;
            agent.LastFeatureName = "";
        }
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
        ShowGlobalSettings = false;
        ShowAgentsList = true;
    }

    [RelayCommand]
    private void ShowGlobalSettingsView()
    {
        ShowGlobalSettings = true;
        ShowAgentsList = false;
        ShowAgentSettings = false;
        ShowRunHistoryView = false;
    }

    [RelayCommand]
    private void ApplyTheme(string theme)
    {
        SelectedTheme = theme;
        IsLightTheme = theme == "Light";
        IsDarkTheme = theme == "Dark";
        IsSystemTheme = theme == "System";

        // Save theme preference
        var windowSettingsService = new WindowSettingsService();
        var settings = windowSettingsService.LoadSettings();
        settings.Theme = theme;
        windowSettingsService.SaveSettings(settings);

        // Swap theme resource dictionaries
        SwapThemeResourceDictionary(theme);
        
        // Apply WPF-UI theme for controls
        Wpf.Ui.Appearance.ApplicationTheme wpfUiTheme;
        
        if (theme == "System")
        {
            var systemTheme = Wpf.Ui.Appearance.ApplicationThemeManager.GetSystemTheme();
            wpfUiTheme = systemTheme == Wpf.Ui.Appearance.SystemTheme.Light 
                ? Wpf.Ui.Appearance.ApplicationTheme.Light 
                : Wpf.Ui.Appearance.ApplicationTheme.Dark;
        }
        else
        {
            wpfUiTheme = theme == "Light" 
                ? Wpf.Ui.Appearance.ApplicationTheme.Light 
                : Wpf.Ui.Appearance.ApplicationTheme.Dark;
        }
        
        Wpf.Ui.Appearance.ApplicationThemeManager.Apply(wpfUiTheme);
    }
    
    private void SwapThemeResourceDictionary(string theme)
    {
        var dictionaries = System.Windows.Application.Current.Resources.MergedDictionaries;
        
        // Remove old theme dictionary
        var oldTheme = dictionaries.FirstOrDefault(d => 
            d.Source?.OriginalString.Contains("/Themes/") == true);
        if (oldTheme != null)
        {
            dictionaries.Remove(oldTheme);
        }
        
        // Determine which theme to load
        var themeFile = theme == "Light" ? "LightTheme.xaml" : "DarkTheme.xaml";
        
        // Add new theme dictionary
        var themeUri = new Uri($"pack://application:,,,/Themes/{themeFile}", UriKind.Absolute);
        var newTheme = new System.Windows.ResourceDictionary { Source = themeUri };
        dictionaries.Add(newTheme);
    }

    partial void OnSelectedRunChanged(RunHistoryItem? value)
    {
        if (value == null)
        {
            PlanContent = string.Empty;
            OutputContent = string.Empty;
            ReportContent = string.Empty;
            return;
        }

        LoadRunDetails(value);
    }

    private void LoadRunDetails(RunHistoryItem run)
    {
        try
        {
            // Find plan file (plan-*.md)
            var planFiles = System.IO.Directory.GetFiles(run.FolderPath, "plan-*.md");
            if (planFiles.Length > 0)
            {
                var planContent = System.IO.File.ReadAllText(planFiles[0]);
                var planFileName = System.IO.Path.GetFileNameWithoutExtension(planFiles[0]);
                var planId = planFileName.Replace("plan-", "");
                
                // Extract plan name from first line (after "# Implementation Plan:")
                var firstLine = planContent.Split('\n').FirstOrDefault() ?? "";
                var planName = firstLine.Replace("# Implementation Plan:", "").Trim();
                
                // Add header with plan ID and name
                //PlanContent = $"# Plan: {planId}\n## {planName}\n\n{planContent}";
                PlanContent = planContent;
            }
            else
            {
                PlanContent = "No plan found.";
            }

            var outputPath = System.IO.Path.Combine(run.FolderPath, "output.log");
            OutputContent = System.IO.File.Exists(outputPath) 
                ? System.IO.File.ReadAllText(outputPath) 
                : "No output log found.";

            var reportPath = System.IO.Path.Combine(run.FolderPath, "report.md");
            ReportContent = System.IO.File.Exists(reportPath) 
                ? System.IO.File.ReadAllText(reportPath) 
                : "No report found.";
        }
        catch (Exception ex)
        {
            PlanContent = $"Error loading plan: {ex.Message}";
            OutputContent = $"Error loading output: {ex.Message}";
            ReportContent = $"Error loading report: {ex.Message}";
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
