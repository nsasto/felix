#!/usr/bin/env pwsh
# Felix Loop - Autonomous Multi-Requirement Executor
# Usage: .\felix-loop.ps1 <ProjectPath> [-MaxRequirements <N>] [-NoCommit]
#
# Continuously selects and processes planned/in_progress requirements
# until none remain or max requirements limit is reached.
#
# Use -NoCommit flag for testing without git commits

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxRequirements = 999,
    
    [Parameter(Mandatory = $false)]
    [switch]$NoCommit,   # Use this flag for testing to prevent git commits
    
    [Parameter(Mandatory = $false)]
    [string]$Format = "json"  # Output format: json, plain, or rich
)

$ErrorActionPreference = "Stop"

# Load NDJSON event emission functions
. (Join-Path $PSScriptRoot "core\emit-event.ps1")

# Helper to conditionally emit logs based on format
function Emit-Loop-Log {
    param(
        [string]$Level,
        [string]$Message,
        [string]$Component = "loop"
    )
    if ($Format -eq "json") {
        Emit-Log -Level $Level -Message $Message -Component $Component
    }
}

# Resolve paths
$ProjectPath = Resolve-Path $ProjectPath
$RequirementsFile = Join-Path $ProjectPath ".felix\requirements.json"
$FelixScript = Join-Path $ProjectPath ".felix\felix.ps1"

# Only emit JSON events when format is json, otherwise use plain text
if ($Format -eq "json") {
    Emit-Loop-Log -Level "info" -Message "Felix Loop - Autonomous Multi-Requirement Executor"
    Emit-Loop-Log -Level "info" -Message "Project: $ProjectPath"
    Emit-Loop-Log -Level "info" -Message "Max requirements: $MaxRequirements"
}

# Create process-specific lock file to track active loops
$lockDir = Join-Path $ProjectPath ".felix\.locks"
if (-not (Test-Path $lockDir)) {
    New-Item -Path $lockDir -ItemType Directory -Force | Out-Null
}

$lockFile = Join-Path $lockDir "loop-$PID.lock"
$lockData = @{
    pid     = $PID
    started = Get-Date -Format "o"
    project = $ProjectPath
} | ConvertTo-Json

Set-Content -Path $lockFile -Value $lockData
Emit-Loop-Log -Level "debug" -Message "Created loop lock: $lockFile"

# Cleanup function
function Remove-LoopLock {
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        Emit-Loop-Log -Level "debug" -Message "Removed loop lock"
    }
}

# Register cleanup on exit
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Remove-LoopLock } | Out-Null
function Select-NextRequirement {
    param([string]$RequirementsFilePath)
    
    if (-not (Test-Path $RequirementsFilePath)) {
        Emit-Error -ErrorType "RequirementsFileNotFound" -Message "Requirements file not found: $RequirementsFilePath" -Severity "error"
        return $null
    }
    
    try {
        $requirements = Get-Content $RequirementsFilePath -Raw | ConvertFrom-Json
    }
    catch {
        Emit-Error -ErrorType "RequirementsParseError" -Message "Failed to parse requirements.json: $_" -Severity "error"
        return $null
    }
    
    # Find first in_progress, then first planned (explicitly exclude complete, blocked, done)
    # Sort by ID to ensure sequential processing (S-0001, S-0002, etc.)
    $req = $requirements.requirements | Where-Object { 
        $_.status -eq "in_progress" 
    } | Sort-Object { $_.id } | Select-Object -First 1
    
    if (-not $req) {
        $req = $requirements.requirements | Where-Object { 
            $_.status -eq "planned" 
        } | Sort-Object { $_.id } | Select-Object -First 1
    }
    
    return $req
}

$requirementsProcessed = 0

while ($requirementsProcessed -lt $MaxRequirements) {
    # Select next requirement
    $nextReq = Select-NextRequirement -RequirementsFilePath $RequirementsFile
    
    if (-not $nextReq) {
        Emit-Loop-Log -Level "info" -Message "No more requirements to process - all done!"
        exit 0
    }
    
    Emit-Loop-Log -Level "info" -Message "Processing requirement: $($nextReq.id) - $($nextReq.title)"
    
    # Validate parameters before calling felix-agent
    if (-not $nextReq.id) {
        Emit-Error -ErrorType "InvalidRequirementId" -Message "nextReq.id is null or empty" -Severity "error"
        Emit-Loop-Log -Level "debug" -Message "nextReq object: $($nextReq | ConvertTo-Json -Depth 2)"
        continue
    }
    
    # Double-check requirement status immediately before processing (catch external changes)
    try {
        $freshReqs = Get-Content $RequirementsFile -Raw | ConvertFrom-Json
        $freshReq = $freshReqs.requirements | Where-Object { $_.id -eq $nextReq.id } | Select-Object -First 1
        
        if (-not $freshReq) {
            Emit-Loop-Log -Level "warn" -Message "Requirement $($nextReq.id) no longer exists - skipping"
            continue
        }
        
        if ($freshReq.status -notin @("planned", "in_progress")) {
            Emit-Loop-Log -Level "warn" -Message "Requirement $($nextReq.id) status changed to '$($freshReq.status)' - skipping"
            continue
        }
    }
    catch {
        Emit-Loop-Log -Level "warn" -Message "Failed to verify requirement status: $_ - skipping"
        continue
    }
    
    # Execute felix run for this specific requirement
    Emit-Loop-Log -Level "debug" -Message "Calling felix run with RequirementId='$($nextReq.id)', Format='$Format'"
    
    # Call felix run directly - output flows through to console
    if ($Format -ne "json") {
        Write-Host ""  # Blank line before requirement execution
    }
    
    & $FelixScript run $nextReq.id --format $Format
    $exitCode = $LASTEXITCODE
    
    switch ($exitCode) {
        0 {
            # Success - requirement completed
            Emit-Loop-Log -Level "info" -Message "$($nextReq.id) completed successfully"
            
            # Brief pause to ensure requirements.json is updated
            Start-Sleep -Milliseconds 500
            
            # Verify the requirement was actually marked complete
            $updatedReqs = Get-Content $RequirementsFile -Raw | ConvertFrom-Json
            $completedReq = $updatedReqs.requirements | Where-Object { $_.id -eq $nextReq.id }
            
            if ($completedReq -and ($completedReq.status -eq "complete" -or $completedReq.status -eq "done")) {
                Emit-Loop-Log -Level "info" -Message "Status verified: $($nextReq.id) marked as $($completedReq.status)"
            }
            elseif ($completedReq -and $completedReq.status -in @("in_progress", "planned")) {
                Emit-Loop-Log -Level "warn" -Message "$($nextReq.id) still has status '$($completedReq.status)' after processing"
            }
            else {
                Emit-Loop-Log -Level "warn" -Message "$($nextReq.id) status is '$($completedReq.status)' (expected 'complete')"
            }
            
            $requirementsProcessed++
        }
        2 {
            # Blocked due to backpressure failures
            Emit-Loop-Log -Level "warn" -Message "$($nextReq.id) blocked (backpressure failures) - moving to next"
            $requirementsProcessed++
        }
        3 {
            # Blocked due to validation failures
            Emit-Loop-Log -Level "warn" -Message "$($nextReq.id) blocked (validation failures) - moving to next"
            $requirementsProcessed++
        }
        1 {
            # Error - stop loop
            Emit-Error -ErrorType "AgentExecutionError" -Message "$($nextReq.id) encountered an error (exit code 1)" -Severity "fatal"
            exit 1
        }
        default {
            # Unknown exit code - stop loop
            Emit-Error -ErrorType "UnexpectedExitCode" -Message "$($nextReq.id) returned unexpected exit code: $exitCode" -Severity "fatal"
            exit $exitCode
        }
    }
    
    Emit-Loop-Log -Level "info" -Message "Requirements processed: $requirementsProcessed / $MaxRequirements"
}

Emit-Loop-Log -Level "info" -Message "Max requirements limit reached ($MaxRequirements)"

# Cleanup
Remove-LoopLock
exit 0

