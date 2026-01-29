using System;
using CommunityToolkit.Mvvm.ComponentModel;

namespace FelixTrayApp.ViewModels;

public partial class TransferItem : ObservableObject
{
    [ObservableProperty]
    private string _name = string.Empty;

    [ObservableProperty]
    private string _size = string.Empty;

    [ObservableProperty]
    private DateTime _lastModified;

    [ObservableProperty]
    private string _status = string.Empty;

    [ObservableProperty]
    private double _progress;
}
