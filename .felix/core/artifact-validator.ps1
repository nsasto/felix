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

        # If everything is already checked off, no new ticks are required.
        $allAlreadyDone = ($after.Unchecked -eq 0 -and $after.Checked -gt 0)

        if (-not $allAlreadyDone -and $after.Checked -le $before.Checked) {
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

function Test-IterationContract {
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
    $planPath = Get-RunPlanPath -RunDir $RunDir -RequirementId $RequirementId

    if ($Mode -eq "planning" -and $signal -ne "PLAN_COMPLETE") {
        $planningFallback = Test-PlanningArtifact -RunDir $RunDir -RequirementId $RequirementId
        if ($planningFallback.IsValid) {
            return @{
                IsValid  = $true
                Reason   = $null
                Signal   = "PLAN_COMPLETE"
                PlanPath = $planningFallback.PlanPath
            }
        }

        return @{
            IsValid  = $false
            Reason   = "Missing exact standalone <promise>PLAN_COMPLETE</promise> line for planning completion."
            Signal   = $signal
            PlanPath = $planPath
        }
    }

    if ($Mode -eq "building" -and $signal -notin @("TASK_COMPLETE", "ALL_COMPLETE")) {
        $buildingFallback = Test-BuildingArtifact -RunDir $RunDir -RequirementId $RequirementId -PreviousPlanContent $PreviousPlanContent -Signal "TASK_COMPLETE"
        if ($buildingFallback.IsValid) {
            $inferredSignal = "TASK_COMPLETE"
            if (Test-Path $buildingFallback.PlanPath) {
                $currentPlan = Get-Content $buildingFallback.PlanPath -Raw
                $summary = Get-PlanCheckboxSummary -Content $currentPlan
                if ($summary.Unchecked -eq 0 -and $summary.Checked -gt 0) {
                    $inferredSignal = "ALL_COMPLETE"
                }
            }

            return @{
                IsValid  = $true
                Reason   = $null
                Signal   = $inferredSignal
                PlanPath = $buildingFallback.PlanPath
            }
        }

        return @{
            IsValid  = $false
            Reason   = "Missing exact standalone <promise>TASK_COMPLETE</promise> or <promise>ALL_COMPLETE</promise> line for building completion."
            Signal   = $signal
            PlanPath = $planPath
        }
    }

    $artifactResult = Test-IterationArtifacts -Mode $Mode -RunDir $RunDir -RequirementId $RequirementId -AgentOutput $AgentOutput -PreviousPlanContent $PreviousPlanContent
    return @{
        IsValid  = $artifactResult.IsValid
        Reason   = $artifactResult.Reason
        Signal   = $artifactResult.Signal
        PlanPath = $artifactResult.PlanPath
    }
}

function New-ContractRepairPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePrompt,

        [Parameter(Mandatory = $true)]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [Parameter(Mandatory = $true)]
        [string]$PlanPath
    )

    $requiredSignal = if ($Mode -eq "planning") {
        "<promise>PLAN_COMPLETE</promise>"
    }
    else {
        "<promise>TASK_COMPLETE</promise> or <promise>ALL_COMPLETE</promise>"
    }

    $repairInstructions = @"

---

# Contract Repair

Your previous response was invalid.

Reason: $Reason

Retry once and fix only the output-contract issue. Update **$PlanPath** if needed and end with the required exact standalone completion line:

$requiredSignal
"@

    return ($BasePrompt + $repairInstructions)
}

function Invoke-ContractRepairFlow {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePrompt,

        [Parameter(Mandatory = $true)]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$RunDir,

        [Parameter(Mandatory = $true)]
        [string]$RequirementId,

        [Parameter(Mandatory = $true)]
        [string]$InitialOutput,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$PreviousPlanContent = "",

        [Parameter(Mandatory = $true)]
        [scriptblock]$RetryExecution
    )

    $output = $InitialOutput
    $validation = Test-IterationContract -Mode $Mode -RunDir $RunDir -RequirementId $RequirementId -AgentOutput $output -PreviousPlanContent $PreviousPlanContent
    $attempts = 0
    $lastRetryResult = $null

    while (-not $validation.IsValid -and $attempts -lt 1) {
        $attempts++
        $retryPrompt = New-ContractRepairPrompt -BasePrompt $BasePrompt -Mode $Mode -Reason $validation.Reason -PlanPath $validation.PlanPath
        $lastRetryResult = & $RetryExecution $retryPrompt $attempts $validation.Reason

        if (-not $lastRetryResult.Succeeded) {
            return @{
                IsValid       = $false
                Output        = $lastRetryResult.Output
                Validation    = @{
                    Reason   = "Corrective retry failed before producing a valid contract response."
                    Signal   = $null
                    PlanPath = $validation.PlanPath
                }
                RetryAttempts = $attempts
                RetryResult   = $lastRetryResult
            }
        }

        $output = if ($lastRetryResult.Parsed -and $lastRetryResult.Parsed.Output) {
            $lastRetryResult.Parsed.Output
        }
        elseif ($lastRetryResult.NormalizedOutput) {
            $lastRetryResult.NormalizedOutput
        }
        else {
            $lastRetryResult.Output
        }
        $validation = Test-IterationContract -Mode $Mode -RunDir $RunDir -RequirementId $RequirementId -AgentOutput $output -PreviousPlanContent $PreviousPlanContent
    }

    return @{
        IsValid       = $validation.IsValid
        Output        = $output
        Validation    = $validation
        RetryAttempts = $attempts
        RetryResult   = $lastRetryResult
    }
}

function Write-ArtifactValidationFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunDir,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [int]$RetryAttempts = 0
    )

    $reportPath = Join-Path $RunDir "artifact-validation.md"
    $content = @"
# Artifact Validation Failed

**Timestamp:** $(Get-Date -Format "o")

## Reason

$Message

**Retry Attempts:** $RetryAttempts
"@

    Set-Content $reportPath $content -Encoding UTF8
    return $reportPath
}