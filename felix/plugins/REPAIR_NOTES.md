# Plugin System Repair Notes

## Issue Identified: 2026-01-29

All three plugins are failing with the same error:

```
You cannot call a method on a null-valued expression.
```

## Affected Plugins

- **prompt-enhancer** - Enhances prompts with additional context
- **metrics-collector** - Collects execution metrics
- **slack-notifier** - Sends Slack notifications

## Symptoms

- Error occurs in `Invoke-PluginHook` function
- All hooks fail: OnPreIteration, OnContextGathering, OnPreLLM, OnPostLLM
- Plugin system loads 3 plugins successfully but execution fails
- Felix agent continues to work with plugins disabled

## Root Cause Analysis Needed

1. Check for null reference in plugin permission checking
2. Verify plugin script execution paths exist
3. Investigate PowerShell scoping issues in plugin execution
4. Review plugin hook script implementations

## Temporary Fix

All plugins disabled in felix/config.json:

```json
"disabled": [
  "prompt-enhancer",
  "metrics-collector",
  "slack-notifier"
]
```

## Next Steps

1. Fix null reference error in plugin infrastructure
2. Test each plugin individually
3. Re-enable plugins once fixed
4. Add better error handling and logging

## Testing

Use S-0999 dummy spec to test plugin fixes without side effects.
