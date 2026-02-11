# S-0023: Tray Manager UI Modernization and Multi-Agent Dashboard

## Overview

Transform the Felix Tray Manager from a simple background tray application into a modern, dashboard-first multi-agent management interface with dual-theme support, Windows toast notifications, and Material Design aesthetics.

## Motivation

The current Felix Tray Manager has several limitations:
- Single-agent architecture (can only run one Felix instance at a time)
- Basic Windows Forms-style UI without modern styling
- Agent management buried in settings dialog
- No visual feedback for agent status changes
- No theme support (light/dark mode)
- Limited window state persistence

This redesign addresses these issues by creating a professional, user-friendly interface that supports managing multiple concurrent Felix agents with modern UX patterns.

## Requirements

### Multi-Agent Architecture

- Replace `FelixProcessManager` with `MultiAgentProcessManager` supporting concurrent agent execution
- Track multiple agent processes via `Dictionary<string, AgentProcessInfo>` keyed by AgentId
- Support configurable concurrent agent limit (default: 3 agents)
- Emit `AgentStateChanged` events with agent ID for targeted UI updates
- Provide `StartAgentAsync(AgentConfig)`, `StopAgentAsync(string agentId)`, `GetAgentStatus(string agentId)` methods

### Agent Dashboard Window

- Create new `AgentDashboard` as primary application window (900×650px)
- Display all configured agents in a modern DataGrid with columns:
  - Status icon (Material Design icons: Computer/CloudCheck/AlertCircle)
  - Display Name
  - Name (unique identifier)
  - Project Path
  - Auto-start badge indicator
  - Individual action buttons per row (Start/Stop/Edit/Remove)
- Toolbar with Add Agent, Refresh, View Logs, Settings, Theme Toggle buttons
- Status filter dropdown (All/Running/Stopped/Error)
- Concurrent agent limit indicator ("2/3 running")
- Real-time status updates via event subscription
- Window position and size persistence across sessions

### Multi-Agent Log Viewer

- Create `MultiAgentLogViewer` window with tabbed interface (800×600px)
- One tab per running agent with tab header showing agent name, status icon, and close button
- Each tab displays real-time console output from the agent process
- Auto-add tab when agent starts, auto-remove when agent stops
- Per-tab Clear and Copy buttons
- Custom title bar with theme support

### Dual-Theme System

- Create `DarkTheme.xaml` with dark blue gradient palette:
  - Background gradients: `#1a2332` → `#2d4a6f`
  - Text colors: `#E0E0E0` (primary), `#A0A0A0` (secondary)
  - Accent blue: `#007ACC`
  - Success green: `#4CAF50`
  - Error red: `#F44336`
- Create `LightTheme.xaml` with light blue gradient palette:
  - Background gradients: white → `#e3f2fd`
  - Text colors: `#212121` (primary), `#757575` (secondary)
  - Same accent colors as dark theme
- Implement `ThemeManager` service with:
  - System theme detection via Windows Registry (`HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme`)
  - Theme modes: System (auto-detect), Dark (manual), Light (manual)
  - Registry change listener for auto-update when system theme changes
  - Theme persistence to AppSettings
  - Frozen gradient brushes for performance
- Create `ThemeTransitionOverlay` control with fade-to-black transition (300ms total: 150ms fade-in, switch, 150ms fade-out)
- Add theme selection UI in Settings window with RadioButton group and Material icons

### Custom Title Bars

- Implement custom window chrome using `WindowChrome` for all windows
- Material Design icon buttons for window controls (minimize/maximize/close)
- Theme-aware title bar gradient matching window background
- Windows 11 rounded corner detection (`Environment.OSVersion.Version >= 10.0.22000`) with `WindowCornerPreference="RoundedSmall"`
- Drag functionality for window repositioning

### Material Design Integration

- Add `MaterialDesignThemes` NuGet package to project
- Create `MaterialIcons.cs` constants file mapping semantic names to Material icon kinds:
  - `AgentRunningIcon`, `AgentStoppedIcon`, `AgentErrorIcon`
  - `ProjectFolderIcon`, `SettingsIcon`, `ThemeIcon`
  - `WindowCloseIcon`, `WindowMinimizeIcon`, `WindowMaximizeIcon`
  - `FolderOpenIcon`, `FilePowerShellIcon`, `AlertCircleIcon`
- Use vector-based Material icons throughout for high-DPI support

### Shared Styles and Animations

- Create `Styles.xaml` resource dictionary with:
  - `ButtonStyle` with CornerRadius="6", gradient hover effects, subtle shadow
  - `TextBoxStyle` with dark background, light text, focus glow animation
  - `DataGridStyle` with transparent rows, hover highlight, custom header gradient
  - `CheckBoxStyle` with custom checkmark and accent color
  - `SeparatorStyle` with 1px gradient line
  - All styles use `{DynamicResource}` for theme switching support
- Create `Animations.xaml` with reusable Storyboards:
  - `FadeIn` (0 → 1 opacity, 200ms)
  - `SlideIn` (translate transform, 300ms)
  - `ButtonPress` (scale to 0.98x on MouseDown)
  - `CrossFade` (theme transition, 400ms)
- Apply `RenderOptions.BitmapScalingMode="HighQuality"` for hardware acceleration
- Apply `UseLayoutRounding="True"` for crisp rendering on high-DPI displays

### Windows Toast Notifications

- Create `NotificationService` using `Windows.UI.Notifications.ToastNotificationManager`
- Show notifications for:
  - Agent started (success icon with agent display name)
  - Agent stopped (info icon with agent display name)
  - Agent error (error icon with error message)
- Notifications clickable to open/focus dashboard window
- Optional notification settings toggle in Settings window

### Agent Auto-Start

- Add `AutoStart` boolean property to `AgentConfig` model
- Add AutoStart checkbox to `AgentEditDialog`
- On application startup, auto-start all agents where `AutoStart == true`
- Respect `MaxConcurrentAgents` limit during auto-start
- Show toast notifications for auto-started agents

### Simplified Tray Behavior

- Remove Start/Stop menu items from system tray context menu
- Tray icon click opens/focuses AgentDashboard window (singleton pattern)
- Context menu shows only: Settings, About, Exit
- Tray icon color reflects aggregate system status:
  - Idle (gray) if all agents stopped
  - Running (green) if any agent running
  - Error (red) if any agent in error state
- Keep existing tray icons unchanged (no theme adaptation)

### Restructured Settings Window

- Remove Agent Management section entirely (moved to dashboard)
- Keep sections:
  - Server Configuration (backend endpoint, connection test)
  - Appearance (theme selection: System/Dark/Light with icons)
  - General Settings (Max Concurrent Agents spinner, minimize to tray, start with Windows)
- Reduce window size to 500×450px
- Apply custom title bar and theme support
- Add notification settings toggle

### Model Updates

- Add to `AgentConfig.cs`:
  - `AutoStart` (bool, default: false)
  - JSON serialization support
- Add to `AppSettings.cs`:
  - `MaxConcurrentAgents` (int, default: 3)
  - `ThemeMode` (enum: System/Dark/Light, default: System)
  - `DashboardWindowLeft`, `DashboardWindowTop`, `DashboardWindowWidth`, `DashboardWindowHeight` (window persistence)
  - `EnableNotifications` (bool, default: true)

### Application Startup

- Initialize services in order: ThemeManager, MultiAgentProcessManager, NotificationService
- Apply theme before showing any windows
- Show AgentDashboard as main window (not hidden)
- Restore saved window position/size from AppSettings
- Auto-start agents with `AutoStart == true` respecting concurrent limit
- Update tray icon based on aggregate status
- Minimize to tray if configured in settings

## Acceptance Criteria

### Multi-Agent Support
- [ ] Multiple agents can run concurrently (up to MaxConcurrentAgents limit)
- [ ] Each agent tracked independently with unique process ID
- [ ] Starting agent beyond limit shows warning dialog
- [ ] Agent status updates in real-time in dashboard DataGrid
- [ ] Individual Start/Stop controls work correctly per agent

### Dashboard UI
- [ ] AgentDashboard opens on application startup
- [ ] AgentDashboard opens/focuses when clicking tray icon
- [ ] DataGrid shows all configured agents with correct status icons
- [ ] Add/Edit/Remove agent operations work from dashboard
- [ ] Auto-start badge displays for agents with AutoStart enabled
- [ ] Concurrent limit indicator shows current/max running agents
- [ ] Window position and size persist across application restarts

### Theme System
- [ ] Dark theme applies correctly with gradient backgrounds
- [ ] Light theme applies correctly with gradient backgrounds
- [ ] System theme mode auto-detects Windows theme on startup
- [ ] System theme mode updates when Windows theme changes
- [ ] Theme selection in Settings shows System/Dark/Light options
- [ ] Theme transition overlay provides smooth 300ms fade effect
- [ ] All windows update theme when selection changes
- [ ] Theme preference persists to AppSettings

### Custom Title Bars
- [ ] All windows have custom title bars with theme-aware gradient
- [ ] Window control buttons (minimize/maximize/close) use Material icons
- [ ] Title bars support drag functionality for window movement
- [ ] Windows 11 rounded corners apply on Windows 11+ systems
- [ ] Title bar colors match window theme correctly

### Log Viewer
- [ ] MultiAgentLogViewer opens from dashboard "View Logs" button
- [ ] Tab automatically added when agent starts
- [ ] Tab shows real-time console output from agent process
- [ ] Tab automatically removed when agent stops
- [ ] Tab close button stops output stream but keeps tab history
- [ ] Clear and Copy buttons work per-tab

### Notifications
- [ ] Toast notification shows when agent starts
- [ ] Toast notification shows when agent stops
- [ ] Toast notification shows when agent errors with error message
- [ ] Clicking notification opens/focuses dashboard window
- [ ] Notifications can be disabled via Settings toggle

### Auto-Start
- [ ] Agents with AutoStart enabled start automatically on app launch
- [ ] Auto-start respects MaxConcurrentAgents limit
- [ ] Auto-start shows toast notifications for each started agent
- [ ] Auto-start failures show error toast notifications

### Tray Behavior
- [ ] Tray context menu shows Settings/About/Exit only
- [ ] Start/Stop removed from tray menu
- [ ] Clicking tray icon opens/focuses dashboard
- [ ] Tray icon color reflects aggregate status (idle/running/error)
- [ ] Application continues running when dashboard closed (minimize to tray)

### Settings Window
- [ ] Agent management section removed
- [ ] Max Concurrent Agents spinner works (range 1-10)
- [ ] Theme selection with icons works correctly
- [ ] Notification toggle enables/disables toast notifications
- [ ] Window has custom title bar and theme support

### Styling and Polish
- [ ] All buttons have rounded corners and hover effects
- [ ] DataGrid has transparent rows with hover highlight
- [ ] Scrollbars styled to match theme
- [ ] Drop shadows applied to elevated surfaces
- [ ] Animations smooth (no jank or flicker)
- [ ] High-DPI displays render crisp text and icons
- [ ] All Material icons display correctly

## Technical Considerations

### Performance Optimization
- Use frozen gradient brushes (`Freeze()`) to reduce memory allocations
- Enable hardware acceleration with `RenderOptions.BitmapScalingMode="HighQuality"`
- Cache Material icon geometries to avoid repeated lookups
- Debounce theme changes to prevent rapid switching overhead

### Accessibility
- Ensure WCAG AA contrast compliance for both themes
- Support keyboard navigation for all interactive elements
- Screen reader support for status updates and notifications
- High contrast mode detection and override

### Error Handling
- Graceful degradation if MaterialDesignThemes fails to load
- Fallback to default theme if theme files missing
- Handle concurrent agent limit edge cases (e.g., agent crashes)
- Validate window position/size on restore (handle multi-monitor changes)

### Backward Compatibility
- Support reading old settings format without AutoStart property
- Migrate from single-agent to multi-agent format on first launch
- Preserve existing agent configurations during upgrade

## Dependencies

- S-0021: Windows System Tray Manager (base implementation)
- S-0022: Windows Tray Remote Agent Management (agent configuration model)

## Related Specifications

- S-0009: Light Theme (inspiration for dual-theme approach)
- S-0007: Settings Screen (settings window restructure)

## Implementation Notes

### Phase 1: Foundation (Models and Services)
1. Update models (AgentConfig, AppSettings)
2. Create MultiAgentProcessManager
3. Create ThemeManager
4. Create NotificationService

### Phase 2: Theme Resources
1. Create DarkTheme.xaml and LightTheme.xaml
2. Create Styles.xaml with control styles
3. Create Animations.xaml with storyboards
4. Create MaterialIcons.cs constants
5. Create ThemeTransitionOverlay control

### Phase 3: Windows
1. Create AgentDashboard window
2. Create MultiAgentLogViewer window
3. Update AgentEditDialog with AutoStart
4. Update SettingsWindow (remove agent management, add appearance)
5. Update AboutWindow with custom title bar

### Phase 4: Integration
1. Update App.xaml.cs startup logic
2. Wire dashboard to MultiAgentProcessManager
3. Wire log viewer to process output streams
4. Wire notifications to agent state changes
5. Implement tray icon click behavior

### Phase 5: Polish
1. Add animations to all interactive elements
2. Test theme switching across all windows
3. Test multi-agent concurrent execution
4. Test window persistence and restoration
5. Test auto-start functionality
6. Validate high-DPI rendering

## Open Questions

1. Should we add agent grouping/filtering by project in future iterations?
2. Should notification settings be per-agent or global only?
3. Should we support custom color themes beyond Dark/Light in the future?

