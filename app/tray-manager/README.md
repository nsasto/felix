# FelixTrayApp

A modern .NET 8 WPF tray application with Fluent Design and Mica backdrop for managing Felix agents.

## Features

- System tray application with context menu
- Modern Fluent UI with Mica/Acrylic backdrop
- Rounded corners and custom window chrome
- Left navigation panel (Agents, Logs, Settings)
- Multi-agent management dashboard
- Dark theme by default
- High-DPI aware

## Agent Management

- View all configured agents in a modern DataGrid
- Columns: Name, Status (Idle/Busy/Error), Last Run, Last Feature Name, Operations
- Add new agents with the "Add Agent" button
- Configure agent settings (Settings button per row)
- Toggle agent active/inactive status
- Remove agents with delete button
- Search/filter agents by name or feature
- Real-time status indicators with icons

## Build and Run

### Prerequisites

- .NET 8 SDK
- Windows 10 version 22621 or later (for Mica backdrop)

### Build

```powershell
cd app/tray-manager
dotnet restore
dotnet build
```

### Run

```powershell
dotnet run
```

Or run the executable directly:

```powershell
.\bin\Debug\net8.0-windows10.0.22621.0\FelixTrayApp.exe
```

## Usage

1. App starts in system tray (look for the icon in the taskbar notification area)
2. Right-click the tray icon or double-click to open the main window
3. Click "Transfer" to add items (stub implementation)
4. Use search box to filter transfer history
5. Use Copy/Delete buttons on individual items
6. Minimizing or closing the window hides it to tray
7. Use "Exit" from tray menu to fully quit the application

## Architecture

- **App.xaml/cs**: Application entry point, manages tray-only startup
- **Services/TrayService.cs**: System tray icon and context menu management
- **Views/MainWindow.xaml**: Main window with Fluent design
- **ViewModels/MainViewModel.cs**: Main window data and commands
- **ViewModels/TransferItem.cs**: Transfer item model

## NuGet Packages

- WPF-UI: Fluent window, Mica backdrop, modern controls
- CommunityToolkit.Mvvm: MVVM helpers (ObservableObject, RelayCommand)
