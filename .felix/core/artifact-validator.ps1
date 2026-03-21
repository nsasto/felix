function Get-RunPlanPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunDir,

        [Parameter(Mandatory = $true)]
        [string]$RequirementId
    )

    return (Join-Path $RunDir "plan-$RequirementId.md")
}

function Get-PlanCheckboxSummary {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    return @{
        Checked   = ([regex]::Matches($Content, '(?m)^- \[x\] .+$')).Count
        Unchecked = ([regex]::Matches($Content, '(?m)^- \[ \] .+$')).Count
    }
}

function Test-PlanStructure {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return @{ IsValid = $false; Reason = "Plan file is empty." }
    }

    if ($Content -notmatch '(?m)^#\s+') {
        return @{ IsValid = $false; Reason = "Plan file must contain a top-level heading." }
    }

    if ($Content -notmatch '(?m)^##\s+Tasks\s*$') {
        return @{ IsValid = $false; Reason = "Plan file must contain a ## Tasks section." }
    }

    $checkboxSummary = Get-PlanCheckboxSummary -Content $Content
    if (($checkboxSummary.Checked + $checkboxSummary.Unchecked) -eq 0) {
        return @{ IsValid = $false; Reason = "Plan file must contain at least one task checkbox." }
    }

    return @{ IsValid = $true; Reason = $null }
}

function Test-PlanningArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunDir,

        [Parameter(Mandatory = $true)]
        [string]$RequirementId
    )

    $planPath = Get-RunPlanPath -RunDir $RunDir -RequirementId $RequirementId
    if (-not (Test-Path $planPath)) {
        return @{ IsValid = $false; Reason = "Planning completed without creating the run plan file."; PlanPath = $planPath }
    }

    $content = Get-Content $planPath -Raw
    $structure = Test-PlanStructure -Content $content
    return @{ IsValid = $structure.IsValid; Reason = $structure.Reason; PlanPath = $planPath }
}

function Test-BuildingArtifact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunDir,

        [Parameter(Mandatory = $true)]
        [string]$RequirementId,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$PreviousPlanContent = "",

        [Parameter(Mandatory = $true)]
        [string]$Signal
    )

    $planPath = Get-RunPlanPath -RunDir $RunDir -RequirementId $RequirementId
    if (-not (Test-Path $planPath)) {
        return @{ IsValid = $false; Reason = "Task completion was signaled without an updated run plan file."; PlanPath = $planPath }
    }

    $content = Get-Content $planPath -Raw
    $structure = Test-PlanStructure -Content $content
    if (-not $structure.IsValid) {
        return @{ IsValid = $false; Reason = $structure.Reason; PlanPath = $planPath }
    }

    if (-not [string]::IsNullOrEmpty($PreviousPlanContent)) {
        $before = Get-PlanCheckboxSummary -Content $PreviousPlanContent
        $after = Get-PlanCheckboxSummary -Content $content

        if ($after.Checked -le $before.Checked) {
            return @{ IsValid = $false; Reason = "Task completion was signaled without checking off any plan items."; PlanPath = $planPath }
        }

        if ($Signal -eq "ALL_COMPLETE" -and $after.Unchecked -gt 0) {
            return @{ IsValid = $false; Reason = "ALL_COMPLETE was signaled but unchecked plan items remain."; PlanPath = $planPath }
        }
    }

    return @{ IsValid = $true; Reason = $null; PlanPath = $planPath }
}

function Test-IterationArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$RunDir,

        [Parameter(Mandatory = $true)]
        [string]$RequirementId,

        [Parameter(Mandatory = $true)]
        [string]$AgentOutput,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$PreviousPlanContent = ""
    )

    $signal = Get-CompletionSignal -Output $AgentOutput -AllowPlanningAlias
    $taskCompleted = $AgentOutput -match '(?m)^\*\*Task Completed:\*\*\s*\S.+$'

    if ($Mode -eq "planning" -and $signal -eq "PLAN_COMPLETE") {
        $planningResult = Test-PlanningArtifact -RunDir $RunDir -RequirementId $RequirementId
        return @{
            IsRequired = $true
            IsValid    = $planningResult.IsValid
            Reason     = $planningResult.Reason
            Signal     = $signal
            PlanPath   = $planningResult.PlanPath
        }
    }

    if ($Mode -eq "building" -and ($taskCompleted -or $signal -in @("TASK_COMPLETE", "ALL_COMPLETE"))) {
        $buildingSignal = if ($signal) { $signal } else { "TASK_COMPLETE" }
        $buildingResult = Test-BuildingArtifact -RunDir $RunDir -RequirementId $RequirementId -PreviousPlanContent $PreviousPlanContent -Signal $buildingSignal
        return @{
            IsRequired = $true
            IsValid    = $buildingResult.IsValid
            Reason     = $buildingResult.Reason
            Signal     = $buildingSignal
            PlanPath   = $buildingResult.PlanPath
        }
    }

    return @{
        IsRequired = $false
        IsValid    = $true
        Reason     = $null
        Signal     = $signal
        PlanPath   = (Get-RunPlanPath -RunDir $RunDir -RequirementId $RequirementId)
    }
}

function Write-ArtifactValidationFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunDir,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $reportPath = Join-Path $RunDir "artifact-validation.md"
    $content = @"
# Artifact Validation Failed

**Timestamp:** $(Get-Date -Format "o")

## Reason

$Message
"@

    Set-Content $reportPath $content -Encoding UTF8
    return $reportPath
}