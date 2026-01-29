# S-0022: Windows Tray Manager - Remote Agent Management

## Narrative

As a Windows user of Felix, I need to configure and manage multiple remote Felix agent instances from the tray manager, so that I can control agents running on different machines or in different locations from a single interface. I also need to configure which backend server endpoint the tray manager connects to for monitoring and control.

## Acceptance Criteria

### Agent Configuration Management

- [ ] **Add Agent** button/menu option in Settings window
- [ ] Each agent configuration includes:
  - **Name**: Unique identifier (auto-generated from computer name)
  - **Display Name**: User-friendly label (editable)
  - **Agent Path**: Full path to felix-agent.ps1 script
  - **Enabled**: Boolean flag to enable/disable agent
  - **Location Type**: Local or Remote
- [ ] Default unique name format: `{ComputerName}` for first agent, `{ComputerName}-2`, `{ComputerName}-3` for additional agents
- [ ] Display name defaults to unique name but can be customized by user
- [ ] Agent path validation:
  - Verifies file exists at specified path
  - Confirms file is named `felix-agent.ps1`
  - Shows warning if path is not accessible
- [ ] Enable/disable toggle for each agent
- [ ] Remove/delete agent configuration option
- [ ] List view showing all configured agents with status indicators

### Server Endpoint Configuration

- [ ] **Server Endpoint** field in Settings window
- [ ] URL input for backend API endpoint (e.g., `http://localhost:8080`)
- [ ] Default value: `http://localhost:8080`
- [ ] **Test Connection** button next to endpoint field
- [ ] Connection test validates:
  - Server is reachable at specified URL
  - `/health` endpoint responds successfully
  - API version compatibility (if applicable)
- [ ] Visual feedback for connection test:
  - ✅ Success: "Connected to Felix backend v{version}"
  - ❌ Failed: "Cannot connect to {url}: {error_message}"
  - ⏳ Testing: "Testing connection..."
- [ ] Save endpoint configuration to `app/tray-manager/settings.json`

### Settings Data Model

- [ ] Update `settings.json` schema to include:
  ```json
  {
    "serverEndpoint": "http://localhost:8080",
    "agents": [
      {
        "id": "unique-guid",
        "name": "DESKTOP-PC",
        "displayName": "Main Development Machine",
        "agentPath": "C:\\dev\\felix\\felix-agent.ps1",
        "enabled": true,
        "locationType": "local"
      }
    ]
  }
  ```
- [ ] Maintain backward compatibility with existing settings
- [ ] Migrate existing single project path to agent configuration on first load
- [ ] Validate settings schema on load
- [ ] Save settings atomically (write to temp file, then rename)

### Settings UI Layout

- [ ] **Server Configuration** section at top of Settings window:
  - Endpoint URL text field
  - Test Connection button
  - Connection status indicator
- [ ] **Agent Management** section:
  - List/grid view of configured agents
  - Add Agent button
  - Edit/Remove buttons for each agent entry
  - Enable/Disable toggle for each agent
- [ ] **Agent Details** panel (shown when adding/editing):
  - Unique Name field (auto-generated, read-only)
  - Display Name field (editable)
  - Agent Path field with folder picker button
  - Enabled checkbox
  - Save/Cancel buttons

### Connection Testing Logic

- [ ] Test connection sends GET request to `{serverEndpoint}/health`
- [ ] Timeout after 5 seconds if no response
- [ ] Handle common error scenarios:
  - Server not running
  - Invalid URL format
  - Network unreachable
  - CORS/authentication errors
- [ ] Parse health response to extract version information
- [ ] Display result in non-blocking manner (doesn't freeze UI)
- [ ] Log connection test results to application log

### Agent Migration Strategy

- [ ] On first run with new version:
  - Check if legacy `projectPath` exists in settings
  - If yes, create default agent configuration from legacy path
  - Set agent name to computer name
  - Set display name to "Local Agent"
  - Mark agent as enabled
  - Preserve all other settings
- [ ] Show migration notification to user
- [ ] Do not break existing installations

### Error Handling

- [ ] Validate agent path is not empty before saving
- [ ] Prevent duplicate agent names
- [ ] Handle invalid endpoint URLs gracefully
- [ ] Show user-friendly error messages for:
  - Invalid agent path
  - Connection test failures
  - Settings file corruption
  - Permission denied errors
- [ ] Log all errors to `app/tray-manager/logs/TrayManager.log`

### Validation Criteria

- [ ] Application builds without errors: `dotnet build app/tray-manager/FelixTrayManager.csproj` (exit code 0)
- [ ] Settings window opens with new Server Configuration section
- [ ] Can add multiple agent configurations
- [ ] Each agent has unique name auto-generated from computer name
- [ ] Connection test successfully validates backend endpoint
- [ ] Connection test shows appropriate error when backend is down
- [ ] Settings persist correctly to settings.json
- [ ] Legacy settings migrate correctly to new agent-based format

## Technical Notes

### Implementation Considerations

1. **Settings Service Updates**:
   - Extend `SettingsManager.cs` to support new data model
   - Add agent collection management methods
   - Implement connection testing logic

2. **UI Components**:
   - Update `SettingsWindow.xaml` with new sections
   - Add agent list control (DataGrid or ListBox)
   - Create agent detail form for add/edit operations

3. **HTTP Client**:
   - Use `HttpClient` for connection testing
   - Implement async connection test to prevent UI blocking
   - Add timeout and cancellation support

4. **Backward Compatibility**:
   - Check for legacy `projectPath` field on load
   - Auto-migrate to first agent configuration
   - Preserve existing behavior for single-agent scenarios

5. **Scope Limitation**:
   - This feature only modifies the tray manager application
   - No changes to backend or frontend required
   - No changes to felix-agent.ps1 required
   - Connection testing uses existing backend `/health` endpoint

### Dependencies

- S-0021: Windows System Tray Manager (must be implemented first)
- S-0002: Backend API Server (required for connection testing)

### Future Considerations

- Remote agent execution (not in this spec)
- Agent status aggregation across multiple instances
- Centralized agent control from backend
- WebSocket integration for real-time agent updates

## Success Metrics

- Users can configure multiple agent instances
- Each agent has clear unique and display names
- Server endpoint connection can be validated before use
- Settings migration preserves existing configurations
- No breaking changes to existing tray manager functionality
