using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows.Input;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace FelixTrayApp.ViewModels;

public partial class MainViewModel : ObservableObject
{
    [ObservableProperty]
    private ObservableCollection<AgentItem> _agents;

    [ObservableProperty]
    private ObservableCollection<AgentItem> _filteredAgents;

    [ObservableProperty]
    private string _searchText = string.Empty;

    public MainViewModel()
    {
        // Initialize with sample agent data
        _agents = new ObservableCollection<AgentItem>
        {
            new AgentItem
            {
                Name = "DESKTOP-PC",
                Status = "Idle",
                LastRun = new DateTime(2026, 1, 29, 10, 30, 0),
                LastFeatureName = "S-0023: Tray Manager UI",
                IsActive = true
            },
            new AgentItem
            {
                Name = "LAPTOP-2",
                Status = "Busy",
                LastRun = new DateTime(2026, 1, 29, 11, 15, 0),
                LastFeatureName = "S-0022: Windows Tray Enhancements",
                IsActive = true
            },
            new AgentItem
            {
                Name = "WORKSTATION-3",
                Status = "Error",
                LastRun = new DateTime(2026, 1, 28, 15, 45, 0),
                LastFeatureName = "S-0021: Agent Orchestration",
                IsActive = false
            }
        };

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
                a.LastFeatureName.Contains(SearchText, StringComparison.OrdinalIgnoreCase));
            FilteredAgents = new ObservableCollection<AgentItem>(filtered);
        }
    }

    [RelayCommand]
    private void AddAgent()
    {
        var newAgent = new AgentItem
        {
            Name = $"MACHINE-{Agents.Count + 1}",
            Status = "Idle",
            LastRun = null,
            LastFeatureName = "",
            IsActive = true
        };
        Agents.Add(newAgent);
        FilterAgents();
    }

    [RelayCommand]
    private void ConfigureAgent(AgentItem agent)
    {
        // Stub: Open settings dialog for this agent
        System.Diagnostics.Debug.WriteLine($"Configure agent: {agent.Name}");
    }

    [RelayCommand]
    private void ToggleAgentActive(AgentItem agent)
    {
        agent.IsActive = !agent.IsActive;
        System.Diagnostics.Debug.WriteLine($"Agent {agent.Name} is now {(agent.IsActive ? "active" : "inactive")}");
    }

    [RelayCommand]
    private void RemoveAgent(AgentItem agent)
    {
        Agents.Remove(agent);
        FilterAgents();
    }
}
