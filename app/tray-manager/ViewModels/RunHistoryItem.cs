using System;
using CommunityToolkit.Mvvm.ComponentModel;

namespace FelixTrayApp.ViewModels;

public partial class RunHistoryItem : ObservableObject
{
    [ObservableProperty]
    private string _runId = string.Empty;

    [ObservableProperty]
    private DateTime _startTime;

    [ObservableProperty]
    private string _folderPath = string.Empty;

    public string DisplayName => $"{StartTime:yyyy-MM-dd HH:mm:ss} - {RunId}";
}
