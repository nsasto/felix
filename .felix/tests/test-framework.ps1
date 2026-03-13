<#
.SYNOPSIS
Lightweight test framework for PowerShell 5.1+ compatibility
#>

$Global:TestResults = @{
    Passed  = 0
    Failed  = 0
    Skipped = 0
    Tests   = @()
}

function Describe {
    param([string]$Name, [scriptblock]$Tests)

    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    & $Tests
}

function It {
    param([string]$Description, [scriptblock]$Test)

    Write-Host "  Testing: $Description" -NoNewline

    try {
        & $Test
        Write-Host " [PASS]" -ForegroundColor Green
        $Global:TestResults.Passed++
        $Global:TestResults.Tests += @{
            description = $Description
            status      = "PASS"
            error       = $null
        }
    }
    catch {
        Write-Host " [FAIL]" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        $Global:TestResults.Failed++
        $Global:TestResults.Tests += @{
            description = $Description
            status      = "FAIL"
            error       = $_.Exception.Message
        }
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message = "")
    if ($Expected -ne $Actual) {
        throw "Expected '$Expected' but got '$Actual'. $Message"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message = "")
    if (-not $Condition) {
        throw "Condition is false. $Message"
    }
}

function Assert-False {
    param([bool]$Condition, [string]$Message = "")
    if ($Condition) {
        throw "Condition is true (expected false). $Message"
    }
}

function Assert-NotNull {
    param($Value, [string]$Message = "")
    if ($null -eq $Value) {
        throw "Value is null. $Message"
    }
}

function Assert-Null {
    param($Value, [string]$Message = "")
    if ($null -ne $Value) {
        throw "Value is not null (expected null). $Message"
    }
}

function Assert-Throws {
    param([scriptblock]$ScriptBlock, [string]$Message = "")
    try {
        & $ScriptBlock
        throw "Expected exception but none was thrown. $Message"
    }
    catch {
        # Expected - test passes
    }
}

function Assert-Contains {
    param($Collection, $Item, [string]$Message = "")
    if ($Collection -notcontains $Item) {
        throw "Collection does not contain '$Item'. $Message"
    }
}

function Assert-FileExists {
    param([string]$Path, [string]$Message = "")
    if (-not (Test-Path $Path)) {
        throw "File does not exist: $Path. $Message"
    }
}

function Get-TestResults {
    $total = $Global:TestResults.Passed + $Global:TestResults.Failed + $Global:TestResults.Skipped

    Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
    Write-Host "Total:   $total" -ForegroundColor White
    Write-Host "Passed:  $($Global:TestResults.Passed)" -ForegroundColor Green
    Write-Host "Failed:  $($Global:TestResults.Failed)" -ForegroundColor Red
    Write-Host "Skipped: $($Global:TestResults.Skipped)" -ForegroundColor Yellow

    $successRate = if ($total -gt 0) {
        [math]::Round(($Global:TestResults.Passed / $total) * 100, 2)
    }
    else {
        0
    }
    Write-Host "Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } else { "Red" })

    return ($Global:TestResults.Failed -eq 0)
}

try {
    Export-ModuleMember -Function Describe, It, Assert-*, Get-TestResults
}
catch {
    # Allow dot-sourcing this file in scripts (Export-ModuleMember only works inside modules).
}

