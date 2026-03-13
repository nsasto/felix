# Writing Felix Plugins

Plugins extend Felix's behavior through **lifecycle hooks**  PowerShell scripts that run at specific points during each agent iteration.

## Quick Start

Create a plugin in 3 steps:

### 1. Create the plugin directory

```
.felix/plugins/my-plugin/
  plugin.json
  on-postllm.ps1
```

### 2. Write the manifest (`plugin.json`)

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "api_version": "v1",
  "description": "Does something useful after each LLM call",
  "author": "Your Name",
  "permissions": ["read:state", "write:logs"],
  "hooks": [
    { "name": "OnPostLLM", "type": "powershell", "script": "on-postllm.ps1" }
  ],
  "priority": 100,
  "config": {
    "my_setting": "default_value"
  }
}
```

### 3. Write the hook script (`on-postllm.ps1`)

```powershell
param(
    [string]$HookName,
    [string]$RunId,
    [hashtable]$Data,
    [hashtable]$Config
)

# $Data contains hook-specific parameters (see Hook Reference below)
# $Config contains your plugin.json config values

Write-Host "[my-plugin] LLM finished with exit code $($Data.ExitCode)"

# Return a result hashtable (optional - controls agent behavior)
return @{
    Success = $true
    Metadata = @{ logged = $true }
}
```

That's it. Felix discovers and loads plugins automatically on startup.

## Plugin Structure

```
.felix/plugins/
  my-plugin/
    plugin.json              # Required - manifest
    on-prediteration.ps1     # Hook script (one per hook, v1 naming)
    on-postllm.ps1           # Another hook script
    persistent-state.json    # Auto-managed persistent state
    README.md                # Optional documentation
    tests/                   # Optional tests
```

### Naming conventions

- **v1 API**: Hook scripts named `on-{hookname}.ps1` (lowercase). Example: `on-prediteration.ps1`
- **v2 API**: Hook scripts in `hooks/{HookName}.ps1` subdirectory. Example: `hooks/OnPreIteration.ps1`

Set `api_version` in your `plugin.json` to `"v1"` or `"v2"`.

## Manifest Reference

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique identifier (lowercase, hyphens only: `^[a-z0-9-]+$`) |
| `name` | Yes | Human-readable name |
| `version` | Yes | Semver version (`1.0.0`) |
| `api_version` | Yes | `"v1"` or `"v2"` |
| `description` | No | What the plugin does |
| `author` | No | Author name |
| `permissions` | No | Required permissions (see below) |
| `hooks` | Yes | Array of hook declarations |
| `requires` | No | Plugin dependencies (other plugin IDs) |
| `priority` | No | Execution order (0-999, lower = earlier, default: 100) |
| `felix_version_min` | No | Minimum Felix version |
| `felix_version_max` | No | Maximum Felix version |
| `config` | No | Plugin-specific settings (any JSON object) |

### Permissions

Declare what your plugin needs access to:

| Permission | Description |
|-----------|-------------|
| `read:specs` | Read spec/requirement files |
| `read:state` | Read agent state |
| `read:runs` | Read run artifacts |
| `write:runs` | Write to run directories |
| `write:logs` | Write log files |
| `execute:commands` | Run shell commands |
| `network:http` | Make HTTP requests |
| `git:read` | Read git history/status |
| `git:write` | Create commits, modify working tree |

## Hook Reference

Hooks fire at specific points in the agent iteration. Your script receives four parameters:

```powershell
param(
    [string]$HookName,     # The hook being invoked
    [string]$RunId,        # Current run ID
    [hashtable]$Data,      # Hook-specific data (see table)
    [hashtable]$Config     # Your plugin.json config values
)
```

### Lifecycle hooks

| Hook | When it fires | `$Data` contents | Return controls |
|------|--------------|-----------------|-----------------|
| **OnPreIteration** | Before each iteration starts | `Iteration`, `MaxIterations`, `CurrentRequirement`, `State` | `ContinueIteration` (bool) - set `$false` to cancel |
| **OnPostModeSelection** | After planning/building mode determined | `Mode`, `CurrentRequirement`, `PlanPath` | `OverrideMode` - change to `"planning"` or `"building"` |
| **OnContextGathering** | During context assembly | `Mode`, `CurrentRequirement`, `GitDiff`, `PlanContent`, `ContextFiles` | `AdditionalFiles`, `AdditionalContext` - inject extra context |
| **OnPreLLM** | Before LLM execution | `Mode`, `CurrentRequirement`, `PromptFile`, `FullPrompt` | `ModifiedPrompt`, `SkipLLM` (bool) |
| **OnPostLLM** | After LLM completes | `Mode`, `CurrentRequirement`, `ExitCode`, `OutputPath` | `Success` (bool), `Metadata` |
| **OnGuardrailCheck** | Planning mode validation fails | `Mode`, `CurrentRequirement`, `GuardrailsPassed`, `FailedChecks` | `OverrideResult` (bool) |
| **OnPreBackpressure** | Before validation commands run | `CurrentRequirement`, `Commands` | `AdditionalCommands`, `SkipBackpressure` (bool) |
| **OnBackpressureFailed** | When validation fails | `CurrentRequirement`, `ValidationResult`, `RetryCount` | `ShouldRetry` (bool), `SuggestedFix` |
| **OnPreCommit** | Before git commit | `CurrentRequirement`, `CommitMessage`, `StagedFiles` | `ModifiedCommitMessage`, `SkipCommit` (bool) |
| **OnPostValidation** | After requirement validation | `CurrentRequirement`, `ValidationPassed`, `ValidationOutput` | `OverrideResult` (bool), `Metadata` |
| **OnPostIteration** | After iteration cleanup | `Iteration`, `MaxIterations`, `CurrentRequirement`, `Outcome`, `State` | `ShouldContinue` (bool), `UpdatedState` |

See `.felix/plugins/hook-contracts.ps1` for the full typed parameter and result classes.

## State Management

Plugins can persist data in two scopes:

### Persistent state (survives across runs)

Stored in `persistent-state.json` in your plugin directory.

```powershell
# Read
$state = Get-PluginPersistentState -PluginName "my-plugin"

# Write
Set-PluginPersistentState -PluginName "my-plugin" -State @{
    total_runs = ($state.total_runs ?? 0) + 1
    last_run   = Get-Date -Format "o"
}
```

### Transient state (per-run only)

Stored in the run directory as `plugin-state-{name}.json`.

```powershell
# Read
$runState = Get-PluginTransientState -PluginName "my-plugin" -RunId $RunId

# Write
Set-PluginTransientState -PluginName "my-plugin" -RunId $RunId -State @{
    iterations_completed = $Data.Iteration
    mode_changes = @()
}
```

## Configuration

Plugin config comes from two places:

1. **Default values** in your `plugin.json` `config` field
2. **User overrides** in `.felix/config.json`:

```json
{
  "plugins": {
    "enabled": true,
    "my-plugin": {
      "my_setting": "custom_value"
    }
  }
}
```

User overrides merge with plugin defaults. The merged config is passed as `$Config` to your hook scripts.

## Error Handling & Circuit Breaker

- If your hook script throws an error, Felix catches it and logs the failure.
- After **3 consecutive failures**, Felix disables your plugin for the session (circuit breaker).
- Adjust the threshold in `.felix/config.json`:

```json
{
  "plugins": {
    "circuit_breaker_max_failures": 5
  }
}
```

**Best practice**: Handle errors in your hook scripts. Don't let exceptions bubble up unless something is truly broken.

## Debugging

Check these files after a run:

| File | Location | Contents |
|------|----------|----------|
| Hook execution chain | `runs/{runId}/plugin-chain-debug.json` | Order of hook execution, inputs/outputs |
| Execution metrics | `runs/{runId}/plugin-execution.json` | Timing, success/failure per plugin |
| Plugin state | `runs/{runId}/plugin-state-{name}.json` | Your transient state |

## Example: Commit Message Enforcer

A simple plugin that prepends the requirement ID to all commit messages:

**`plugin.json`**:
```json
{
  "id": "commit-prefix",
  "name": "Commit Message Prefix",
  "version": "1.0.0",
  "api_version": "v1",
  "description": "Prepends requirement ID to commit messages",
  "permissions": ["git:write"],
  "hooks": [
    { "name": "OnPreCommit", "type": "powershell", "script": "on-precommit.ps1" }
  ],
  "priority": 50
}
```

**`on-precommit.ps1`**:
```powershell
param(
    [string]$HookName,
    [string]$RunId,
    [hashtable]$Data,
    [hashtable]$Config
)

$reqId = $Data.CurrentRequirement.id
$message = $Data.CommitMessage

if ($message -notmatch "^$reqId") {
    return @{
        ModifiedCommitMessage = "${reqId}: $message"
    }
}

return @{}
```

## Example: Slack Notifier

Posts to Slack when validation passes or fails:

**`plugin.json`**:
```json
{
  "id": "slack-notify",
  "name": "Slack Notifier",
  "version": "1.0.0",
  "api_version": "v1",
  "description": "Posts to Slack when validation passes or fails",
  "permissions": ["network:http", "read:state"],
  "hooks": [
    { "name": "OnPostValidation", "type": "powershell", "script": "on-postvalidation.ps1" }
  ],
  "priority": 200,
  "config": {
    "webhook_url": "",
    "channel": "#felix-builds"
  }
}
```

**`on-postvalidation.ps1`**:
```powershell
param(
    [string]$HookName,
    [string]$RunId,
    [hashtable]$Data,
    [hashtable]$Config
)

if (-not $Config.webhook_url) { return @{} }

$reqId = $Data.CurrentRequirement.id
$status = if ($Data.ValidationPassed) { "passed" } else { "failed" }

$body = @{
    channel = $Config.channel
    text    = "Felix: $reqId validation $status (run: $RunId)"
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri $Config.webhook_url -Method POST -Body $body -ContentType "application/json"
} catch {
    Write-Warning "[slack-notify] Failed to send: $_"
}

return @{}
```

Configure in `.felix/config.json`:
```json
{
  "plugins": {
    "slack-notify": {
      "webhook_url": "https://hooks.slack.com/services/YOUR/WEBHOOK/URL",
      "channel": "#builds"
    }
  }
}
```

## Reference Implementation

The built-in **sync-http** plugin (`.felix/plugins/sync-http/`) is a production-grade reference showing:
- Multiple hooks working together
- HTTP client with retry and outbox queuing
- Persistent state management
- Throttling and batching
- Proper error handling
