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
    private ObservableCollection<TransferItem> _transfers;

    [ObservableProperty]
    private ObservableCollection<TransferItem> _filteredTransfers;

    [ObservableProperty]
    private string _searchText = string.Empty;

    [ObservableProperty]
    private string _selectedDevice = "iPhone 13 Pro";

    public MainViewModel()
    {
        // Initialize with sample data
        _transfers = new ObservableCollection<TransferItem>
        {
            new TransferItem
            {
                Name = "IMG_3644819.MOV",
                Size = "175 MB",
                LastModified = new DateTime(2024, 6, 29),
                Status = "Done",
                Progress = 100
            },
            new TransferItem
            {
                Name = "IMG_3544220.MOV",
                Size = "25.4 MB",
                LastModified = new DateTime(2024, 6, 29),
                Status = "Copying",
                Progress = 19
            }
        };

        _filteredTransfers = new ObservableCollection<TransferItem>(_transfers);
    }

    partial void OnSearchTextChanged(string value)
    {
        FilterTransfers();
    }

    private void FilterTransfers()
    {
        if (string.IsNullOrWhiteSpace(SearchText))
        {
            FilteredTransfers = new ObservableCollection<TransferItem>(Transfers);
        }
        else
        {
            var filtered = Transfers.Where(t => 
                t.Name.Contains(SearchText, StringComparison.OrdinalIgnoreCase));
            FilteredTransfers = new ObservableCollection<TransferItem>(filtered);
        }
    }

    [RelayCommand]
    private void CopyItem(TransferItem item)
    {
        // Stub: Show notification or toast
        System.Diagnostics.Debug.WriteLine($"Copy: {item.Name}");
    }

    [RelayCommand]
    private void DeleteItem(TransferItem item)
    {
        Transfers.Remove(item);
        FilteredTransfers.Remove(item);
    }

    [RelayCommand]
    private void Transfer()
    {
        System.Diagnostics.Debug.WriteLine("Transfer clicked");
    }

    [RelayCommand]
    private void SendToPhone()
    {
        System.Diagnostics.Debug.WriteLine("Send to phone clicked");
    }
}
