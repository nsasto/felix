. "$PSScriptRoot/test-framework.ps1"

Describe "agent install-help" {

    It "should show only the requested agent when targeting copilot" {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $felixScript = Join-Path $repoRoot ".felix\felix.ps1"

        Assert-True (Test-Path $felixScript) "Missing Felix entrypoint at $felixScript"

        Push-Location $repoRoot
        try {
            $output = (& powershell.exe -NoProfile -File $felixScript agent install-help copilot 2>&1 | Out-String)
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        Assert-Equal 0 $exitCode "Expected targeted install-help to succeed"
        Assert-True ($output -match "Agent Install Help") "Expected install-help header in output"
        Assert-True ($output -match "copilot \[(OK|--)\] installed") "Expected copilot install status in output"
        Assert-True ($output -match "copilot login") "Expected copilot login guidance in output"
        Assert-False ($output -match "codex \[(OK|--)\] installed") "Targeted install-help should not list other agents"
        Assert-False ($output -match "claude \[(OK|--)\] installed") "Targeted install-help should not list other agents"
    }
}

Get-TestResults