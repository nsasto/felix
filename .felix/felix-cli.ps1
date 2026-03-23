#!/usr/bin/env pwsh
<#
.SYNOPSIS
Felix CLI consumer for NDJSON event stream

.DESCRIPTION
Spawns felix-agent subprocess and consumes NDJSON events from stdout.
Supports multiple output formats: json (passthrough), plain (colored text), rich (enhanced visuals).

.PARAMETER ProjectPath
Path to the Felix repository

.PARAMETER RequirementId
Optional requirement ID to run a specific requirement

.PARAMETER Format
Output format: json, plain, or rich (default: rich)

.PARAMETER EventTypes
Filter events by type (e.g., log, error_occurred, validation_passed)

.PARAMETER MinLevel
Minimum log level to display: debug, info, warn, error (default: info)

.PARAMETER NoStats
Suppress statistics summary at the end

.PARAMETER Sync
Temporarily enable sync for this run (overrides config.json)

.EXAMPLE
.felix\felix-cli.ps1 C:\dev\Felix -RequirementId S-0001

.EXAMPLE
.felix\felix-cli.ps1 C:\dev\Felix -Format json

.EXAMPLE
.felix\felix-cli.ps1 C:\dev\Felix -RequirementId S-0001 -Sync

.EXAMPLE
.felix\felix-cli.ps1 C:\dev\Felix -MinLevel warn -NoStats
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,
    
    [Parameter(Mandatory = $false)]
    [string]$RequirementId = $null,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("json", "plain", "rich")]
    [string]$Format = "json",
    
    [Parameter(Mandatory = $false)]
    [string[]]$EventTypes = @(),
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("debug", "info", "warn", "error")]
    [string]$MinLevel = "info",
    
    [Parameter(Mandatory = $false)]
    [switch]$NoStats,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoCommit,
    
    [Parameter(Mandatory = $false)]
    [switch]$SpecBuildMode,
    
    [Parameter(Mandatory = $false)]
    [switch]$QuickMode,
    
    [Parameter(Mandatory = $false)]
    [string]$InitialPrompt = $null,
    
    [Parameter(Mandatory = $false)]
    [switch]$VerboseMode,

    [Parameter(Mandatory = $false)]
    [switch]$DebugMode,
    
    [Parameter(Mandatory = $false)]
    [switch]$Sync
)

$ErrorActionPreference = "Continue"

# Load text formatting utilities
. "$PSScriptRoot/core/text-utils.ps1"
. "$PSScriptRoot/cli/renderer.ps1"

# Select renderer based on format
$renderer = switch ($Format) {
    "json" { { param($e, $l) Render-Json -Line $l } }
    "plain" { { param($e, $l) Render-Plain -Event $e } }
    "rich" { { param($e, $l) Render-Rich -Event $e } }
}

# Build felix-agent command
$agentScript = Join-Path $PSScriptRoot "felix-agent.ps1"

# Build argument string with proper quoting for ProcessStartInfo
$argParts = @("-NoProfile", "-File", "`"$agentScript`"", "`"$ProjectPath`"")
if ($RequirementId) {
    $argParts += @("-RequirementId", "`"$RequirementId`"")
}
if ($NoCommit) {
    $argParts += @("-NoCommit")
}
if ($SpecBuildMode) {
    $argParts += @("-SpecBuildMode")
}
if ($QuickMode) {
    $argParts += @("-QuickMode")
}
if ($InitialPrompt) {
    $argParts += @("-InitialPrompt", $InitialPrompt)
}
if ($VerboseMode) {
    $argParts += @("-VerboseMode")
}
if ($DebugMode) {
    $argParts += @("-DebugMode")
}

if ($Format -ne "json") {
    Write-Host "$($colors.Bold)$($colors.Cyan)Felix CLI Consumer$($colors.Reset)"
    Write-Host "$($colors.Dim)Format: $Format | Min Level: $MinLevel$($colors.Reset)"
    if ($EventTypes.Count -gt 0) {
        Write-Host "$($colors.Dim)Filtering events: $($EventTypes -join ', ')$($colors.Reset)"
    }
    Write-Host ""
}

# Determine which PowerShell executable to use (prefer pwsh for better streaming)
$pwshExe = Get-Command pwsh -ErrorAction SilentlyContinue
$psExe = if ($pwshExe) { "pwsh" } else { "powershell.exe" }

# Start felix-agent as subprocess
$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = $psExe
$processInfo.Arguments = $argParts -join " "
$processInfo.UseShellExecute = $false
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.CreateNoWindow = $true

# If -Sync flag is set, enable sync for this run only
if ($Sync) {
    # Copy parent environment variables first, then add ours
    foreach ($key in [System.Environment]::GetEnvironmentVariables().Keys) {
        $processInfo.EnvironmentVariables[$key] = [System.Environment]::GetEnvironmentVariable($key)
    }
    $processInfo.EnvironmentVariables["FELIX_SYNC_ENABLED"] = "true"
}

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $processInfo

# Make process accessible to Ctrl+C handler via script scope
$script:agentProcess = $process

# Register Ctrl+C handler to kill subprocess
$ctrlCHandler = {
    param($sender, $e)
    if ($script:agentProcess -and -not $script:agentProcess.HasExited) {
        Write-Host "`n$($colors.Yellow)Cancelling agent execution...$($colors.Reset)" -NoNewline
        try {
            $script:agentProcess.Kill($true)  # Kill entire process tree
            $script:agentProcess.WaitForExit(2000)  # Wait up to 2 seconds
            Write-Host " $($colors.Green)Done$($colors.Reset)"
        }
        catch {
            Write-Host " $($colors.Red)Failed$($colors.Reset)"
        }
    }
    $e.Cancel = $true  # Prevent process termination, let finally block handle cleanup
}

$ctrlCEvent = [System.Console]::add_CancelKeyPress($ctrlCHandler)

try {
    $process.Start() | Out-Null
    
    # Register session for tracking
    . "$PSScriptRoot\core\session-manager.ps1"
    $runId = if ($RequirementId) { "$RequirementId-$(Get-Date -Format 'yyyyMMdd-HHmmss')" } else { "loop-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
    $agentName = "felix-primary"  # TODO: Get from config
    Register-Session -SessionId $runId -RequirementId $RequirementId -ProcessId $process.Id -AgentName $agentName -ProjectPath $ProjectPath
    
    # Read stdout line by line using StreamReader for better buffering control
    $reader = $process.StandardOutput
    
    while (-not $process.HasExited -or -not $reader.EndOfStream) {
        if (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            # Try to parse as JSON
            try {
                $event = $line | ConvertFrom-Json -ErrorAction Stop
                
                # Check for standard format (type/data) or legacy format (event field)
                $isStandardEvent = $event.type -and $event.data
                $isLegacyEvent = $event.event -and -not $event.type
                
                if ($isStandardEvent) {
                    # Standard format - use as-is
                    Update-Stats -Event $event
                    
                    if (Should-Display-Event -Event $event) {
                        & $renderer $event $line
                    }
                }
                elseif ($isLegacyEvent) {
                    # Legacy format - convert to standard format
                    $standardEvent = @{
                        type      = $event.event
                        timestamp = $event.timestamp
                        data      = @{}
                    }
                    
                    # Copy all fields except 'event' and 'timestamp' to data
                    $event.PSObject.Properties | Where-Object { $_.Name -notin @('event', 'timestamp') } | ForEach-Object {
                        $standardEvent.data[$_.Name] = $_.Value
                    }
                    
                    $convertedEvent = [PSCustomObject]$standardEvent
                    Update-Stats -Event $convertedEvent
                    
                    if (Should-Display-Event -Event $convertedEvent) {
                        & $renderer $convertedEvent $line
                    }
                }
                else {
                    # Valid JSON but not an event
                    if ($Format -eq "json") {
                        Write-Output $line
                    }
                    elseif ($Format -ne "json") {
                        Write-Host "$($colors.Dim)Non-event JSON: $line$($colors.Reset)"
                    }
                }
            }
            catch {
                # Not JSON - treat as legacy console output
                if ($Format -eq "json") {
                    Write-Output $line
                }
                else {
                    Write-Host "$($colors.Yellow)[LEGACY OUTPUT]$($colors.Reset) $line"
                }
            }
        }
        else {
            # No data available, brief sleep
            Start-Sleep -Milliseconds 50
        }
    }
    
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    
    # Read any stderr output
    $stderrText = $process.StandardError.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($stderrText) -and $Format -ne "json") {
        $stderrLines = $stderrText -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        foreach ($errLine in $stderrLines) {
            Write-Host "$($colors.Red)[STDERR]$($colors.Reset) $errLine"
        }
    }
    
    # Show stats for non-json formats
    if ($Format -ne "json") {
        Show-Stats
        Write-Host "$($colors.Dim)Felix agent exited with code: $exitCode$($colors.Reset)"
    }
    
    # Unregister session
    Unregister-Session -SessionId $runId -ProjectPath $ProjectPath
    
    exit $exitCode
}
catch {
    if ($Format -ne "json") {
        Write-Host "$($colors.Red)Error running felix-agent: $_$($colors.Reset)"
    }
    
    # Unregister session on error
    if ($runId) {
        Unregister-Session -SessionId $runId -ProjectPath $ProjectPath
    }
    
    exit 1
}
finally {
    # Unregister Ctrl+C handler
    if ($ctrlCEvent) {
        [System.Console]::remove_CancelKeyPress($ctrlCHandler)
    }
    
    if ($process -and -not $process.HasExited) {
        $process.Kill()
    }
    if ($process) {
        $process.Dispose()
    }
}
