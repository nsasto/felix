# ═══════════════════════════════════════════════════════════════════════════
# Felix Plugin API Documentation Generator
# ═══════════════════════════════════════════════════════════════════════════
# Generates API documentation from hook contracts

param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "felix\plugins\API.md"
)

$contractsPath = Join-Path $PSScriptRoot "..\felix\plugins\hook-contracts.ps1"

if (-not (Test-Path $contractsPath)) {
    Write-Error "Hook contracts file not found: $contractsPath"
    exit 1
}

Write-Host "Generating plugin API documentation..." -ForegroundColor Cyan

# Read hook contracts
$contractsContent = Get-Content $contractsPath -Raw

# Extract hook information
$hooks = @(
    @{ Name = "OnPreIteration"; Description = "Executed before each iteration starts"; Phase = "Iteration Setup" }
    @{ Name = "OnPostModeSelection"; Description = "Executed after planning/building mode is determined"; Phase = "Mode Selection" }
    @{ Name = "OnContextGathering"; Description = "Executed during context gathering phase"; Phase = "Context Gathering" }
    @{ Name = "OnPreLLM"; Description = "Executed before LLM execution"; Phase = "LLM Execution" }
    @{ Name = "OnPostLLM"; Description = "Executed after LLM execution completes"; Phase = "LLM Execution" }
    @{ Name = "OnGuardrailCheck"; Description = "Executed after guardrail validation (planning mode only)"; Phase = "Guardrails" }
    @{ Name = "OnPreBackpressure"; Description = "Executed before backpressure validation runs"; Phase = "Validation" }
    @{ Name = "OnBackpressureFailed"; Description = "Executed when backpressure validation fails"; Phase = "Validation" }
    @{ Name = "OnPreCommit"; Description = "Executed before git commit"; Phase = "Commit" }
    @{ Name = "OnPostValidation"; Description = "Executed after validation completes"; Phase = "Validation" }
    @{ Name = "OnPostIteration"; Description = "Executed after iteration completes"; Phase = "Iteration Cleanup" }
)

# Build documentation
$doc = @"
# Felix Plugin API Documentation

**Version**: 1.0.0  
**Generated**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

## Overview

The Felix Plugin API provides 11 lifecycle hooks that allow plugins to extend and customize the behavior of the Felix autonomous agent. Plugins are discovered automatically from the ``.felix/plugins/`` directory and loaded in dependency order.

## Plugin Structure

``````
.felix/plugins/
  your-plugin/
    plugin.json           # Manifest (required)
    on-hookname.ps1       # Hook scripts (v1 API)
    persistent-state.json # Persistent state (auto-generated)
    README.md             # Documentation
    tests/                # Tests
``````

## API Versions

- **v1**: Hook scripts named ``on-{hookname}.ps1`` (e.g., ``on-prediteration.ps1``)
- **v2**: Hook scripts in ``hooks/{HookName}.ps1`` subdirectory (e.g., ``hooks/OnPreIteration.ps1``)

## Permissions Model

Plugins must declare required permissions in their manifest:

| Permission | Description |
|-----------|-------------|
| ``read:specs`` | Read spec files from specs/ |
| ``read:state`` | Read .felix/state.json and .felix/requirements.json |
| ``read:runs`` | Read run artifacts from runs/ |
| ``write:runs`` | Write to run artifacts in runs/ |
| ``write:logs`` | Write to log files |
| ``execute:commands`` | Execute external commands |
| ``network:http`` | Make HTTP requests |
| ``git:read`` | Read git state |
| ``git:write`` | Execute git commands |

## Available Hooks

"@

# Group hooks by phase
$phases = $hooks | Group-Object -Property Phase

foreach ($phase in $phases) {
    $doc += "`n### $($phase.Name)`n`n"
    
    foreach ($hook in $phase.Group) {
        $doc += "#### $($hook.Name)`n`n"
        $doc += "**Description**: $($hook.Description)`n`n"
        
        # Extract parameter class from contracts
        $paramClass = "$($hook.Name)Params"
        $resultClass = "$($hook.Name)Result"
        
        # Find class definition
        $paramMatch = $contractsContent -match "class $paramClass \{([^}]+)\}"
        if ($paramMatch) {
            $doc += "**Parameters**:`n``````powershell`n"
            $doc += "class $paramClass {`n"
            
            # Extract properties
            $properties = [regex]::Matches($contractsContent, "(?<=class $paramClass \{)([\s\S]*?)(?=\})")
            if ($properties.Count -gt 0) {
                $propText = $properties[0].Value
                $doc += $propText.Trim()
                $doc += "`n"
            }
            
            $doc += "}`n``````"
        }
        
        $doc += "`n`n**Return Type**: ``$resultClass```n`n"
        
        # Add usage example
        $doc += "**Example**:`n``````powershell`n"
        $doc += "param(`n"
        $doc += "    [Parameter(Mandatory = `$true)]`n"
        $doc += "    [hashtable]`$HookData,`n"
        $doc += "    [Parameter(Mandatory = `$true)]`n"
        $doc += "    [string]`$RunId,`n"
        $doc += "    [Parameter(Mandatory = `$true)]`n"
        $doc += "    `$PluginConfig`n"
        $doc += ")`n`n"
        $doc += "# Your plugin logic here`n`n"
        $doc += "return @{}`n"
        $doc += "``````"
        $doc += "`n`n"
    }
}

# Add state management section
$doc += @"

## State Management

Plugins can store data in two ways:

### Persistent State

Survives across runs, stored in ``.felix/plugins/{name}/persistent-state.json``:

``````powershell
# Read
`$value = Get-PluginPersistentState -PluginName "my-plugin" -Key "counter"

# Write
Set-PluginPersistentState -PluginName "my-plugin" -Key "counter" -Value 42
``````

### Transient State

Per-run only, stored in ``runs/{runId}/plugin-state-{name}.json``:

``````powershell
# Read
`$value = Get-PluginTransientState -PluginName "my-plugin" -RunId `$RunId -Key "temp_data"

# Write
Set-PluginTransientState -PluginName "my-plugin" -RunId `$RunId -Key "temp_data" -Value "test"
``````

## Circuit Breaker

If a plugin fails repeatedly (default: 3 times), it is automatically disabled for the session. Configure threshold in ``.felix/config.json``:

``````json
{
  "plugins": {
    "circuit_breaker_max_failures": 3
  }
}
``````

## Hook Execution Order

Hooks execute in the following order within each iteration:

1. **OnPreIteration** - Setup
2. **OnPostModeSelection** - After mode determined
3. **OnContextGathering** - During context collection
4. **OnPreLLM** - Before AI execution
5. **OnPostLLM** - After AI execution
6. **OnGuardrailCheck** - Planning mode validation (optional)
7. **OnPreBackpressure** - Before validation (building mode)
8. **OnBackpressureFailed** - On validation failure (optional)
9. **OnPreCommit** - Before git commit (optional)
10. **OnPostValidation** - After requirement validation (optional)
11. **OnPostIteration** - Cleanup

## Plugin Chaining

Plugins execute in priority order (lower = earlier). Each plugin receives the output of the previous plugin in the chain, allowing data to flow through the plugin pipeline.

## Testing

Use the test harness to validate your plugin:

``````powershell
cd .felix/plugins
.\test-harness.ps1 -PluginPath .\your-plugin -RunAll
``````

## Example Plugins

See these reference implementations:

- **slack-notifier**: Sends Slack notifications on key events
- **metrics-collector**: Collects execution metrics
- **prompt-enhancer**: Enhances prompts with additional context

## Resources

- [Plugin Manifest Schema](plugin-manifest.schema.json)
- [Hook Contracts](hook-contracts.ps1)
- [Test Harness](test-harness.ps1)
- [Example Plugins](.)

"@

# Write documentation
Set-Content $OutputPath $doc -Encoding UTF8

Write-Host "✅ Documentation generated: $OutputPath" -ForegroundColor Green
Write-Host ""
Write-Host "Preview:" -ForegroundColor Yellow
Write-Host "  Lines: $((Get-Content $OutputPath | Measure-Object -Line).Lines)"
Write-Host "  Size: $([math]::Round((Get-Item $OutputPath).Length / 1KB, 2)) KB"

