<#
.SYNOPSIS
Planning mode guardrails for Felix agent

.DESCRIPTION
Provides functions to enforce planning mode restrictions - preventing code commits
and unauthorized file modifications during the planning phase.
#>

function Test-PlanningModeGuardrails {
    <#
    .SYNOPSIS
    Checks if planning mode guardrails were violated (code files modified or committed)
    
    .PARAMETER WorkingDir
    The project working directory
    
    .PARAMETER BeforeState
    Git state captured before the LLM execution
    
    .PARAMETER RunId
    Current run identifier
    
    .OUTPUTS
    Hashtable with violation details: CommitMade, UnauthorizedFiles, HasViolations
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkingDir,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$BeforeState,
        
        [Parameter(Mandatory = $false)]
        [string]$RunId
    )
    

    Push-Location $WorkingDir
    try {
        $violations = @{
            CommitMade        = $false
            UnauthorizedFiles = @()
            HasViolations     = $false
        }
        
        # Allowed paths for planning mode (relative paths)
        $allowedPatterns = @(
            "^runs/",                          # Run directories
            "^\.felix/state\.json$",           # State file
            "^\.felix/requirements\.json$"     # Requirements file
        )
        
        # Get current git state
        $afterState = Get-GitState -WorkingDir $WorkingDir
        
        # Check if a new commit was made
        if ($afterState.commitHash -ne $BeforeState.commitHash) {
            $violations.CommitMade = $true
            $violations.HasViolations = $true
            Emit-Error -ErrorType "GuardrailViolation" -Message "New commit detected during planning mode!" -Severity "error"
        }
        
        # Check for unauthorized file modifications
        $allModifiedFiles = @($afterState.modifiedFiles) + @($afterState.untrackedFiles) | 
        Where-Object { $_ -and $_.Trim() -ne "" } |
        Select-Object -Unique
        
        foreach ($file in $allModifiedFiles) {
            # Skip if file was already modified before
            if ($BeforeState.modifiedFiles -contains $file -or $BeforeState.untrackedFiles -contains $file) {
                continue
            }
            
            # Check if file matches allowed patterns
            $isAllowed = $false
            $normalizedFile = $file -replace '\\', '/'
            foreach ($pattern in $allowedPatterns) {
                if ($normalizedFile -match $pattern) {
                    $isAllowed = $true
                    break
                }
            }
            
            if (-not $isAllowed) {
                $violations.UnauthorizedFiles += $file
                $violations.HasViolations = $true
            }
        }
        
        if ($violations.UnauthorizedFiles.Count -gt 0) {
            Emit-Error -ErrorType "GuardrailViolation" -Message "Unauthorized files modified in planning mode" -Severity "error" -Context @{
                files = $violations.UnauthorizedFiles
            }
            foreach ($file in $violations.UnauthorizedFiles) {
                Emit-Log -Level "error" -Message "  - $file" -Component "guardrail"
            }
        }
        
        return $violations
    }
    finally {
        Pop-Location
    }
}

function Undo-PlanningViolations {
    <#
    .SYNOPSIS
    Reverts unauthorized changes made during planning mode
    
    .PARAMETER WorkingDir
    The project working directory
    
    .PARAMETER BeforeState
    Git state from before the LLM execution
    
    .PARAMETER Violations
    Violations object from Test-PlanningModeGuardrails
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkingDir,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$BeforeState,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Violations
    )
    
    Push-Location $WorkingDir
    try {
        # Revert commit if one was made
        if ($Violations.CommitMade) {
            Emit-Log -Level "warn" -Message "Reverting unauthorized commit..." -Component "guardrail"
            git reset --soft $BeforeState.commitHash 2>$null
        }
        
        # Revert unauthorized file changes
        foreach ($file in $Violations.UnauthorizedFiles) {
            if (Test-Path $file) {
                # Check if it was an existing file (modified) or new file
                $wasTracked = git ls-files $file 2>$null
                if ($wasTracked) {
                    Emit-Log -Level "info" -Message "Reverting changes to: $file" -Component "guardrail"
                    git checkout HEAD -- $file 2>$null
                }
                else {
                    Emit-Log -Level "info" -Message "Removing unauthorized new file: $file" -Component "guardrail"
                    Remove-Item $file -Force
                }
            }
        }
        
        Emit-Log -Level "info" -Message "Violations reverted" -Component "guardrail"
    }
    finally {
        Pop-Location
    }
}

