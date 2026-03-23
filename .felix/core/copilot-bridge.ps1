. "$PSScriptRoot/emit-event.ps1"

function Resolve-FelixCliBridgeCommand {
    <#
    .SYNOPSIS
    Resolves a runnable Felix CLI command for the C# Copilot bridge
    #>
    param()

    if ($script:FelixCliBridgeCommand) {
        if (Test-Path -Path $script:FelixCliBridgeCommand.FilePath -PathType Leaf) {
            return $script:FelixCliBridgeCommand
        }

        $script:FelixCliBridgeCommand = $null
    }

    if (-not (Get-Command Resolve-FelixExecutablePath -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\compat-utils.ps1"
    }

    $candidates = @()

    if (-not [string]::IsNullOrWhiteSpace($env:FELIX_COPILOT_BRIDGE_EXE)) {
        $candidates += $env:FELIX_COPILOT_BRIDGE_EXE
    }

    if (-not [string]::IsNullOrWhiteSpace($env:FELIX_INSTALL_DIR)) {
        $candidates += (Join-Path $env:FELIX_INSTALL_DIR "felix.exe")
        $candidates += (Join-Path $env:FELIX_INSTALL_DIR "felix")
        $candidates += (Join-Path $env:FELIX_INSTALL_DIR "felix.dll")
    }

    $resolvedFelix = Resolve-FelixExecutablePath "felix"
    if ($resolvedFelix) {
        $candidates += $resolvedFelix
    }

    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $candidatePatterns = @(
        (Join-Path $repoRoot "src\Felix.Cli\bin\*\net10.0\felix.exe"),
        (Join-Path $repoRoot "src\Felix.Cli\bin\*\net10.0\felix.dll")
    )

    foreach ($pattern in $candidatePatterns) {
        $candidateFiles = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        foreach ($candidateFile in $candidateFiles) {
            $candidates += $candidateFile.FullName
        }
    }

    foreach ($candidate in ($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (-not (Test-Path -Path $candidate -PathType Leaf)) {
            continue
        }

        $extension = [System.IO.Path]::GetExtension($candidate)
        if ($extension -eq ".dll") {
            $dotnet = Resolve-FelixExecutablePath "dotnet"
            if (-not $dotnet) {
                continue
            }

            $script:FelixCliBridgeCommand = @{
                FilePath   = $dotnet
                PrefixArgs = @($candidate)
            }
            return $script:FelixCliBridgeCommand
        }

        if ($extension -eq ".ps1") {
            $pwsh = Resolve-FelixExecutablePath "pwsh"
            if (-not $pwsh) {
                $pwsh = Resolve-FelixExecutablePath "powershell"
            }
            if (-not $pwsh) {
                continue
            }

            $script:FelixCliBridgeCommand = @{
                FilePath   = $pwsh
                PrefixArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $candidate)
            }
            return $script:FelixCliBridgeCommand
        }

        $script:FelixCliBridgeCommand = @{
            FilePath   = $candidate
            PrefixArgs = @()
        }
        return $script:FelixCliBridgeCommand
    }

    return $null
}

function Test-UseCopilotCliBridge {
    <#
    .SYNOPSIS
    Determines whether the C# Copilot bridge should be used
    #>
    param()

    # Bridge is opt-in: set FELIX_COPILOT_BRIDGE=1 to enable.
    # By default copilot runs directly like all other agents.
    if ($env:FELIX_COPILOT_BRIDGE -notmatch '^(1|true|yes)$') {
        return $false
    }

    return ($null -ne (Resolve-FelixCliBridgeCommand))
}

function Publish-BridgeStderrUpdates {
    <#
    .SYNOPSIS
    Reads newly appended bridge stderr text and emits it as Felix log lines
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [int]$Offset,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Remainder,

        [switch]$FlushRemainder
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Offset = $Offset; Remainder = $Remainder }
    }

    $content = Get-Content -Raw -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        $content = ""
    }

    if ($content.Length -lt $Offset) {
        $Offset = 0
        $Remainder = ""
    }

    $newText = if ($content.Length -gt $Offset) { $content.Substring($Offset) } else { "" }
    $combined = $Remainder + $newText

    $lines = [regex]::Split($combined, "`r`n|`n|`r")
    $nextRemainder = ""
    if ($combined.Length -gt 0 -and -not $FlushRemainder -and $combined -notmatch "(`r`n|`n|`r)$") {
        $nextRemainder = $lines[-1]
        if ($lines.Count -gt 1) {
            $lines = $lines[0..($lines.Count - 2)]
        }
        else {
            $lines = @()
        }
    }

    foreach ($line in $lines) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Emit-Log -Level "info" -Message $line.TrimEnd() -Component "agent"
        }
    }

    return @{ Offset = $content.Length; Remainder = $nextRemainder }
}

function Invoke-CopilotCliBridge {
    <#
    .SYNOPSIS
    Executes Copilot through the Felix C# bridge and returns a structured result
    #>
    param(
        [Parameter(Mandatory = $true)]
        $AgentConfig,

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    $bridgeCommand = Resolve-FelixCliBridgeCommand
    if (-not $bridgeCommand) {
        throw "Felix CLI bridge executable could not be resolved"
    }

    $requestPath = [System.IO.Path]::GetTempFileName()
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()

    try {
        $request = @{
            executable            = [string]$AgentConfig.executable
            prompt                = $Prompt
            workingDirectory      = $WorkingDirectory
            model                 = if ($AgentConfig.PSObject.Properties['model']) { [string]$AgentConfig.model } else { $null }
            allowAll              = if ($AgentConfig.PSObject.Properties['allow_all']) { [bool]$AgentConfig.allow_all } else { $true }
            noAskUser             = if ($AgentConfig.PSObject.Properties['no_ask_user']) { [bool]$AgentConfig.no_ask_user } else { $true }
            maxAutopilotContinues = if ($AgentConfig.PSObject.Properties['max_autopilot_continues'] -and $null -ne $AgentConfig.max_autopilot_continues) { [int]$AgentConfig.max_autopilot_continues } else { $null }
            customAgent           = if ($AgentConfig.PSObject.Properties['custom_agent']) { [string]$AgentConfig.custom_agent } else { $null }
            mirrorOutputToStdErr  = $true
            environment           = @{}
        }

        if ($AgentConfig.environment) {
            foreach ($prop in $AgentConfig.environment.PSObject.Properties) {
                $request.environment[$prop.Name] = [string]$prop.Value
            }
        }

        $request | ConvertTo-Json -Depth 10 | Set-Content -Path $requestPath -Encoding UTF8

        $arguments = @($bridgeCommand.PrefixArgs + @("copilot-bridge", "--request-file", $requestPath))
        $process = Start-Process `
            -FilePath $bridgeCommand.FilePath `
            -ArgumentList $arguments `
            -WorkingDirectory $WorkingDirectory `
            -NoNewWindow `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $stderrOffset = 0
        $stderrRemainder = ""
        $heartbeatIntervalSec = 20
        $lastHeartbeat = Get-Date
        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 500

            $stderrState = Publish-BridgeStderrUpdates -Path $stderrPath -Offset $stderrOffset -Remainder $stderrRemainder
            $stderrOffset = [int]$stderrState.Offset
            $stderrRemainder = [string]$stderrState.Remainder

            $elapsed = ((Get-Date) - $lastHeartbeat).TotalSeconds
            if ($elapsed -ge $heartbeatIntervalSec) {
                Emit-Event -EventType "agent_heartbeat" -Data @{
                    agent_running   = $true
                    elapsed_seconds = $elapsed
                    bridge          = $true
                }
                $lastHeartbeat = Get-Date
            }
        }

        $process.WaitForExit()
        $stderrState = Publish-BridgeStderrUpdates -Path $stderrPath -Offset $stderrOffset -Remainder $stderrRemainder -FlushRemainder
        $stdout = if (Test-Path $stdoutPath) { Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue } else { "" }
        $stderr = if (Test-Path $stderrPath) { Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue } else { "" }

        if ([string]::IsNullOrWhiteSpace($stdout)) {
            throw "Copilot bridge returned no JSON payload. Stderr: $stderr"
        }

        $result = $stdout | ConvertFrom-Json -ErrorAction Stop
        return @{
            Output                = [string]$result.output
            ExitCode              = [int]$result.exitCode
            Succeeded             = [bool]$result.succeeded
            Error                 = if ($null -ne $result.error) { [string]$result.error } else { $null }
            ResolvedExecutable    = [string]$result.resolvedExecutable
            UsedBridge            = [bool]$result.usedBridge
            BridgeProcessExitCode = [int]$process.ExitCode
            BridgeStdErr          = $stderr
        }
    }
    finally {
        foreach ($path in @($requestPath, $stdoutPath, $stderrPath)) {
            if ($path -and (Test-Path $path)) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
    }
}