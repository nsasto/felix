# ═══════════════════════════════════════════════════════════════════════════
# Felix Plugin Hook Contracts
# ═══════════════════════════════════════════════════════════════════════════
# This file defines type-safe parameter and result classes for plugin hooks.
# Plugins should follow these contracts to ensure compatibility with Felix.

# Hook: OnPreIteration
# Executed before each iteration starts
class OnPreIterationParams {
    [int]$Iteration
    [int]$MaxIterations
    [string]$RunId
    [hashtable]$CurrentRequirement
    [hashtable]$State
    
    OnPreIterationParams([int]$iteration, [int]$maxIterations, [string]$runId, [hashtable]$requirement, [hashtable]$state) {
        $this.Iteration = $iteration
        $this.MaxIterations = $maxIterations
        $this.RunId = $runId
        $this.CurrentRequirement = $requirement
        $this.State = $state
    }
}

class OnPreIterationResult {
    [bool]$ContinueIteration = $true
    [string]$Reason
    [hashtable]$UpdatedState
    
    OnPreIterationResult() {
        $this.ContinueIteration = $true
    }
}

# Hook: OnPostModeSelection
# Executed after mode (planning/building) is determined
class OnPostModeSelectionParams {
    [string]$Mode
    [string]$RunId
    [hashtable]$CurrentRequirement
    [string]$PlanPath
    
    OnPostModeSelectionParams([string]$mode, [string]$runId, [hashtable]$requirement, [string]$planPath) {
        $this.Mode = $mode
        $this.RunId = $runId
        $this.CurrentRequirement = $requirement
        $this.PlanPath = $planPath
    }
}

class OnPostModeSelectionResult {
    [string]$OverrideMode
    [string]$Reason
    
    OnPostModeSelectionResult() {
    }
}

# Hook: OnContextGathering
# Executed during context gathering phase
class OnContextGatheringParams {
    [string]$Mode
    [string]$RunId
    [hashtable]$CurrentRequirement
    [string]$GitDiff
    [string]$PlanContent
    [System.Collections.ArrayList]$ContextFiles
    
    OnContextGatheringParams([string]$mode, [string]$runId, [hashtable]$requirement, [string]$gitDiff, [string]$planContent, [System.Collections.ArrayList]$files) {
        $this.Mode = $mode
        $this.RunId = $runId
        $this.CurrentRequirement = $requirement
        $this.GitDiff = $gitDiff
        $this.PlanContent = $planContent
        $this.ContextFiles = $files
    }
}

class OnContextGatheringResult {
    [System.Collections.ArrayList]$AdditionalFiles
    [string]$AdditionalContext
    
    OnContextGatheringResult() {
        $this.AdditionalFiles = [System.Collections.ArrayList]::new()
    }
}

# Hook: OnPreLLM
# Executed before LLM execution
class OnPreLLMParams {
    [string]$Mode
    [string]$RunId
    [hashtable]$CurrentRequirement
    [string]$PromptFile
    [string]$FullPrompt
    
    OnPreLLMParams([string]$mode, [string]$runId, [hashtable]$requirement, [string]$promptFile, [string]$fullPrompt) {
        $this.Mode = $mode
        $this.RunId = $runId
        $this.CurrentRequirement = $requirement
        $this.PromptFile = $promptFile
        $this.FullPrompt = $fullPrompt
    }
}

class OnPreLLMResult {
    [string]$ModifiedPrompt
    [bool]$SkipLLM = $false
    [string]$Reason
    
    OnPreLLMResult() {
    }
}

# Hook: OnPostLLM
# Executed after LLM execution completes
class OnPostLLMParams {
    [string]$Mode
    [string]$RunId
    [hashtable]$CurrentRequirement
    [int]$ExitCode
    [string]$OutputPath
    
    OnPostLLMParams([string]$mode, [string]$runId, [hashtable]$requirement, [int]$exitCode, [string]$outputPath) {
        $this.Mode = $mode
        $this.RunId = $runId
        $this.CurrentRequirement = $requirement
        $this.ExitCode = $exitCode
        $this.OutputPath = $outputPath
    }
}

class OnPostLLMResult {
    [bool]$Success = $true
    [string]$ErrorMessage
    [hashtable]$Metadata
    
    OnPostLLMResult() {
        $this.Success = $true
        $this.Metadata = @{}
    }
}

# Hook: OnGuardrailCheck
# Executed during guardrail validation (planning mode only)
class OnGuardrailCheckParams {
    [string]$Mode
    [string]$RunId
    [hashtable]$CurrentRequirement
    [bool]$GuardrailsPassed
    [System.Collections.ArrayList]$FailedChecks
    
    OnGuardrailCheckParams([string]$mode, [string]$runId, [hashtable]$requirement, [bool]$passed, [System.Collections.ArrayList]$failed) {
        $this.Mode = $mode
        $this.RunId = $runId
        $this.CurrentRequirement = $requirement
        $this.GuardrailsPassed = $passed
        $this.FailedChecks = $failed
    }
}

class OnGuardrailCheckResult {
    [bool]$OverrideResult
    [string]$Reason
    
    OnGuardrailCheckResult() {
    }
}

# Hook: OnPreBackpressure
# Executed before backpressure validation runs
class OnPreBackpressureParams {
    [string]$RunId
    [hashtable]$CurrentRequirement
    [System.Collections.ArrayList]$Commands
    
    OnPreBackpressureParams([string]$runId, [hashtable]$requirement, [System.Collections.ArrayList]$commands) {
        $this.RunId = $runId
        $this.CurrentRequirement = $requirement
        $this.Commands = $commands
    }
}

class OnPreBackpressureResult {
    [System.Collections.ArrayList]$AdditionalCommands
    [bool]$SkipBackpressure = $false
    [string]$Reason
    
    OnPreBackpressureResult() {
        $this.AdditionalCommands = [System.Collections.ArrayList]::new()
    }
}

# Hook: OnBackpressureFailed
# Executed when backpressure validation fails
class OnBackpressureFailedParams {
    [string]$RunId
    [hashtable]$CurrentRequirement
    [hashtable]$ValidationResult
    [int]$RetryCount
    
    OnBackpressureFailedParams([string]$runId, [hashtable]$requirement, [hashtable]$result, [int]$retryCount) {
        $this.RunId = $runId
        $this.CurrentRequirement = $requirement
        $this.ValidationResult = $result
        $this.RetryCount = $retryCount
    }
}

class OnBackpressureFailedResult {
    [bool]$ShouldRetry = $false
    [string]$Reason
    [hashtable]$SuggestedFix
    
    OnBackpressureFailedResult() {
        $this.SuggestedFix = @{}
    }
}

# Hook: OnPreCommit
# Executed before git commit
class OnPreCommitParams {
    [string]$RunId
    [hashtable]$CurrentRequirement
    [string]$CommitMessage
    [System.Collections.ArrayList]$StagedFiles
    
    OnPreCommitParams([string]$runId, [hashtable]$requirement, [string]$commitMessage, [System.Collections.ArrayList]$files) {
        $this.RunId = $runId
        $this.CurrentRequirement = $requirement
        $this.CommitMessage = $commitMessage
        $this.StagedFiles = $files
    }
}

class OnPreCommitResult {
    [string]$ModifiedCommitMessage
    [bool]$SkipCommit = $false
    [string]$Reason
    
    OnPreCommitResult() {
    }
}

# Hook: OnPostValidation
# Executed after validation completes
class OnPostValidationParams {
    [string]$RunId
    [hashtable]$CurrentRequirement
    [bool]$ValidationPassed
    [string]$ValidationOutput
    
    OnPostValidationParams([string]$runId, [hashtable]$requirement, [bool]$passed, [string]$output) {
        $this.RunId = $runId
        $this.CurrentRequirement = $requirement
        $this.ValidationPassed = $passed
        $this.ValidationOutput = $output
    }
}

class OnPostValidationResult {
    [bool]$OverrideResult
    [string]$Reason
    [hashtable]$Metadata
    
    OnPostValidationResult() {
        $this.Metadata = @{}
    }
}

# Hook: OnPostIteration
# Executed after iteration completes
class OnPostIterationParams {
    [int]$Iteration
    [int]$MaxIterations
    [string]$RunId
    [hashtable]$CurrentRequirement
    [string]$Outcome
    [hashtable]$State
    
    OnPostIterationParams([int]$iteration, [int]$maxIterations, [string]$runId, [hashtable]$requirement, [string]$outcome, [hashtable]$state) {
        $this.Iteration = $iteration
        $this.MaxIterations = $maxIterations
        $this.RunId = $runId
        $this.CurrentRequirement = $requirement
        $this.Outcome = $outcome
        $this.State = $state
    }
}

class OnPostIterationResult {
    [bool]$ShouldContinue = $true
    [string]$Reason
    [hashtable]$UpdatedState
    
    OnPostIterationResult() {
        $this.ShouldContinue = $true
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Hook Contract Validation Functions
# ═══════════════════════════════════════════════════════════════════════════

function Test-HookContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HookName,
        
        [Parameter(Mandatory = $true)]
        $Result
    )
    
    $expectedType = switch ($HookName) {
        "OnPreIteration" { [OnPreIterationResult] }
        "OnPostModeSelection" { [OnPostModeSelectionResult] }
        "OnContextGathering" { [OnContextGatheringResult] }
        "OnPreLLM" { [OnPreLLMResult] }
        "OnPostLLM" { [OnPostLLMResult] }
        "OnGuardrailCheck" { [OnGuardrailCheckResult] }
        "OnPreBackpressure" { [OnPreBackpressureResult] }
        "OnBackpressureFailed" { [OnBackpressureFailedResult] }
        "OnPreCommit" { [OnPreCommitResult] }
        "OnPostValidation" { [OnPostValidationResult] }
        "OnPostIteration" { [OnPostIterationResult] }
        default { $null }
    }
    
    if ($null -eq $expectedType) {
        Write-Warning "Unknown hook: $HookName"
        return $false
    }
    
    # For v1 API, accept hashtables (not strongly typed)
    # For v2 API, enforce class types
    if ($Result -isnot $expectedType -and $Result -isnot [hashtable]) {
        Write-Warning "Hook $HookName returned invalid type. Expected: $expectedType or hashtable, Got: $($Result.GetType())"
        return $false
    }
    
    return $true
}

# Export classes for plugin use
Export-ModuleMember -Function Test-HookContract
