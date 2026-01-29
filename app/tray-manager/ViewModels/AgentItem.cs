using System;
using CommunityToolkit.Mvvm.ComponentModel;

namespace FelixTrayApp.ViewModels;

public partial class AgentItem : ObservableObject
{
    [ObservableProperty]
    private string _name = string.Empty;

    [ObservableProperty]
    private string _status = "Idle"; // Idle, Busy, Error

    [ObservableProperty]
    private DateTime? _lastRun;

    [ObservableProperty]
    private string _lastFeatureName = string.Empty;

    [ObservableProperty]
    private bool _isActive = true;

    public string LastRunFormatted => LastRun?.ToString("MMM d, yyyy HH:mm") ?? "Never";
}
