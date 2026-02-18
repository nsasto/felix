# HTTP Sync Plugin

Synchronizes Felix agent run data to a backend server via HTTP/REST API.

## Features

- **Run Lifecycle Tracking**: Creates run records, updates status, marks completion
- **Event Batching**: Queues events and flushes every 5 seconds (heartbeat proxy)
- **Status Updates**: Throttled to max 1 per second to prevent spam
- **Artifact Upload**: Uploads run artifacts (logs, diffs, etc.) on completion
- **Error Handling**: Uses outbox queue for retry on network failures
- **Idempotent**: SHA256-based deduplication prevents duplicate uploads

## Configuration

### Required Settings (`.felix/config.json`)

```json
{
  "sync": {
    "enabled": true,
    "provider": "http",
    "base_url": "http://localhost:8080",
    "api_key": "fsk_your_api_key_here" // Optional, can use env var instead
  },
  "plugins": {
    "enabled": true
  }
}
```

### Environment Variables

Override config file values with environment variables:

- `FELIX_SYNC_ENABLED` - Enable/disable sync (true/false)
- `FELIX_SYNC_URL` - Backend URL
- `FELIX_SYNC_KEY` - API key (starts with `fsk_`)

### Plugin Configuration

Adjust plugin behavior via config:

```json
{
  "sync": {
    "enabled": true,
    "provider": "http",
    "base_url": "http://localhost:8080"
  },
  "plugins": {
    "enabled": true,
    "sync-http": {
      "event_batch_interval": 5, // Seconds between event flushes (heartbeat)
      "status_throttle_ms": 1000, // Min milliseconds between status updates
      "retry_attempts": 3 // Max retries for failed uploads
    }
  }
}
```

## Hooks

The plugin registers these lifecycle hooks:

1. **OnPreIteration** (iteration 1 only)
   - Initializes HTTP client
   - Registers agent with backend
   - Creates run record
   - Starts event flush timer (heartbeat)

2. **OnEvent** (all events)
   - Queues events for batch sending
   - Flushes immediately for critical events (errors, validation failures)

3. **OnPostModeSelection** (mode changes)
   - Updates run status when agent switches planning ↔ building modes
   - Throttled to prevent spam

4. **OnBackpressureFailed** (validation failures)
   - Queues validation_failed event
   - Forces immediate status update (bypasses throttle)

5. **OnRunComplete** (run end)
   - Flushes remaining events
   - Marks run finished with final status
   - Uploads artifacts from runs/ directory
   - Stops flush timer

## How It Works

### Event Flow

```
1. Agent emits event via Emit-Event → OnEvent hook triggered
2. Event added to in-memory queue
3. Background timer flushes queue every 5s → AppendEvents API call
4. On network failure: events queued to .felix/outbox/*.jsonl
5. Retry with exponential backoff (automatic)
```

### Status Updates

```
1. Agent changes mode/state → OnPostModeSelection/OnBackpressureFailed
2. Check last update timestamp
3. If >= 1000ms elapsed (or forced): send status_update event
4. Otherwise: skip (throttled)
```

### Artifact Upload

```
1. Run completes → OnRunComplete hook
2. Find latest folder in runs/ directory
3. Scan all files, compute SHA256 hashes
4. Upload files not already on server (idempotent)
5. Batch upload in single HTTP request
```

## API Endpoints Used

- `POST /api/agents/register` - Agent registration (one-time)
- `POST /api/runs` - Create run record
- `POST /api/runs/{id}/events` - Append events (batch)
- `PATCH /api/runs/{id}` - Update run status
- `POST /api/runs/{id}/artifacts` - Upload artifacts
- `PATCH /api/runs/{id}/finish` - Mark run complete

## Outbox Queue

Failed uploads are queued locally for retry:

- **Location**: `.felix/outbox/*.jsonl`
- **Format**: NDJSON (one operation per line)
- **Retry**: Automatic with exponential backoff
- **Max Retries**: 5 attempts (configurable)
- **Persistence**: Survives agent restarts

### Troubleshooting Outbox

```powershell
# View pending uploads
Get-ChildItem .felix\outbox\*.jsonl

# Check specific file
Get-Content .felix\outbox\<filename>.jsonl | ConvertFrom-Json

# Clear stale queue (careful!)
Remove-Item .felix\outbox\*.jsonl
```

## Testing

```powershell
# Run sync plugin tests
.\.felix\tests\test-sync-http.ps1

# Test with backend
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "http://localhost:8080"
.\felix\felix-agent.ps1 -RequirementId S-0001
```

## Troubleshooting

**Sync not working:**

1. Check backend is running: `curl http://localhost:8080/health`
2. Verify API key: `echo $env:FELIX_SYNC_KEY`
3. Check logs: `.felix/sync.log`
4. Check outbox: `ls .felix\outbox\*.jsonl`

**Events not appearing:**

- Events batch every 5s by default (check `event_batch_interval`)
- Critical events flush immediately
- Check console for `[sync-http]` verbose messages (`-Verbose` flag)

**413 Payload Too Large:**

- Large artifacts may exceed server limits
- Backend default: 50MB max upload
- Split artifacts or increase server `client_max_body_size`

**429 Too Many Requests:**

- Rate limit: 100 requests/minute (backend default)
- Reduce `event_batch_interval` or increase server rate limit
- Check X-RateLimit-Reset header for retry time

## Permissions

The plugin requires these permissions (defined in plugin.json):

- `read:state` - Read agent state/config
- `write:runs` - Create and update run records
- `write:events` - Send events to backend
- `read:artifacts` - Read files from runs/ directory

## Dependencies

- httpSync class (http-client.ps1)
- Felix backend API (app/backend)
- Active internet connection (or accessible backend URL)

## See Also

- [AGENTS.md](../../../AGENTS.md#sync-configuration) - Sync setup guide
- [SYNC_OPERATIONS.md](../../../docs/SYNC_OPERATIONS.md) - Operational procedures
- [Backend API docs](http://localhost:8080/docs) - Swagger UI
