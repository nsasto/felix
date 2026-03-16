<#
.SYNOPSIS
Tests for emit-event.ps1 NDJSON event system
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"

# Helper: capture [Console]::WriteLine output via subprocess writing to temp file
function Invoke-EmitCapture {
    param([string]$ScriptBlock)
    $tempFile = Join-Path $env:TEMP "emit-test-$(Get-Random).txt"
    $scriptPath = Join-Path $env:TEMP "emit-test-$(Get-Random).ps1"
    try {
        # Write a script that sources emit-event and runs the block, redirecting stdout to file
        @"
. '$PSScriptRoot/../core/emit-event.ps1'
$ScriptBlock
"@ | Set-Content $scriptPath -Encoding UTF8
        & powershell.exe -NoProfile -File $scriptPath > $tempFile 2>&1
        if (Test-Path $tempFile) {
            $raw = Get-Content $tempFile -Raw
            if ($raw) { return $raw.Trim() }
        }
        return ""
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
    }
}

Describe "Emit-Event" {

    It "should produce valid JSON with timestamp and type" {
        $output = Invoke-EmitCapture 'Emit-Event -EventType "test_event" -Data @{ key = "value" }'
        $parsed = $output | ConvertFrom-Json
        Assert-Equal "test_event" $parsed.type
        Assert-Equal "value" $parsed.data.key
        Assert-NotNull $parsed.timestamp
    }
}

Describe "Emit-Log" {

    It "should accept valid log levels without error" {
        # Should not throw for any valid level
        foreach ($level in @("debug", "info", "warn", "error")) {
            Emit-Log -Level $level -Message "test $level" -Component "test"
        }
        Assert-True $true "All valid levels accepted"
    }

    It "should use rich output in rich mode" {
        $global:FelixOutputFormat = "rich"
        try {
            Emit-Log -Level "info" -Message "Rich mode test" -Component "test"
            Assert-True $true "Rich mode did not throw"
        }
        finally {
            $global:FelixOutputFormat = $null
        }
    }

    It "should include component in NDJSON output" {
        $output = Invoke-EmitCapture 'Emit-Log -Level "info" -Message "test msg" -Component "mycomp"'
        $parsed = $output | ConvertFrom-Json
        Assert-Equal "mycomp" $parsed.data.component
        Assert-Equal "info" $parsed.data.level
        Assert-Equal "test msg" $parsed.data.message
    }
}

Describe "Emit-Progress" {

    It "should include percent and step in NDJSON output" {
        $output = Invoke-EmitCapture 'Emit-Progress -Percent 50 -Step "validation" -Message "Running tests"'
        $parsed = $output | ConvertFrom-Json
        Assert-Equal "progress" $parsed.type
        Assert-Equal 50 $parsed.data.percent
        Assert-Equal "validation" $parsed.data.step
        Assert-Equal "Running tests" $parsed.data.message
    }

    It "should reject percent out of range" {
        Assert-Throws {
            Emit-Progress -Percent 101 -Step "test"
        }
    }
}

Describe "Emit-Error" {

    It "should emit error_occurred event" {
        $output = Invoke-EmitCapture 'Emit-Error -ErrorType "TestError" -Message "Something broke" -Severity "error"'
        $parsed = $output | ConvertFrom-Json
        Assert-Equal "error_occurred" $parsed.type
        Assert-Equal "TestError" $parsed.data.error_type
        Assert-Equal "Something broke" $parsed.data.message
        Assert-Equal "error" $parsed.data.severity
    }
}

Describe "Event Suppression" {

    It "should suppress events when SuppressEventEmission is set" {
        $output = Invoke-EmitCapture '$script:SuppressEventEmission = $true; Emit-Event -EventType "suppressed" -Data @{ key = "value" }'
        Assert-Equal "" $output "No output should be produced when suppressed"
    }
}

Get-TestResults
