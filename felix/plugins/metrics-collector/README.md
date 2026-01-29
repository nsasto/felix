# Metrics Collector Plugin

Collects and stores execution metrics for Felix agent performance analysis.

## Features

- Tracks iteration duration
- Records LLM execution metrics (exit code, output size)
- Stores metrics both persistently and per-run
- Provides historical performance data

## Data Collected

Per iteration:
- Iteration number
- Requirement ID
- Mode (planning/building)
- Outcome (success/error/blocked)
- Duration in seconds
- LLM exit code
- LLM output size in bytes
- Timestamp

## Storage

**Persistent**: `felix/plugins/metrics-collector/persistent-state.json`
- Contains all historical metrics across all runs
- Use for trend analysis and performance tracking

**Per-Run**: `runs/{runId}/metrics.json`
- Contains metrics for that specific iteration
- Use for debugging individual runs

## Example Metrics

```json
{
  "iteration": 1,
  "requirement_id": "S-0001",
  "mode": "building",
  "outcome": "success",
  "duration_seconds": 45.67,
  "llm_exit_code": 0,
  "llm_output_size": 12345,
  "timestamp": "2026-01-27T10:30:00Z"
}
```

## Analysis

To analyze metrics, read the persistent state:

```powershell
$metrics = Get-Content felix/plugins/metrics-collector/persistent-state.json | ConvertFrom-Json
$metrics.metrics | Measure-Object -Property duration_seconds -Average -Maximum -Minimum
```

## Testing

```powershell
cd felix/plugins
.\test-harness.ps1 -PluginPath .\metrics-collector -RunAll
```

## Permissions Required

- `read:state` - Read Felix state information
- `read:runs` - Read run artifacts
- `write:runs` - Write metrics files to run directories
