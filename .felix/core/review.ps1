<#
.SYNOPSIS
Architecture review phase helpers for Felix.

.DESCRIPTION
After build validation passes, an optional reviewing iteration assesses the
change against simplicity/modularity (deep-module) principles, writes
remediation suggestions, and records requirement-scoped learnings.
#>

function Get-ReviewConfig {
    param($Config)

    $defaults = @{
        enabled = $true
    }

    if (-not $Config) { return $defaults }

    $section = if ($Config -is [hashtable]) { $Config["review"] } else { $Config.review }
    if (-not $section) { return $defaults }

    $enabled = $defaults.enabled
    if ($section -is [hashtable]) {
        if ($null -ne $section["enabled"]) { $enabled = [bool]$section["enabled"] }
    }
    else {
        if ($null -ne $section.enabled) { $enabled = [bool]$section.enabled }
    }

    return @{ enabled = $enabled }
}

function Test-ReviewEnabled {
    <#
    .SYNOPSIS
    Returns whether architecture review should run after ALL_COMPLETE.
    #>
    param($Config)

    $reviewConfig = Get-ReviewConfig -Config $Config
    return [bool]$reviewConfig.enabled
}

function Test-ReviewHelpersAvailable {
    <#
    .SYNOPSIS
    True when review.ps1 helpers are loaded (fail-closed gate for ALL_COMPLETE).
    #>
    return (
        [bool](Get-Command Test-ReviewEnabled -ErrorAction SilentlyContinue) -and
        [bool](Get-Command Get-ReviewConfig -ErrorAction SilentlyContinue) -and
        [bool](Get-Command Save-ReviewLearningsFromRun -ErrorAction SilentlyContinue) -and
        [bool](Get-Command Write-RequirementReviewLearning -ErrorAction SilentlyContinue)
    )
}

function Write-RequirementReviewLearning {
    <#
    .SYNOPSIS
    Writes a requirement-scoped memory file from a review artifact.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FelixDir,

        [Parameter(Mandatory = $true)]
        [string]$RequirementId,

        [Parameter(Mandatory = $true)]
        [string]$ReviewContent,

        [Parameter(Mandatory = $false)]
        [string]$Signal = "REVIEW_COMPLETE"
    )

    if ([string]::IsNullOrWhiteSpace($ReviewContent)) {
        throw "Review content is empty; refusing to write requirement learning."
    }

    $reqMemDir = Join-Path $FelixDir "memory\requirement\$RequirementId"
    if (-not (Test-Path $reqMemDir)) {
        New-Item -ItemType Directory -Path $reqMemDir -Force | Out-Null
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $fileName = "review-$stamp.md"
    $path = Join-Path $reqMemDir $fileName
    $created = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")

    $body = @"
---
title: Architecture review for $RequirementId
scope: requirement
created: $created
tags: [review, architecture, $Signal]
---

# Architecture review - $RequirementId

_Auto-written by Felix reviewing phase ($Signal)._

$ReviewContent
"@

    Set-Content -Path $path -Value $body -Encoding UTF8
    if (-not (Test-Path $path)) {
        throw "Failed to create requirement learning file: $path"
    }
    return $path
}

function Test-PreReviewValidationAvailable {
    <#
    .SYNOPSIS
    True when at least one real validation gate can run before reviewing.
    #>
    param(
        $Config,
        [hashtable]$Paths = $null
    )

    $backpressureWanted = $false
    if ($Config -and $Config.backpressure) {
        $bpSection = $Config.backpressure
        if ($bpSection -is [hashtable]) {
            $backpressureWanted = [bool]$bpSection["enabled"]
        }
        else {
            $backpressureWanted = [bool]$bpSection.enabled
        }
    }

    if ($backpressureWanted -and (Get-Command Invoke-BackpressureValidation -ErrorAction SilentlyContinue)) {
        return $true
    }

    if ($Paths -and $Paths.ProjectPath) {
        $root = $Paths.ProjectPath
        if (Test-Path (Join-Path $root "scripts\validate-requirement.ps1")) { return $true }
        if (Test-Path (Join-Path $root "scripts\validate-requirement.py")) { return $true }
    }

    return $false
}

function Save-ReviewLearningsFromRun {
    <#
    .SYNOPSIS
    Requires runs/<run-id>/code-review.md and writes requirement-scoped learnings.

    .OUTPUTS
    Hashtable: Ok (bool), Reason (string), ReviewPath, MemoryPath
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RunDir,

        [Parameter(Mandatory = $true)]
        [string]$FelixDir,

        [Parameter(Mandatory = $true)]
        [string]$RequirementId,

        [Parameter(Mandatory = $true)]
        [string]$Signal
    )

    if ([string]::IsNullOrWhiteSpace($RunDir) -or -not (Test-Path $RunDir)) {
        return @{ Ok = $false; Reason = "RunDir missing for review learnings."; ReviewPath = $null; MemoryPath = $null }
    }

    $reviewPath = Join-Path $RunDir "code-review.md"
    if (-not (Test-Path $reviewPath)) {
        return @{
            Ok         = $false
            Reason     = "Review signal requires code-review.md at $reviewPath."
            ReviewPath = $reviewPath
            MemoryPath = $null
        }
    }

    if (-not (Get-Command Write-RequirementReviewLearning -ErrorAction SilentlyContinue)) {
        return @{
            Ok         = $false
            Reason     = "Write-RequirementReviewLearning is not loaded."
            ReviewPath = $reviewPath
            MemoryPath = $null
        }
    }

    try {
        $reviewBody = Get-Content $reviewPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($reviewBody)) {
            return @{
                Ok         = $false
                Reason     = "code-review.md is empty."
                ReviewPath = $reviewPath
                MemoryPath = $null
            }
        }

        $memPath = Write-RequirementReviewLearning `
            -FelixDir $FelixDir `
            -RequirementId $RequirementId `
            -ReviewContent $reviewBody `
            -Signal $Signal

        return @{
            Ok         = $true
            Reason     = $null
            ReviewPath = $reviewPath
            MemoryPath = $memPath
        }
    }
    catch {
        return @{
            Ok         = $false
            Reason     = "Failed to write requirement learning: $_"
            ReviewPath = $reviewPath
            MemoryPath = $null
        }
    }
}
