# Unit tests for reviewing phase helpers and signals
$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$core = Join-Path (Split-Path $here -Parent) "core"

. (Join-Path $here "test-framework.ps1")
. (Join-Path $core "emit-event.ps1")
. (Join-Path $core "agent-adapters.ps1")
. (Join-Path $core "agent-state.ps1")
. (Join-Path $core "review.ps1")

Describe "Get-ReviewConfig / Test-ReviewEnabled" {
    It "defaults enabled to true" {
        $cfg = Get-ReviewConfig -Config $null
        Assert-True $cfg.enabled
        Assert-True (Test-ReviewEnabled -Config $null)
    }

    It "respects review.enabled false" {
        $config = [PSCustomObject]@{ review = [PSCustomObject]@{ enabled = $false } }
        $cfg = Get-ReviewConfig -Config $config
        Assert-False $cfg.enabled
        Assert-False (Test-ReviewEnabled -Config $config)
    }

    It "reports helpers available when review.ps1 is loaded" {
        Assert-True (Test-ReviewHelpersAvailable)
    }
}

Describe "Review completion signals" {
    It "detects REVIEW_COMPLETE promise" {
        $out = "notes`n<promise>REVIEW_COMPLETE</promise>`n"
        Assert-equal "REVIEW_COMPLETE" (Get-CompletionSignal -Output $out)
    }

    It "detects REVIEW_CHANGES_REQUESTED promise" {
        $out = "<promise>REVIEW_CHANGES_REQUESTED</promise>"
        Assert-equal "REVIEW_CHANGES_REQUESTED" (Get-CompletionSignal -Output $out)
    }

    It "sets NextMode for review signals" {
        $r1 = @{ IsComplete = $false; NextMode = $null }
        Set-CompletionResult -Result $r1 -Signal "REVIEW_COMPLETE"
        Assert-equal "complete" $r1.NextMode

        $r2 = @{ IsComplete = $false; NextMode = $null }
        Set-CompletionResult -Result $r2 -Signal "REVIEW_CHANGES_REQUESTED"
        Assert-equal "building" $r2.NextMode
    }
}

Describe "AgentState reviewing transitions" {
    It "allows Validating -> Reviewing -> Complete" {
        $s = [AgentState]::new("Building")
        $s.TransitionTo("Validating")
        $s.TransitionTo("Reviewing")
        Assert-equal "Reviewing" $s.Mode
        $s.TransitionTo("Complete")
        Assert-equal "Complete" $s.Mode
    }

    It "allows Reviewing -> Building for remediations" {
        $s = [AgentState]::new("Building")
        $s.TransitionTo("Validating")
        $s.TransitionTo("Reviewing")
        $s.TransitionTo("Building")
        Assert-equal "Building" $s.Mode
    }
}

Describe "Mode selector pending_review gate" {
    It "enters reviewing only when pending_review is set" {
        . (Join-Path $core "mode-selector.ps1")
        # Stub hooks used by mode selector
        if (-not (Get-Command Invoke-PluginHook -ErrorAction SilentlyContinue)) {
            function script:Invoke-PluginHook { param($HookName, $RunId, $HookData) return @{} }
        }
        if (-not (Get-Command Emit-Artifact -ErrorAction SilentlyContinue)) {
            function script:Emit-Artifact { }
        }
        if (-not (Get-Command Set-WorkflowStage -ErrorAction SilentlyContinue)) {
            function script:Set-WorkflowStage { }
        }

        $tmp = Join-Path $env:TEMP ("felix-mode-" + [guid]::NewGuid().ToString("n"))
        $runs = Join-Path $tmp "runs"
        $runDir = Join-Path $runs "S-0001-run"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        Set-Content (Join-Path $runDir "plan-S-0001.md") "# plan`n- [x] done" -Encoding UTF8

        $req = [PSCustomObject]@{ id = "S-0001" }
        $config = [PSCustomObject]@{ executor = [PSCustomObject]@{ default_mode = "planning" } }
        $agentState = [AgentState]::new("Building")

        $stateSticky = @{ pending_review = $false; last_mode = "reviewing" }
        $modeSticky = Get-ExecutionMode -CurrentRequirement $req -State $stateSticky -Config $config -RunsDir $runs -RunId "r1" -RunDir $runDir -AgentState $agentState
        Assert-equal "building" $modeSticky.Mode
        Assert-equal "building" $stateSticky.last_mode

        $agentState2 = [AgentState]::new("Building")
        $statePending = @{ pending_review = $true; last_mode = "reviewing" }
        $modePending = Get-ExecutionMode -CurrentRequirement $req -State $statePending -Config $config -RunsDir $runs -RunId "r2" -RunDir $runDir -AgentState $agentState2
        Assert-equal "reviewing" $modePending.Mode

        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "REVIEW signal requires durable learnings" {
    It "stays in reviewing when code-review.md is missing" {
        . (Join-Path $core "workflow.ps1") -ErrorAction SilentlyContinue
        . (Join-Path $core "requirements-utils.ps1")
        . (Join-Path $core "task-handler.ps1")

        $tmp = Join-Path $env:TEMP ("felix-rev-nolearn-" + [guid]::NewGuid().ToString("n"))
        $run = Join-Path $tmp "run"
        New-Item -ItemType Directory -Path $run -Force | Out-Null
        $reqFile = Join-Path $tmp "requirements.json"
        '{"requirements":[{"id":"S-0001","title":"t","status":"in-progress"}]}' | Set-Content $reqFile -Encoding UTF8

        $state = @{ pending_review = $true; last_mode = "reviewing"; status = "running" }
        $agentState = [AgentState]::new("Reviewing")
        $req = [PSCustomObject]@{ id = "S-0001" }

        $result = Invoke-CompletionSignals `
            -AgentOutput "<promise>REVIEW_COMPLETE</promise>" `
            -Mode "reviewing" `
            -CurrentRequirement $req `
            -State $state `
            -AgentState $agentState `
            -RequirementsFile $reqFile `
            -Config ([PSCustomObject]@{ review = [PSCustomObject]@{ enabled = $true } }) `
            -RunDir $run `
            -Paths @{ ProjectPath = $tmp }

        Assert-False $result.ShouldExit
        Assert-True ([bool]$state.pending_review)
        Assert-equal "reviewing" $state.last_mode
        $reqs = Get-Content $reqFile -Raw | ConvertFrom-Json
        Assert-equal "in-progress" $reqs.requirements[0].status

        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "ALL_COMPLETE fail-closed without review helpers" {
    It "stays in building and does not complete when helpers are missing" {
        . (Join-Path $core "workflow.ps1") -ErrorAction SilentlyContinue
        . (Join-Path $core "requirements-utils.ps1")
        . (Join-Path $core "task-handler.ps1")

        # Remove review helpers to simulate missing review.ps1
        Remove-Item Function:\Test-ReviewEnabled -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-ReviewConfig -ErrorAction SilentlyContinue
        Remove-Item Function:\Test-ReviewHelpersAvailable -ErrorAction SilentlyContinue

        $tmp = Join-Path $env:TEMP ("felix-failclosed-" + [guid]::NewGuid().ToString("n"))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $reqFile = Join-Path $tmp "requirements.json"
        '{"requirements":[{"id":"S-0001","title":"t","status":"in-progress"}]}' | Set-Content $reqFile -Encoding UTF8

        $state = @{ pending_review = $false; last_mode = "building"; status = "running" }
        $agentState = [AgentState]::new("Building")
        $req = [PSCustomObject]@{ id = "S-0001" }

        $result = Invoke-CompletionSignals `
            -AgentOutput "<promise>ALL_COMPLETE</promise>" `
            -Mode "building" `
            -CurrentRequirement $req `
            -State $state `
            -AgentState $agentState `
            -RequirementsFile $reqFile `
            -Config ([PSCustomObject]@{ review = [PSCustomObject]@{ enabled = $true } }) `
            -RunDir $tmp `
            -Paths @{ ProjectPath = $tmp; AgentsFile = (Join-Path $tmp "AGENTS.md") }

        Assert-False $result.ShouldExit
        Assert-equal "building" $state.last_mode
        Assert-False ([bool]$state.pending_review)
        $reqs = Get-Content $reqFile -Raw | ConvertFrom-Json
        Assert-equal "in-progress" $reqs.requirements[0].status

        # Restore helpers for later tests
        . (Join-Path $core "review.ps1")
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Review artifact contract" {
    It "does not infer REVIEW_COMPLETE from leftover code-review.md" {
        . (Join-Path $core "artifact-validator.ps1")
        $tmp = Join-Path $env:TEMP ("felix-review-contract-" + [guid]::NewGuid().ToString("n"))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            Set-Content (Join-Path $tmp "code-review.md") "# leftover" -Encoding UTF8
            $result = Test-IterationContract `
                -Mode "reviewing" `
                -RunDir $tmp `
                -RequirementId "S-0001" `
                -AgentOutput "I wrote some notes but forgot the promise."
            Assert-False $result.IsValid
            Assert-True ($result.Reason -match "REVIEW_COMPLETE|REVIEW_CHANGES_REQUESTED")
        }
        finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Write-RequirementReviewLearning" {
    It "writes a requirement-scoped memory file" {
        $tmp = Join-Path $env:TEMP ("felix-review-test-" + [guid]::NewGuid().ToString("n"))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            $path = Write-RequirementReviewLearning `
                -FelixDir $tmp `
                -RequirementId "S-0009" `
                -ReviewContent "## Findings`nLooks deep enough." `
                -Signal "REVIEW_COMPLETE"
            Assert-True (Test-Path $path)
            $text = Get-Content $path -Raw
            Assert-True ($text -match "scope: requirement")
            Assert-True ($text -match "Looks deep enough")
            Assert-True ($text -match "S-0009")
        }
        finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "rejects empty review content" {
        $tmp = Join-Path $env:TEMP ("felix-review-empty-" + [guid]::NewGuid().ToString("n"))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            $threw = $false
            try {
                Write-RequirementReviewLearning -FelixDir $tmp -RequirementId "S-0009" -ReviewContent "   " -Signal "REVIEW_COMPLETE" | Out-Null
            }
            catch { $threw = $true }
            Assert-True $threw
        }
        finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-PreReviewValidationAvailable" {
    It "is false when backpressure off and no validate script" {
        $tmp = Join-Path $env:TEMP ("felix-gate-none-" + [guid]::NewGuid().ToString("n"))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            $config = [PSCustomObject]@{ backpressure = [PSCustomObject]@{ enabled = $false } }
            $paths = @{ ProjectPath = $tmp }
            Assert-False (Test-PreReviewValidationAvailable -Config $config -Paths $paths)
        }
        finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "is false when backpressure enabled but Paths.ProjectPath is missing" {
        if (-not (Get-Command Invoke-BackpressureValidation -ErrorAction SilentlyContinue)) {
            function script:Invoke-BackpressureValidation { return @{ success = $true; skipped = $false } }
        }
        $config = [PSCustomObject]@{ backpressure = [PSCustomObject]@{ enabled = $true } }
        Assert-False (Test-PreReviewValidationAvailable -Config $config -Paths $null)
        Assert-False (Test-PreReviewValidationAvailable -Config $config -Paths @{ ProjectPath = "" })
    }

    It "is true when validate-requirement.ps1 exists" {
        $tmp = Join-Path $env:TEMP ("felix-gate-ps1-" + [guid]::NewGuid().ToString("n"))
        $scripts = Join-Path $tmp "scripts"
        New-Item -ItemType Directory -Path $scripts -Force | Out-Null
        Set-Content (Join-Path $scripts "validate-requirement.ps1") "# stub" -Encoding UTF8
        try {
            $config = [PSCustomObject]@{ backpressure = [PSCustomObject]@{ enabled = $false } }
            $paths = @{ ProjectPath = $tmp }
            Assert-True (Test-PreReviewValidationAvailable -Config $config -Paths $paths)
        }
        finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "is true when backpressure enabled, helper loaded, and project path exists" {
        if (-not (Get-Command Invoke-BackpressureValidation -ErrorAction SilentlyContinue)) {
            function script:Invoke-BackpressureValidation { return @{ success = $true; skipped = $false } }
        }
        $config = [PSCustomObject]@{ backpressure = [PSCustomObject]@{ enabled = $true } }
        Assert-True (Test-PreReviewValidationAvailable -Config $config -Paths @{ ProjectPath = $env:TEMP })
    }
}

Describe "ALL_COMPLETE rejects vacuous skipped backpressure" {
    It "does not schedule review when backpressure is skipped and no validate script ran" {
        . (Join-Path $core "review.ps1")
        . (Join-Path $core "workflow.ps1") -ErrorAction SilentlyContinue
        . (Join-Path $core "requirements-utils.ps1")
        . (Join-Path $core "task-handler.ps1")
        Assert-True (Test-ReviewHelpersAvailable) "review helpers must be loaded for this test"

        function script:Invoke-BackpressureValidation {
            param($WorkingDir, $AgentsFilePath, $Config, $RunDir)
            return @{ success = $true; skipped = $true; failed_commands = @(); output = "" }
        }
        function script:Set-WorkflowStage { }

        $tmp = Join-Path $env:TEMP ("felix-vacuous-" + [guid]::NewGuid().ToString("n"))
        $run = Join-Path $tmp "run"
        New-Item -ItemType Directory -Path $run -Force | Out-Null
        $reqFile = Join-Path $tmp "requirements.json"
        $stateFile = Join-Path $tmp "state.json"
        '{"requirements":[{"id":"S-0001","title":"t","status":"in-progress"}]}' | Set-Content $reqFile -Encoding UTF8
        '{"status":"running"}' | Set-Content $stateFile -Encoding UTF8

        $state = @{ pending_review = $false; last_mode = "building"; status = "running"; current_iteration = 1 }
        $agentState = [AgentState]::new("Building")
        $req = [PSCustomObject]@{ id = "S-0001" }
        $config = [PSCustomObject]@{
            review       = [PSCustomObject]@{ enabled = $true }
            backpressure = [PSCustomObject]@{ enabled = $true; max_retries = 3 }
        }
        $paths = @{
            ProjectPath      = $tmp
            AgentsFile       = (Join-Path $tmp "AGENTS.md")
            RequirementsFile = $reqFile
            StateFile        = $stateFile
        }

        $result = Invoke-CompletionSignals `
            -AgentOutput "<promise>ALL_COMPLETE</promise>" `
            -Mode "building" `
            -CurrentRequirement $req `
            -State $state `
            -AgentState $agentState `
            -RequirementsFile $reqFile `
            -Config $config `
            -RunDir $run `
            -Paths $paths

        Assert-False $result.ShouldExit
        Assert-False ([bool]$state.pending_review)
        Assert-equal "building" $state.last_mode
        Assert-True ($null -ne $state.blocked_task)

        Remove-Item Function:\Invoke-BackpressureValidation -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-BackpressureFailure -ErrorAction SilentlyContinue
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Save-ReviewLearningsFromRun" {
    It "fails when code-review.md is missing" {
        $tmp = Join-Path $env:TEMP ("felix-learn-miss-" + [guid]::NewGuid().ToString("n"))
        $run = Join-Path $tmp "run"
        New-Item -ItemType Directory -Path $run -Force | Out-Null
        try {
            $result = Save-ReviewLearningsFromRun -RunDir $run -FelixDir $tmp -RequirementId "S-0001" -Signal "REVIEW_COMPLETE"
            Assert-False $result.Ok
            Assert-True ($result.Reason -match "code-review.md")
        }
        finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "writes memory when code-review.md is present" {
        $tmp = Join-Path $env:TEMP ("felix-learn-ok-" + [guid]::NewGuid().ToString("n"))
        $run = Join-Path $tmp "run"
        New-Item -ItemType Directory -Path $run -Force | Out-Null
        Set-Content (Join-Path $run "code-review.md") "## Summary`nNeeds a smaller interface." -Encoding UTF8
        try {
            $result = Save-ReviewLearningsFromRun -RunDir $run -FelixDir $tmp -RequirementId "S-0001" -Signal "REVIEW_CHANGES_REQUESTED"
            Assert-True $result.Ok
            Assert-True (Test-Path $result.MemoryPath)
            Assert-True ((Get-Content $result.MemoryPath -Raw) -match "smaller interface")
        }
        finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
