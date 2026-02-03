# Slack Notifier Plugin

Sends Slack notifications for key Felix events.

## Configuration

Add your Slack webhook URL to `..felix/config.json`:

```json
{
  "plugins": {
    "enabled": true
  }
}
```

Then configure the plugin by editing `plugin.json`:

```json
{
  "config": {
    "webhook_url": "https://hooks.slack.com/services/YOUR/WEBHOOK/URL",
    "notify_on_success": true,
    "notify_on_failure": true
  }
}
```

## Hooks Implemented

### OnPostLLM
Sends notification after each LLM execution with status (success/failure).

### OnBackpressureFailed
Sends alert when backpressure validation fails, including failed commands.

### OnPostValidation
Sends notification when requirement validation completes (passed/failed).

## Testing

```powershell
cd ..felix/plugins
.\test-harness.ps1 -PluginPath .\slack-notifier -RunAll
```

## Permissions Required

- `read:state` - Read Felix state and requirement information
- `network:http` - Make HTTP requests to Slack webhook

## Example Notifications

**LLM Execution:**
> ✅ Felix Agent - LLM Execution Complete
> Requirement: S-0001 - Backend API Server
> Mode: BUILDING | Status: ✅ Success

**Backpressure Failure:**
> 🚨 Felix - Backpressure Validation Failed
> Requirement: S-0001 - Backend API Server
> Failed Commands: [test] `npm test` (exit: 1)

**Validation Complete:**
> ✅ Felix - Requirement Validation Complete
> Requirement: S-0001 - Backend API Server
> Result: PASSED


