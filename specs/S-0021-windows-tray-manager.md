# S-0021: Windows System Tray Manager

## Narrative

As a Windows user of Felix, I need a native system tray application that allows me to easily start, stop, and monitor the Felix agent process without needing to manually run PowerShell scripts or keep terminal windows open, so that I can manage Felix as a background service with quick access to common controls.

## Acceptance Criteria

### System Tray Integration

- [ ] Application runs in Windows system tray with Felix icon
- [ ] Tray icon visible in notification area (bottom-right taskbar)
- [ ] Application has no main window by default (runs minimized to tray)
- [ ] Right-click tray icon shows context menu
- [ ] Double-click tray icon shows status/about information
- [ ] Application exits cleanly when closed from tray menu

### Tray Icon States

- [ ] **Idle state**: Gray/neutral icon when Felix agent is not running
- [ ] **Running state**: Green/active icon when Felix agent is executing
- [ ] **Error state**: Red/warning icon when Felix process encounters errors
- [ ] Icon changes automatically based on process state
- [ ] Tooltip on hover shows current status (e.g., "Felix: Stopped", "Felix: Running - Iteration 5/100")

### Context Menu Options

- [ ] **Start Felix** - Launches felix-agent.ps1 with configured project path
- [ ] **Stop Felix** - Terminates running felix-agent.ps1 process
- [ ] **Settings** - Opens settings window (project path, auto-start options)
- [ ] **About** - Opens about dialog (version, description, links)
- [ ] **Exit** - Closes tray application and stops Felix if running

### Felix Process Management

- [ ] Starts PowerShell process: `powershell.exe -File ../../felix-agent.ps1 <project-path>`
- [ ] Tracks process state: Stopped, Starting, Running, Error
- [ ] Monitors process health (detects unexpected termination)
- [ ] Stops process cleanly on user request (SIGTERM/graceful shutdown)
- [ ] Handles process already running scenario (prevents duplicate instances)
- [ ] Captures process output for logging/debugging

### Status Monitoring

- [ ] Polls `..felix/state.json` every 2-3 seconds to read agent state
- [ ] Displays current requirement ID in tooltip
- [ ] Shows iteration count (current/max) in tooltip
- [ ] Updates tray icon based on state.json status field
- [ ] Handles missing or malformed state.json gracefully
- [ ] Shows last error message if process fails

### Settings Window

- [ ] **Project Path**: Folder picker to select Felix project directory
- [ ] **Auto-start on login**: Checkbox to enable Windows startup integration
- [ ] **Max iterations**: Numeric input (defaults to 100)
- [ ] **Run in background on close**: Option to minimize to tray instead of exit
- [ ] Settings saved to `app/tray-manager/settings.json`
- [ ] Settings applied immediately (no restart required where possible)
- [ ] Validate project path contains ..felix/ directory structure

### About Dialog

- [ ] Application name: "Felix Tray Manager"
- [ ] Version number (from assembly version)
- [ ] Description: "Windows system tray manager for Felix autonomous agent"
- [ ] Repository link: GitHub URL
- [ ] License information
- [ ] Credits/author information

### Logging and Error Handling

- [ ] Logs process events to `app/tray-manager/logs/TrayManager.log`
- [ ] Log entries: start/stop events, errors, state changes
- [ ] Balloon notifications for critical events:
  - Felix started successfully
  - Felix stopped unexpectedly
  - Configuration error detected
- [ ] Handle edge cases gracefully:
  - PowerShell not found in PATH
  - felix-agent.ps1 file missing
  - Invalid project path
  - State file read errors

## Technical Notes

**Technology Stack:** .NET 8.0 WPF application using C#. Uses `Hardcodet.NotifyIcon.Wpf` NuGet package for system tray functionality.

**Project Structure:**
```
app/tray-manager/
  FelixTrayManager.csproj    # .NET 8 WPF project
  Program.cs                 # Entry point
  App.xaml / App.xaml.cs     # WPF application
  TrayIconManager.cs         # Tray icon and menu management
  FelixProcessManager.cs     # PowerShell process lifecycle
  Models/
    AppSettings.cs           # Settings data model
    FelixState.cs            # State.json deserialization model
  Views/
    SettingsWindow.xaml      # Settings UI
    AboutWindow.xaml         # About dialog
  Resources/
    felix-idle.ico           # Gray icon
    felix-running.ico        # Green icon
    felix-error.ico          # Red icon
  settings.json              # User settings (generated)
  logs/
    TrayManager.log          # Application logs
```

**Process Management:** Use `System.Diagnostics.Process` to spawn and monitor PowerShell. Track PID, monitor for exit, capture stdout/stderr for logging.

**State Monitoring:** Use `System.IO.FileSystemWatcher` or timer-based polling of `..felix/state.json`. Deserialize JSON to `FelixState` model and update tray icon accordingly.

**Settings Persistence:** Serialize `AppSettings` to JSON using `Newtonsoft.Json` or `System.Text.Json`. Store in user-writable location alongside executable.

**Auto-start Integration:** Write registry key to `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run` or create shortcut in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`.

**Communication:** This is a **standalone process controller**—it does NOT host the backend or frontend. It simply manages the felix-agent.ps1 process. Users can optionally open the web UI (http://localhost:3000) separately.

## Validation Criteria

- [ ] Application builds successfully: `dotnet build app/tray-manager/FelixTrayManager.csproj` (exit code 0)
- [ ] Application starts and appears in tray: Launch executable, verify icon in notification area
- [ ] Start Felix from menu: Right-click → Start Felix, verify PowerShell process spawned
- [ ] Stop Felix from menu: Right-click → Stop Felix while running, verify process terminated
- [ ] Settings window opens: Right-click → Settings, verify window displays
- [ ] Settings persist: Change project path, save, restart app, verify path retained
- [ ] About dialog opens: Right-click → About, verify dialog displays version info
- [ ] Icon changes state: Start Felix, verify icon changes from gray to green
- [ ] Tooltip shows status: Hover over icon while running, verify shows "Running" status
- [ ] Process monitoring works: Kill felix-agent.ps1 externally, verify tray app detects and shows error state

## Dependencies

- S-0001 (Felix Agent Executor) - felix-agent.ps1 must exist to be launched
- Windows 10 or later with .NET 8 Runtime installed

## Non-Goals

- macOS or Linux support (Windows-only tray application)
- Hosting the Python backend server within this app
- Embedding the React frontend (use browser separately)
- Multi-project management (single project focus for simplicity)
- Real-time log streaming UI (use separate log viewer)
- Advanced process management (restart policies, health checks beyond basic monitoring)


