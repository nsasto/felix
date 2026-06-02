param(
    [string[]]$Adapters = @("claude", "codex"),
    [switch]$VerboseMode,
    [int]$TimeoutSeconds = 30,
    [string]$Prompt = "Reply with a single short sentence that says TEST_OK and nothing else."
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/compat-utils.ps1"
. "$PSScriptRoot/../core/output-normalizer.ps1"
. "$PSScriptRoot/../core/agent-adapters.ps1"

function Read-AgentProfile {
    param([string]$Adapter)

    $defaults = Get-AgentDefaults -AdapterType $Adapter

    $agentsFile = Join-Path (Split-Path $PSScriptRoot -Parent) "agents.json"
    if (Test-Path $agentsFile) {
        try {
            $agentsConfig = Get-Content $agentsFile -Raw | ConvertFrom-Json
            $profile = $agentsConfig.agents | Where-Object { $_.adapter -eq $Adapter } | Select-Object -First 1
            if ($profile) {
                foreach ($key in $defaults.Keys) {
                    if (-not $profile.PSObject.Properties[$key] -or $null -eq $profile.$key -or ($profile.$key -is [string] -and [string]::IsNullOrWhiteSpace($profile.$key))) {
                        $profile | Add-Member -NotePropertyName $key -NotePropertyValue $defaults[$key] -Force
                    }
                }
                return $profile
            }
        }
        catch {
        }
    }

    return [pscustomobject]$defaults
}

function Convert-ToArgString {
    param([string[]]$Arguments)

    return (@($Arguments) | ForEach-Object {
            $value = [string]$_
            if ($value -match '[\s"]') { '"' + ($value -replace '"', '\"') + '"' } else { $value }
        }) -join ' '
}

function Invoke-AgentProbe {
    param(
        [string]$Adapter,
        [bool]$UseVerboseMode
    )

    $profile = Read-AgentProfile -Adapter $Adapter
    $resolvedExecutable = Resolve-FelixExecutablePath $profile.executable
    if (-not $resolvedExecutable) {
        Write-Host ""
        Write-Host "[$Adapter] SKIP - executable not found: $($profile.executable)" -ForegroundColor Yellow
        return
    }

    $invocation = Get-AgentInvocation -AdapterType $Adapter -Config $profile -Prompt $Prompt -VerboseMode:$UseVerboseMode
    $processFilePath = $resolvedExecutable
    $processArgs = @($invocation.Arguments)

    if ($resolvedExecutable.EndsWith(".ps1")) {
        $processFilePath = "powershell.exe"
        $processArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $resolvedExecutable) + $processArgs
    }

    $modeLabel = if ($UseVerboseMode) { "verbose" } else { "normal" }
    $logDir = Join-Path $PSScriptRoot "logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $baseName = "agent-io-$Adapter-$modeLabel"
    $stdoutPath = Join-Path $logDir "$baseName.stdout.log"
    $stderrPath = Join-Path $logDir "$baseName.stderr.log"
    $combinedPath = Join-Path $logDir "$baseName.combined.log"
    $normalizedPath = Join-Path $logDir "$baseName.normalized.log"
    $inputPath = $null

    Write-Host ""
    Write-Host "=== $($Adapter.ToUpper()) / $modeLabel ===" -ForegroundColor Cyan
    Write-Host "Executable: $resolvedExecutable" -ForegroundColor Gray
    Write-Host "Process:    $processFilePath" -ForegroundColor Gray
    Write-Host "Args:       $(Convert-ToArgString -Arguments $processArgs)" -ForegroundColor Gray
    Write-Host "PromptMode: $($invocation.PromptMode)" -ForegroundColor Gray
    Write-Host "Timeout:    $TimeoutSeconds s" -ForegroundColor Gray

    # Clear CLAUDECODE so a nested claude subprocess is not blocked by the host session guard.
    # Use -ne $null (not truthiness) so an empty-string value is also cleared.
    $claudeCodeBackup = [Environment]::GetEnvironmentVariable("CLAUDECODE", "Process")
    if ($null -ne $claudeCodeBackup) {
        [Environment]::SetEnvironmentVariable("CLAUDECODE", $null, "Process")
    }

    try {
        if ($invocation.PromptMode -eq "stdin") {
            $inputPath = [System.IO.Path]::GetTempFileName()
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($inputPath, $invocation.FormattedPrompt, $utf8NoBom)
            $process = Start-Process `
                -FilePath $processFilePath `
                -ArgumentList (Convert-ToArgString -Arguments $processArgs) `
                -NoNewWindow `
                -PassThru `
                -RedirectStandardInput $inputPath `
                -RedirectStandardOutput $stdoutPath `
                -RedirectStandardError $stderrPath
        }
        else {
            $process = Start-Process `
                -FilePath $processFilePath `
                -ArgumentList (Convert-ToArgString -Arguments $processArgs) `
                -NoNewWindow `
                -PassThru `
                -RedirectStandardOutput $stdoutPath `
                -RedirectStandardError $stderrPath
        }

        $startTime = Get-Date
        $stdoutLineCount = 0
        $stderrLineCount = 0
        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 250
            if (((Get-Date) - $startTime).TotalSeconds -ge $TimeoutSeconds) {
                Write-Host "[timeout] killing process" -ForegroundColor Yellow
                $process.Kill()
                break
            }

            foreach ($streamInfo in @(
                    @{ Name = "stdout"; Path = $stdoutPath; CountRef = "stdoutLineCount"; Color = "DarkGray" },
                    @{ Name = "stderr"; Path = $stderrPath; CountRef = "stderrLineCount"; Color = "Yellow" }
                )) {
                if (-not (Test-Path $streamInfo.Path)) { continue }
                $lines = @(Get-Content -LiteralPath $streamInfo.Path -ErrorAction SilentlyContinue)
                $currentCount = Get-Variable -Name $streamInfo.CountRef -ValueOnly
                if ($lines.Count -le $currentCount) { continue }
                foreach ($line in $lines[$currentCount..($lines.Count - 1)]) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    Write-Host "[$($streamInfo.Name)] $line" -ForegroundColor $streamInfo.Color
                }
                Set-Variable -Name $streamInfo.CountRef -Value $lines.Count
            }
        }

        $process.WaitForExit()
        $stdout = if (Test-Path $stdoutPath) { Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue } else { "" }
        $stderr = if (Test-Path $stderrPath) { Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue } else { "" }
        $combined = if ([string]::IsNullOrWhiteSpace($stderr)) { $stdout } elseif ([string]::IsNullOrWhiteSpace($stdout)) { $stderr } else { $stdout.TrimEnd() + "`n" + $stderr.TrimEnd() }
        $normalized = Normalize-AgentOutput -Output $combined -AdapterType $Adapter
        $parsed = $invocation.Adapter.ParseResponse($normalized)
        $signal = Get-CompletionSignal -Output $parsed.Output -AllowPlanningAlias

        Set-Content -Path $combinedPath -Value $combined -Encoding UTF8
        Set-Content -Path $normalizedPath -Value $normalized -Encoding UTF8

        Write-Host "ExitCode:   $($process.ExitCode)" -ForegroundColor Gray
        Write-Host "StdoutLen:  $($stdout.Length)" -ForegroundColor Gray
        Write-Host "StderrLen:  $($stderr.Length)" -ForegroundColor Gray
        Write-Host "Combined:   $combinedPath" -ForegroundColor Gray
        Write-Host "Normalized: $normalizedPath" -ForegroundColor Gray
        Write-Host "ParsedComplete: $($parsed.IsComplete)" -ForegroundColor Gray
        Write-Host "NextMode:      $($parsed.NextMode)" -ForegroundColor Gray
        Write-Host "Signal:        $signal" -ForegroundColor Gray
        if ($parsed.Error) {
            Write-Host "ParsedError:   $($parsed.Error)" -ForegroundColor Yellow
        }

        $preview = if ($normalized.Length -gt 500) { $normalized.Substring(0, 500) + "..." } else { $normalized }
        if (-not [string]::IsNullOrWhiteSpace($preview)) {
            Write-Host ""
            Write-Host "--- Normalized Output Preview ---" -ForegroundColor Cyan
            Write-Host $preview -ForegroundColor DarkGray
        }
    }
    finally {
        if ($inputPath -and (Test-Path $inputPath)) {
            Remove-Item $inputPath -Force -ErrorAction SilentlyContinue
        }
        if ($claudeCodeBackup) {
            [Environment]::SetEnvironmentVariable("CLAUDECODE", $claudeCodeBackup, "Process")
        }
    }
}

foreach ($adapter in $Adapters) {
    Invoke-AgentProbe -Adapter $adapter -UseVerboseMode:$false
    Invoke-AgentProbe -Adapter $adapter -UseVerboseMode:$true
}

Write-Host ""
Write-Host "Done. Compare live stream lines with the saved stdout/stderr logs under .felix/tests/logs/." -ForegroundColor Green
