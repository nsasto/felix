<#
.SYNOPSIS
Requirement operations and validation utilities for Felix agent

.DESCRIPTION
Provides functions for updating requirement status and run IDs, and
invoking PowerShell-based validation scripts.
#>

function Update-RequirementStatus {
    <#
    .SYNOPSIS
    Updates the status of a requirement in requirements.json
    
    .PARAMETER RequirementsFilePath
    Path to requirements.json
    
    .PARAMETER RequirementId
    ID of the requirement to update
    
    .PARAMETER NewStatus
    New status value (draft, planned, in_progress, complete, blocked)
    
    .OUTPUTS
    Boolean indicating success or failure
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementsFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$RequirementId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('draft', 'planned', 'in_progress', 'complete', 'blocked')]
        [string]$NewStatus
    )
    
    try {
        if (-not (Test-Path $RequirementsFilePath)) {
            Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
            Write-Host "Requirements file not found: $RequirementsFilePath" -ForegroundColor Red
            return $false
        }
        
        $json = Get-Content $RequirementsFilePath -Raw | ConvertFrom-Json
        $found = $false
        
        if ($json.requirements) {
            foreach ($req in $json.requirements) {
                if ($req.id -eq $RequirementId) {
                    $req.status = $NewStatus
                    $found = $true
                    break
                }
            }
        }
        
        if (-not $found) {
            Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
            Write-Host "Warning: Requirement $RequirementId not found" -ForegroundColor Yellow
            return $false
        }
        
        $json | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $RequirementsFilePath
        Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
        Write-Host "Updated $RequirementId status to '$NewStatus'" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
        Write-Host "Error updating status: $_" -ForegroundColor Red
        return $false
    }
}

function Update-RequirementRunId {
    <#
    .SYNOPSIS
    Updates the last_run_id field for a specific requirement in requirements.json
    
    .PARAMETER RequirementsFilePath
    Path to requirements.json
    
    .PARAMETER RequirementId
    ID of the requirement to update
    
    .PARAMETER RunId
    Run ID to set as last_run_id
    
    .OUTPUTS
    Boolean indicating success or failure
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementsFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$RequirementId,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )
    
    try {
        if (-not (Test-Path $RequirementsFilePath)) {
            Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
            Write-Host "Requirements file not found: $RequirementsFilePath" -ForegroundColor Red
            return $false
        }
        
        $json = Get-Content $RequirementsFilePath -Raw | ConvertFrom-Json
        $found = $false
        
        foreach ($req in $json.requirements) {
            if ($req.id -eq $RequirementId) {
                # Always use Add-Member with -Force to handle both new and existing properties
                $req | Add-Member -NotePropertyName "last_run_id" -NotePropertyValue $RunId -Force
                $found = $true
                break
            }
        }
        
        if (-not $found) {
            Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
            Write-Host "Could not find requirement $RequirementId in requirements.json" -ForegroundColor Yellow
            return $false
        }
        
        $json | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $RequirementsFilePath
        Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
        Write-Host "Updated $RequirementId with last_run_id: $RunId" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[REQUIREMENTS] " -NoNewline -ForegroundColor Cyan
        Write-Host "Error updating last_run_id: $_" -ForegroundColor Red
        return $false
    }
}

function Invoke-RequirementValidation {
    <#
    .SYNOPSIS
    Runs scripts/validate-requirement.ps1 (PowerShell validation script)
    
    .PARAMETER ValidationScript
    Path to the validation script
    
    .PARAMETER RequirementId
    ID of the requirement to validate
    
    .OUTPUTS
    Hashtable with 'output' and 'exitCode' keys
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ValidationScript,
        
        [Parameter(Mandatory = $true)]
        [string]$RequirementId
    )
    
    Write-Host "[VALIDATION] Script: $ValidationScript"
    Write-Host "[VALIDATION] Requirement: $RequirementId"
    
    # Call PowerShell validation script directly
    $prevErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    
    try {
        # Execute the PowerShell validation script
        $output = & $ValidationScript $RequirementId 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        
        if ($null -eq $exitCode) {
            $exitCode = 0
        }
    }
    catch {
        $output = $_.Exception.Message
        $exitCode = 1
    }
    finally {
        $ErrorActionPreference = $prevErrorAction
    }
    
    return @{ output = $output; exitCode = $exitCode }
}

Export-ModuleMember -Function Update-RequirementStatus, Update-RequirementRunId, Invoke-RequirementValidation
