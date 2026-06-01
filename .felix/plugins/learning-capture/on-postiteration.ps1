<#
.SYNOPSIS
OnPostIteration hook: draft agents-md-suggestions.md for human review (Phase E1).

.DESCRIPTION
Reads events from the Event Bus for the current run, identifies failure and success
signals, and writes a proposals file into runs/<run-id>/agents-md-suggestions.md.
Never auto-applies anything. Always requires human review via 'felix review --learnings'.

Disabled via learning.auto_propose: false in .felix/config.json.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$HookName,

    [Parameter(Mandatory = $true)]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [hashtable]$Data,

    [Parameter(Mandatory = $false)]
    $Config = @{}
)

. "$PSScriptRoot\..\..\core\event-reader.ps1"

# Respect learning.auto_propose: false in config
$autoPropose = $true
if ($Config -and $Config.PSObject -and $Config.learning) {
    if ($Config.learning.PSObject -and $null -ne $Config.learning.auto_propose) {
        $autoPropose = [bool]$Config.learning.auto_propose
    }
}
if (-not $autoPropose) {
    return @{ ShouldContinue = $true }
}

# Also check plugin-level config passed through Data
if ($Data.PluginConfig -and $null -ne $Data.PluginConfig.auto_propose) {
    $autoPropose = [bool]$Data.PluginConfig.auto_propose
    if (-not $autoPropose) {
        return @{ ShouldContinue = $true }
    }
}

try {
    # Locate .felix dir and run dir
    $felixDir = if ($Data.Paths -and $Data.Paths.FelixDir) {
        $Data.Paths.FelixDir
    } elseif ($Data.FelixDir) {
        $Data.FelixDir
    } else {
        $null
    }

    $runDir = if ($Data.RunDir) {
        $Data.RunDir
    } elseif ($Data.Paths -and $Data.Paths.RunsDir -and $RunId) {
        Join-Path $Data.Paths.RunsDir $RunId
    } else {
        $null
    }

    if (-not $felixDir -or -not (Test-Path $felixDir)) {
        return @{ ShouldContinue = $true }
    }

    if (-not $runDir -or -not (Test-Path $runDir)) {
        return @{ ShouldContinue = $true }
    }

    # Read events for this run
    $allEvents = Get-RunEvents -FelixDir $felixDir -RunId $RunId

    # Categorise events
    $failureKinds = @("backpressure.fail", "validation.fail", "iteration.error", "error",
                      "BackpressureFailed", "ValidationFailed", "IterationError", "Error")
    $successKinds = @("requirement.complete", "RequirementComplete", "IterationCompleted")

    $failEvents   = [System.Collections.ArrayList]@()
    $successEvents = [System.Collections.ArrayList]@()

    foreach ($evt in $allEvents) {
        $kind = if ($evt.kind) { $evt.kind } elseif ($evt.type) { $evt.type } else { "" }
        $outcome = if ($evt.outcome) { $evt.outcome } else { "" }

        $isFail = $false
        foreach ($fk in $failureKinds) {
            if ($kind -ieq $fk) { $isFail = $true; break }
        }
        # Also treat IterationCompleted with outcome=failure as a failure event
        if (-not $isFail -and $outcome -ieq "failure") { $isFail = $true }

        $isSuccess = $false
        foreach ($sk in $successKinds) {
            if ($kind -ieq $sk) { $isSuccess = $true; break }
        }
        if (-not $isSuccess -and $outcome -ieq "success") { $isSuccess = $true }

        if ($isFail)   { [void]$failEvents.Add($evt) }
        if ($isSuccess){ [void]$successEvents.Add($evt) }
    }

    # Determine requirement ID and iteration from RunId (format: S-NNNN-YYYYMMDD-HHMMSS-itN)
    $reqId = if ($RunId -match "^([A-Za-z0-9]+-\d+)-") { $Matches[1] } else { $RunId }
    $iterNum = if ($RunId -match "-it(\d+)$") { $Matches[1] } else { "?" }

    # Build proposals
    $agentsMdAdditions = [System.Collections.ArrayList]@()
    $memoryEntries     = [System.Collections.ArrayList]@()
    $promptEdits       = [System.Collections.ArrayList]@()

    foreach ($evt in ($failEvents | Select-Object -First 3)) {
        $kind = if ($evt.kind) { $evt.kind } elseif ($evt.type) { $evt.type } else { "unknown" }
        $msg  = if ($evt.message) { $evt.message } elseif ($evt.Message) { $evt.Message } else { "" }

        switch -Wildcard ($kind) {
            "*backpressure*" {
                $cmd = if ($evt.context -and $evt.context.command) { $evt.context.command } else { $msg }
                if ($cmd) {
                    [void]$agentsMdAdditions.Add("- Run ``$cmd`` before committing to surface failures early")
                }
            }
            "*validation*" {
                $reason = if ($evt.context -and $evt.context.signal) { $evt.context.signal } else { $msg }
                if ($reason) {
                    [void]$agentsMdAdditions.Add("- Validation failed with: $reason -- check artifact contract before submitting")
                }
            }
            default {
                if ($msg) {
                    [void]$agentsMdAdditions.Add("- Iteration error: $msg")
                }
            }
        }
    }

    # Memory proposals from failure events
    foreach ($evt in ($failEvents | Select-Object -First 2)) {
        $msg = if ($evt.message) { $evt.message } elseif ($evt.Message) { $evt.Message } else { "" }
        if ($msg) {
            $date = (Get-Date).ToString("yyyy-MM-dd")
            [void]$memoryEntries.Add("- [repo] $date -- $msg")
        }
    }

    # What-worked entries from success events
    foreach ($evt in ($successEvents | Select-Object -First 1)) {
        $kind = if ($evt.kind) { $evt.kind } elseif ($evt.type) { $evt.type } else { "" }
        if ($kind -imatch "complete") {
            [void]$memoryEntries.Add("- [repo] Requirement $reqId completed successfully in iteration $iterNum")
        }
    }

    # Prompt edit suggestions based on failure patterns
    if ($failEvents.Count -gt 0) {
        [void]$promptEdits.Add("- Review planning.md for rules that may fire unnecessarily on clean iterations")
    }

    # Only write file if we have something to propose
    if ($agentsMdAdditions.Count -eq 0 -and $memoryEntries.Count -eq 0 -and $promptEdits.Count -eq 0) {
        return @{ ShouldContinue = $true }
    }

    # Build document
    $lines = [System.Collections.ArrayList]@()
    [void]$lines.Add("# Suggestions from $reqId it$iterNum")
    [void]$lines.Add("")

    if ($agentsMdAdditions.Count -gt 0) {
        [void]$lines.Add("## Proposed AGENTS.md additions")
        [void]$lines.Add("")
        foreach ($item in $agentsMdAdditions) { [void]$lines.Add($item) }
        [void]$lines.Add("")
    }

    if ($memoryEntries.Count -gt 0) {
        [void]$lines.Add("## Proposed memory entries")
        [void]$lines.Add("")
        foreach ($item in $memoryEntries) { [void]$lines.Add($item) }
        [void]$lines.Add("")
    }

    if ($promptEdits.Count -gt 0) {
        [void]$lines.Add("## Proposed prompt edits")
        [void]$lines.Add("")
        foreach ($item in $promptEdits) { [void]$lines.Add($item) }
        [void]$lines.Add("")
    }

    $content = $lines -join "`n"
    $outPath  = Join-Path $runDir "agents-md-suggestions.md"
    [System.IO.File]::WriteAllText($outPath, $content, [System.Text.Encoding]::UTF8)
}
catch {
    # Silent failure - hooks must never break agent execution
}

return @{ ShouldContinue = $true }
