<#
.SYNOPSIS
Requirements state management
#>

function Get-RequirementsState {
    <#
    .SYNOPSIS
    Reads requirements.json with validation
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RequirementsFile
    )

    if (-not (Test-Path $RequirementsFile)) {
        throw "Requirements file not found: $RequirementsFile"
    }

    try {
        $content = Get-Content $RequirementsFile -Raw | ConvertFrom-Json
        return $content
    }
    catch {
        throw "Failed to parse requirements.json: $($_.Exception.Message)"
    }
}

function Save-RequirementsState {
    <#
    .SYNOPSIS
    Writes requirements.json with standardized formatting
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RequirementsFile,

        [Parameter(Mandatory=$true)]
        [object]$State
    )

    try {
        $json = $State | ConvertTo-Json -Depth 10
        Set-Content -Path $RequirementsFile -Value $json -Encoding UTF8
    }
    catch {
        throw "Failed to save requirements.json: $($_.Exception.Message)"
    }
}

function Get-NextRequirement {
    <#
    .SYNOPSIS
    Selects next requirement to process
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RequirementsFile
    )

    $state = Get-RequirementsState $RequirementsFile

    # Priority 1: in_progress requirements
    $inProgress = $state.requirements | Where-Object { $_.status -eq "in_progress" } | Select-Object -First 1
    if ($inProgress) {
        return $inProgress
    }

    # Priority 2: planned requirements (respect dependencies)
    $planned = $state.requirements | Where-Object { $_.status -eq "planned" }
    foreach ($req in $planned) {
        # Check if all dependencies are complete
        $dependenciesMet = $true
        if ($req.depends_on) {
            foreach ($depId in $req.depends_on) {
                $dep = $state.requirements | Where-Object { $_.id -eq $depId }
                if ($dep -and $dep.status -ne "complete") {
                    $dependenciesMet = $false
                    break
                }
            }
        }

        if ($dependenciesMet) {
            return $req
        }
    }

    return $null
}

function Update-RequirementStatus {
    <#
    .SYNOPSIS
    Updates status of a specific requirement
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$RequirementsFile,

        [Parameter(Mandatory=$true)]
        [string]$RequirementId,

        [Parameter(Mandatory=$true)]
        [string]$Status,

        [string]$Branch = $null
    )

    $state = Get-RequirementsState $RequirementsFile
    $requirement = $state.requirements | Where-Object { $_.id -eq $RequirementId }

    if (-not $requirement) {
        throw "Requirement not found: $RequirementId"
    }

    $requirement.status = $Status
    if ($Branch) {
        $requirement.branch = $Branch
    }

    Save-RequirementsState $RequirementsFile $state
    Write-Verbose "Updated requirement $RequirementId status to: $Status"
}

