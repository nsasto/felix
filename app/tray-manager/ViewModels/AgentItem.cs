using System;
using CommunityToolkit.Mvvm.ComponentModel;

namespace FelixTrayApp.ViewModels;

public partial class AgentItem : ObservableObject
{
    [ObservableProperty]
    private string _name = string.Empty;

    [ObservableProperty]
    private string _friendlyName = string.Empty;

    [ObservableProperty]
    private string _agentPath = string.Empty;

    [ObservableProperty]
    private string _projectFolder = string.Empty;

    [ObservableProperty]
    private string _serverAddress = "http://localhost:8080";

    [ObservableProperty]
    private bool _isConnected = false;

    [ObservableProperty]
    private string _status = "Idle"; // Idle, Busy, Error

    [ObservableProperty]
    private DateTime? _lastRun;

    [ObservableProperty]
    private string _lastFeatureName = string.Empty;

    [ObservableProperty]
    private bool _isActive = true;

    [ObservableProperty]
    private bool _enableLogging = true;

    public string LastRunFormatted => LastRun?.ToString("MMM d, yyyy HH:mm") ?? "Never";
    
    public string DisplayName => string.IsNullOrWhiteSpace(FriendlyName) ? Name : FriendlyName;
    
    public string DisplayStatus => IsActive ? Status : "Disabled";

    partial void OnIsActiveChanged(bool value)
    {
        OnPropertyChanged(nameof(DisplayStatus));
    }

    partial void OnStatusChanged(string value)
    {
        OnPropertyChanged(nameof(DisplayStatus));
    }
}
