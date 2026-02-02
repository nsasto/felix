<#
.SYNOPSIS
Tests for PowerShell 5.1 compatibility utilities
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/compat-utils.ps1"

Describe "Coalesce-Value Function" {

    It "should return value when not null" {
        $result = Coalesce-Value "test" "default"
        Assert-Equal "test" $result
    }

    It "should return default when value is null" {
        $result = Coalesce-Value $null "default"
        Assert-Equal "default" $result
    }

    It "should return default when value is empty string" {
        $result = Coalesce-Value "" "default"
        Assert-Equal "default" $result
    }

    It "should work with pipeline input" {
        $result = $null | Coalesce-Value -Default "piped"
        Assert-Equal "piped" $result
    }
}

Describe "Ternary Function" {

    It "should return IfTrue when condition is true" {
        $result = Ternary $true "yes" "no"
        Assert-Equal "yes" $result
    }

    It "should return IfFalse when condition is false" {
        $result = Ternary $false "yes" "no"
        Assert-Equal "no" $result
    }

    It "should handle complex conditions" {
        $value = 5
        $result = Ternary ($value -gt 3) "big" "small"
        Assert-Equal "big" $result
    }
}

Describe "Safe-Interpolate Function" {

    It "should replace variables correctly" {
        $result = Safe-Interpolate -Template "Hello `${name}!" -Variables @{ name = "World" }
        Assert-Equal "Hello World!" $result
    }

    It "should handle multiple variables" {
        $template = "`${greeting} `${name}, you have `${count} messages"
        $vars = @{ greeting = "Hi"; name = "Alice"; count = "5" }
        $result = Safe-Interpolate -Template $template -Variables $vars
        Assert-Equal "Hi Alice, you have 5 messages" $result
    }

    It "should not confuse colons with drive references" {
        $template = "Status: `${status}"
        $vars = @{ status = "Building" }
        $result = Safe-Interpolate -Template $template -Variables $vars
        Assert-Equal "Status: Building" $result
    }
}

Describe "Invoke-SafeCommand Function" {

    It "should execute command and return exit code" {
        $result = Invoke-SafeCommand -Command "powershell" -Arguments @("-Command", "exit 0")
        Assert-Equal 0 $result.exitCode
    }

    It "should return non-zero exit code on failure" {
        $result = Invoke-SafeCommand -Command "powershell" -Arguments @("-Command", "exit 42")
        Assert-Equal 42 $result.exitCode
    }

    It "should change working directory" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/test-wd-$(Get-Random)" -Force
        $result = Invoke-SafeCommand -Command "powershell" -Arguments @("-Command", "pwd") -WorkingDirectory $tempDir.FullName
        $outputString = $result.output | Out-String
        Assert-True ($outputString -match [regex]::Escape($tempDir.FullName))
        Remove-Item $tempDir -Recurse -Force
    }
}

Get-TestResults
