<#
.SYNOPSIS
Agent process executor and planning guardrails

.DESCRIPTION
Handles agent subprocess execution via adapter and enforces planning mode restrictions.
#>

. "$PSScriptRoot\output-normalizer.ps1"
. "$PSScriptRoot\copilot-bridge.ps1"

function Remove-ArgumentPair {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Flag
    )

    $filtered = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        if ([string]::Equals($Arguments[$i], $Flag, [System.StringComparison]::OrdinalIgnoreCase)) {
            $i++
            continue
        }

        $filtered.Add([string]$Arguments[$i])
    }

    return @($filtered.ToArray())
}

function Test-CopilotModelUnavailableOutput {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Output
    )

    return $Output -match 'Model\s+"[^"]+"\s+from\s+--model\s+flag\s+is\s+not\s+available'
}

function Repair-FelixProcessPathEnvironment {
    <#
    .SYNOPSIS
    Collapses duplicate PATH/Path entries in the current process environment on Windows.

    .DESCRIPTION
    Some launch environments expose both PATH and Path. Windows treats them as the
    same variable, but PowerShell's environment provider and Start-Process can throw
    "same key has already been added" before the agent subprocess starts. Preserve
    the active PATH value, then store it once under canonical Path.
    #>

    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
        return
    }

    try {
        $envs = [Environment]::GetEnvironmentVariables("Process")
        $pathValue = $envs["PATH"]
        if (-not $pathValue) {
            $pathValue = $envs["Path"]
        }

        if ($pathValue) {
            [Environment]::SetEnvironmentVariable("PATH", $null, "Process")
            [Environment]::SetEnvironmentVariable("Path", [string]$pathValue, "Process")
        }
    }
    catch {
        # Environment repair must never block agent execution.
    }
}

function Get-FelixObjectPropertyValue {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) { return $null }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }

    return $null
}

function ConvertTo-FelixNullableLong {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return $null }

    try {
        return [int64]$Value
    }
    catch {
        return $null
    }
}

function ConvertTo-FelixTokenUsage {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Usage
    )

    if ($null -eq $Usage) { return $null }

    $inputTokens = ConvertTo-FelixNullableLong (Get-FelixObjectPropertyValue -Object $Usage -Name "input_tokens")
    if ($null -eq $inputTokens) {
        $inputTokens = ConvertTo-FelixNullableLong (Get-FelixObjectPropertyValue -Object $Usage -Name "prompt_tokens")
    }
    if ($null -eq $inputTokens) {
        $inputTokens = ConvertTo-FelixNullableLong (Get-FelixObjectPropertyValue -Object $Usage -Name "inputTokens")
    }

    $outputTokens = ConvertTo-FelixNullableLong (Get-FelixObjectPropertyValue -Object $Usage -Name "output_tokens")
    if ($null -eq $outputTokens) {
        $outputTokens = ConvertTo-FelixNullableLong (Get-FelixObjectPropertyValue -Object $Usage -Name "completion_tokens")
    }
    if ($null -eq $outputTokens) {
        $outputTokens = ConvertTo-FelixNullableLong (Get-FelixObjectPropertyValue -Object $Usage -Name "outputTokens")
    }

    $cacheReadTokens = ConvertTo-FelixNullableLong (Get-FelixObjectPropertyValue -Object $Usage -Name "cache_read_input_tokens")
    if ($null -eq $cacheReadTokens) {
        $cacheReadTokens = ConvertTo-FelixNullableLong (Get-FelixObjectPropertyValue -Object $Usage -Name "cached_input_tokens")
    }

    $cacheCreationTokens = ConvertTo-FelixNullableLong (Get-FelixObjectPropertyValue -Object $Usage -Name "cache_creation_input_tokens")

    $totalTokens = ConvertTo-FelixNullableLong (Get-FelixObjectPropertyValue -Object $Usage -Name "total_tokens")
    if ($null -eq $totalTokens) {
        $totalTokens = ConvertTo-FelixNullableLong (Get-FelixObjectPropertyValue -Object $Usage -Name "totalTokens")
    }
    if ($null -eq $totalTokens -and ($null -ne $inputTokens -or $null -ne $outputTokens)) {
        $safeInputTokens = if ($null -eq $inputTokens) { 0 } else { $inputTokens }
        $safeOutputTokens = if ($null -eq $outputTokens) { 0 } else { $outputTokens }
        $totalTokens = [int64]($safeInputTokens + $safeOutputTokens)
    }

    $observedTokens = [int64]0
    $hasObserved = $false
    foreach ($value in @($inputTokens, $outputTokens, $cacheReadTokens, $cacheCreationTokens)) {
        if ($null -ne $value) {
            $observedTokens += [int64]$value
            $hasObserved = $true
        }
    }

    if (-not $hasObserved -and $null -eq $totalTokens) {
        return $null
    }

    return [ordered]@{
        input_tokens                = $inputTokens
        output_tokens               = $outputTokens
        total_tokens                = $totalTokens
        cache_read_input_tokens     = $cacheReadTokens
        cache_creation_input_tokens = $cacheCreationTokens
        observed_tokens             = if ($hasObserved) { $observedTokens } else { $totalTokens }
    }
}

function Get-AgentUsageFromOutput {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Output,

        [Parameter(Mandatory = $true)]
        [string]$AdapterType
    )

    $result = [ordered]@{
        usage           = $null
        usage_source    = $null
        effective_model = $null
        model_source    = $null
        session_id      = $null
    }

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return $result
    }

    $lines = @($Output -split "`r`n|`n|`r" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    foreach ($line in $lines) {
        $event = $null
        try {
            $event = $line | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            continue
        }

        $model = Get-FelixObjectPropertyValue -Object $event -Name "model"
        if ($model) {
            $result.effective_model = [string]$model
            $result.model_source = "$AdapterType.output"
        }

        $sessionId = Get-FelixObjectPropertyValue -Object $event -Name "session_id"
        if (-not $sessionId) {
            $sessionId = Get-FelixObjectPropertyValue -Object $event -Name "sessionId"
        }
        if ($sessionId) {
            $result.session_id = [string]$sessionId
        }

        $usage = Get-FelixObjectPropertyValue -Object $event -Name "usage"
        $usageSource = "$AdapterType.output"
        if ($null -eq $usage) {
            $data = Get-FelixObjectPropertyValue -Object $event -Name "data"
            $usage = Get-FelixObjectPropertyValue -Object $data -Name "usage"
            $usageSource = "$AdapterType.output.data"
            if ($null -eq $usage) {
                $usage = $data
            }

            $dataModel = Get-FelixObjectPropertyValue -Object $data -Name "model"
            if ($dataModel) {
                $result.effective_model = [string]$dataModel
                $result.model_source = "$AdapterType.output.data"
            }

            $dataSessionId = Get-FelixObjectPropertyValue -Object $data -Name "session_id"
            if (-not $dataSessionId) {
                $dataSessionId = Get-FelixObjectPropertyValue -Object $data -Name "sessionId"
            }
            if ($dataSessionId) {
                $result.session_id = [string]$dataSessionId
            }
        }

        $tokenUsage = ConvertTo-FelixTokenUsage -Usage $usage
        if ($tokenUsage) {
            $result.usage = $tokenUsage
            $result.usage_source = $usageSource
        }
    }

    return $result
}

function Get-AgentParseInput {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Output
    )

    # PowerShell class methods with [string] parameters reject [string]::Empty.
    # Keep raw output artifacts unchanged, but pass a harmless newline to parsers.
    if ($null -eq $Output -or $Output.Length -eq 0) {
        return "`n"
    }

    return $Output
}

function Write-AgentUsageArtifact {
    param(
        [Parameter(Mandatory = $true)]
        $AgentConfig,

        [Parameter(Mandatory = $true)]
        [string]$AdapterType,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [string]$RunDir,

        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Output,

        [Parameter(Mandatory = $true)]
        [double]$DurationSeconds,

        [Parameter(Mandatory = $true)]
        [int]$ExitCode,

        [Parameter(Mandatory = $true)]
        [bool]$Succeeded,

        [Parameter(Mandatory = $false)]
        [bool]$RetriedWithoutExplicitModel = $false
    )

    $configuredModel = if ($AgentConfig.PSObject.Properties["model"] -and -not [string]::IsNullOrWhiteSpace([string]$AgentConfig.model)) {
        [string]$AgentConfig.model
    }
    else {
        $null
    }

    $usageInfo = Get-AgentUsageFromOutput -Output $Output -AdapterType $AdapterType
    $effectiveModel = if ($usageInfo.effective_model) { [string]$usageInfo.effective_model } else { $configuredModel }
    $modelSource = if ($usageInfo.model_source) { [string]$usageInfo.model_source } elseif ($configuredModel) { "configured" } else { "provider_default" }

    if ($RetriedWithoutExplicitModel -and -not $usageInfo.effective_model) {
        $effectiveModel = $null
        $modelSource = "provider_default_after_configured_model_rejected"
    }

    $provider = if ($AgentConfig.PSObject.Properties["provider"] -and $AgentConfig.provider) {
        [string]$AgentConfig.provider
    }
    else {
        $AdapterType
    }

    $usageRecord = [ordered]@{
        _v                = 1
        run_id            = $RunId
        timestamp_utc     = (Get-Date).ToUniversalTime().ToString("o")
        duration_seconds  = [math]::Round($DurationSeconds, 3)
        exit_code         = $ExitCode
        succeeded         = $Succeeded
        usage_available   = ($null -ne $usageInfo.usage)
        usage_source      = $usageInfo.usage_source
        session_id        = $usageInfo.session_id
        agent             = [ordered]@{
            id         = if ($AgentConfig.PSObject.Properties["key"]) { [string]$AgentConfig.key } else { $null }
            name       = if ($AgentConfig.PSObject.Properties["name"]) { [string]$AgentConfig.name } else { $null }
            provider   = $provider
            adapter    = $AdapterType
            executable = if ($AgentConfig.PSObject.Properties["executable"]) { [string]$AgentConfig.executable } else { $null }
        }
        model             = [ordered]@{
            configured = $configuredModel
            effective  = $effectiveModel
            source     = $modelSource
        }
        usage             = $usageInfo.usage
    }

    try {
        $usagePath = Join-Path $RunDir "usage.json"
        $usageRecord | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $usagePath -Encoding UTF8

        $relPath = $usagePath.Replace($ProjectPath + "\", "")
        Emit-Artifact -Path $relPath -Type "usage" -SizeBytes (Get-Item $usagePath).Length
        Emit-Event -EventType "llm_usage" -Data $usageRecord
    }
    catch {
        Emit-Log -Level "warn" -Message "Failed to write usage artifact: $($_.Exception.Message)" -Component "agent"
    }

    return $usageRecord
}

function Write-AgentPromptArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunDir,

        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,

        [Parameter(Mandatory = $true)]
        [string]$AdapterType,

        [Parameter(Mandatory = $true)]
        [string]$PromptMode,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Prompt,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string[]]$AgentArgs = @()
    )

    try {
        $existing = @(Get-ChildItem -LiteralPath $RunDir -Filter "prompt-*.txt" -ErrorAction SilentlyContinue)
        $index = $existing.Count + 1

        $promptFileName = "prompt-{0:D2}.txt" -f $index
        $metaFileName = "prompt-{0:D2}.meta.json" -f $index

        $promptPath = Join-Path $RunDir $promptFileName
        $metaPath = Join-Path $RunDir $metaFileName

        Set-Content -LiteralPath $promptPath -Value $Prompt -Encoding UTF8

        $meta = @{
            timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
            adapter       = $AdapterType
            prompt_mode   = $PromptMode
            prompt_length = $Prompt.Length
            args_count    = if ($AgentArgs) { $AgentArgs.Count } else { 0 }
            args_preview  = if ($AgentArgs) { @($AgentArgs | Select-Object -First 20) } else { @() }
        }

        $meta | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metaPath -Encoding UTF8

        $relPrompt = $promptPath.Replace($ProjectPath + "\", "")
        Emit-Artifact -Path $relPrompt -Type "prompt" -SizeBytes (Get-Item $promptPath).Length

        $relMeta = $metaPath.Replace($ProjectPath + "\", "")
        Emit-Artifact -Path $relMeta -Type "metadata" -SizeBytes (Get-Item $metaPath).Length

        Emit-Log -Level "debug" -Message "Prompt artifact logged: $promptFileName ($($Prompt.Length) chars, mode=$PromptMode)" -Component "agent"
    }
    catch {
        Emit-Log -Level "warn" -Message "Failed to log prompt artifact: $($_.Exception.Message)" -Component "agent"
    }
}

function Invoke-AgentSubprocess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessFilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$ProcessArgs,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [ValidateSet("stdin", "argument")]
        [string]$PromptMode,

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $true)]
        [datetime]$StartTime,

        [Parameter(Mandatory = $false)]
        [switch]$VerboseMode
    )

    $inputPath = $null
    $argumentPromptPath = $null
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()

    try {
        Repair-FelixProcessPathEnvironment

        if ($PromptMode -eq "stdin") {
            $inputPath = [System.IO.Path]::GetTempFileName()
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($inputPath, $Prompt, $utf8NoBom)
        }
        elseif ($PromptMode -eq "argument") {
            $promptFlagIndex = -1
            for ($i = 0; $i -lt $ProcessArgs.Count; $i++) {
                if ($ProcessArgs[$i] -in @("-p", "--prompt")) {
                    $promptFlagIndex = $i
                    break
                }
            }

            if ($promptFlagIndex -ge 0 -and ($promptFlagIndex + 1) -lt $ProcessArgs.Count) {
                $promptArg = [string]$ProcessArgs[$promptFlagIndex + 1]
                if ($promptArg.Length -gt 6000) {
                    $argumentPromptPath = [System.IO.Path]::GetTempFileName()
                    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                    [System.IO.File]::WriteAllText($argumentPromptPath, $promptArg, $utf8NoBom)

                    $shortPrompt = "Read the Felix prompt from this file and follow it exactly: $argumentPromptPath"
                    $updatedArgs = @($ProcessArgs)
                    $updatedArgs[$promptFlagIndex + 1] = $shortPrompt
                    $ProcessArgs = [string[]]$updatedArgs
                }
            }
        }

        $argString = (@($ProcessArgs) | ForEach-Object {
                $a = [string]$_
                if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
            }) -join ' '

        if ($PromptMode -eq "stdin") {
            $process = Start-Process `
                -FilePath $ProcessFilePath `
                -ArgumentList $argString `
                -WorkingDirectory $WorkingDirectory `
                -NoNewWindow `
                -PassThru `
                -RedirectStandardInput $inputPath `
                -RedirectStandardOutput $stdoutPath `
                -RedirectStandardError $stderrPath
        }
        else {
            $process = Start-Process `
                -FilePath $ProcessFilePath `
                -ArgumentList $argString `
                -WorkingDirectory $WorkingDirectory `
                -NoNewWindow `
                -PassThru `
                -RedirectStandardOutput $stdoutPath `
                -RedirectStandardError $stderrPath
        }

        $heartbeatIntervalSec = 20
        $lastHeartbeat = Get-Date
        $stdoutLineCount = 0
        $stderrLineCount = 0
        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 500
            $elapsed = ((Get-Date) - $lastHeartbeat).TotalSeconds
            if ($elapsed -ge $heartbeatIntervalSec) {
                Emit-Event -EventType "agent_heartbeat" -Data @{
                    agent_running   = $true
                    elapsed_seconds = [int]((Get-Date) - $StartTime).TotalSeconds
                }
                $lastHeartbeat = Get-Date
            }

            if ($VerboseMode) {
                if (Test-Path $stdoutPath) {
                    $stdoutLines = @(Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue)
                    if ($stdoutLines.Count -gt $stdoutLineCount) {
                        foreach ($line in $stdoutLines[$stdoutLineCount..($stdoutLines.Count - 1)]) {
                            if (-not [string]::IsNullOrWhiteSpace($line)) {
                                Emit-AgentStreamChunk -Stream "stdout" -Content $line
                            }
                        }
                        $stdoutLineCount = $stdoutLines.Count
                    }
                }

                if (Test-Path $stderrPath) {
                    $stderrLines = @(Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue)
                    if ($stderrLines.Count -gt $stderrLineCount) {
                        foreach ($line in $stderrLines[$stderrLineCount..($stderrLines.Count - 1)]) {
                            if (-not [string]::IsNullOrWhiteSpace($line)) {
                                Emit-AgentStreamChunk -Stream "stderr" -Content $line
                            }
                        }
                        $stderrLineCount = $stderrLines.Count
                    }
                }
            }
        }

        $process.WaitForExit()
        $exitCode = [int]$process.ExitCode

        $stdout = ""
        $stderr = ""
        if (Test-Path $stdoutPath) { $stdout = Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue }
        if (Test-Path $stderrPath) { $stderr = Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue }

        if ($VerboseMode) {
            $stdoutLines = @($stdout -split "`r`n|`n|`r")
            if ($stdoutLines.Count -gt $stdoutLineCount) {
                foreach ($line in $stdoutLines[$stdoutLineCount..($stdoutLines.Count - 1)]) {
                    if (-not [string]::IsNullOrWhiteSpace($line)) {
                        Emit-AgentStreamChunk -Stream "stdout" -Content $line
                    }
                }
            }

            $stderrLines = @($stderr -split "`r`n|`n|`r")
            if ($stderrLines.Count -gt $stderrLineCount) {
                foreach ($line in $stderrLines[$stderrLineCount..($stderrLines.Count - 1)]) {
                    if (-not [string]::IsNullOrWhiteSpace($line)) {
                        Emit-AgentStreamChunk -Stream "stderr" -Content $line
                    }
                }
            }
        }

        $output = $stdout
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            if (-not [string]::IsNullOrWhiteSpace($output)) { $output += "`n" }
            $output += $stderr
        }

        return @{
            Output    = $output
            ExitCode  = $exitCode
            Succeeded = ($exitCode -eq 0)
        }
    }
    finally {
        foreach ($path in @($inputPath, $argumentPromptPath, $stdoutPath, $stderrPath)) {
            try { if ($path -and (Test-Path $path)) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } } catch { }
        }
    }
}

function Invoke-AgentExecution {
    <#
    .SYNOPSIS
    Executes the agent with the given prompt
    #>
    param(
        [Parameter(Mandatory = $true)]
        $AgentConfig,
        
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [string]$RunDir,

        [Parameter(Mandatory = $false)]
        [switch]$DebugMode,
        
        [Parameter(Mandatory = $false)]
        [switch]$VerboseMode
    )
    
    # Workflow Stage: execute_llm
    Set-WorkflowStage -Stage "execute_llm" -ProjectPath $ProjectPath
    Repair-FelixProcessPathEnvironment
    
    Emit-AgentExecutionStarted -AgentName $AgentConfig.name -AgentId $AgentConfig.key
    
    # Load agent adapter
    $adapterType = if ($AgentConfig.adapter) { $AgentConfig.adapter } else { "droid" }
    $adapter = Get-AgentAdapter -AdapterType $adapterType
    if (-not $adapter) {
        Write-Error "Failed to load adapter: $adapterType"
        return @{ Output = ""; Duration = [TimeSpan]::Zero }
    }
    
    $executable = $AgentConfig.executable
    $agentWorkingDir = if ($AgentConfig.working_directory) { $AgentConfig.working_directory } else { "." }
    $agentCwd = if ([System.IO.Path]::IsPathRooted($agentWorkingDir)) {
        $agentWorkingDir
    }
    else {
        Join-Path $ProjectPath $agentWorkingDir
    }

    $resolvedExecutable = $null
    $invocation = $null
    $formattedPrompt = $Prompt
    $agentArgs = @()
    $promptMode = "stdin"
    if (-not ($adapterType -eq "copilot" -and (Test-UseCopilotCliBridge))) {
        $invocation = Get-AgentInvocation -AdapterType $adapterType -Config $AgentConfig -Prompt $Prompt -VerboseMode:$VerboseMode.IsPresent
        $formattedPrompt = $invocation.FormattedPrompt
        $agentArgs = @($invocation.Arguments)
        $promptMode = $invocation.PromptMode
    }

    Write-AgentPromptArtifacts `
        -RunDir $RunDir `
        -ProjectPath $ProjectPath `
        -AdapterType $adapterType `
        -PromptMode $promptMode `
        -Prompt $formattedPrompt `
        -AgentArgs $agentArgs

    $startTime = Get-Date
    
    # Hook: OnPreExecution
    $hookResult = Invoke-PluginHookSafely -HookName "OnPreExecution" -RunId $RunId -HookData @{
        Executable = $executable
        Args       = [System.Collections.ArrayList]@($agentArgs)
        Prompt     = $formattedPrompt
    }
    
    if ($hookResult.ModifiedArgs) {
        $agentArgs = $hookResult.ModifiedArgs
        Write-Verbose "[PLUGINS] Using modified executable arguments"
    }

    $envBackup = @{}
    $exitCode = 0
    $succeeded = $true
    $retriedWithoutExplicitModel = $false

    # Clear CLAUDECODE so the agent subprocess is not blocked by the "nested session" guard.
    # Claude Code sets this env var in the host session; any child claude process sees it and
    # refuses to start. We save and restore it around the subprocess call.
    $claudeCodeValue = [Environment]::GetEnvironmentVariable("CLAUDECODE", "Process")
    if ($claudeCodeValue) {
        $envBackup["CLAUDECODE"] = $claudeCodeValue
        [Environment]::SetEnvironmentVariable("CLAUDECODE", $null, "Process")
    }
    try {
        if ($adapterType -eq "copilot" -and (Test-UseCopilotCliBridge)) {
            Emit-Log -Level "info" -Message "Using C# Copilot bridge for agent execution" -Component "agent"
            $bridgeResult = Invoke-CopilotCliBridge -AgentConfig $AgentConfig -Prompt $Prompt -WorkingDirectory $agentCwd
            $output = $bridgeResult.Output
            $exitCode = $bridgeResult.ExitCode
            $succeeded = $bridgeResult.Succeeded
            $resolvedExecutable = $bridgeResult.ResolvedExecutable

            if (-not $succeeded) {
                Emit-Error -ErrorType "AgentExecutionFailed" -Message "Copilot bridge exited non-zero (exit code: $exitCode)" -Severity "error" -Context @{
                    agent_name = $AgentConfig.name
                    agent_id   = $AgentConfig.key
                    executable = $executable
                    resolved   = $resolvedExecutable
                    exit_code  = $exitCode
                    bridge     = $true
                }
            }
        }
        else {
            $resolvedExecutable = if (Get-Command Resolve-FelixExecutablePath -ErrorAction SilentlyContinue) {
                Resolve-FelixExecutablePath $executable
            }
            else {
                $null
            }

            if (-not $resolvedExecutable) {
                $message = "Agent executable not found: '$executable'. Ensure it is installed and/or on PATH (Windows npm global shim dir is usually '$($env:APPDATA)\\npm')."
                Emit-Error -ErrorType "AgentExecutableNotFound" -Message $message -Severity "fatal" -Context @{
                    agent_name = $AgentConfig.name
                    agent_id   = $AgentConfig.key
                    executable = $executable
                }

                $duration = (Get-Date) - $startTime
                $output = $message

                $outputPath = Join-Path $RunDir "output.log"
                Set-Content $outputPath $output -Encoding UTF8
                $relPath = $outputPath.Replace($ProjectPath + "\", "")
                Emit-Artifact -Path $relPath -Type "log" -SizeBytes (Get-Item $outputPath).Length

                Write-AgentUsageArtifact `
                    -AgentConfig $AgentConfig `
                    -AdapterType $adapterType `
                    -RunId $RunId `
                    -RunDir $RunDir `
                    -ProjectPath $ProjectPath `
                    -Output $output `
                    -DurationSeconds $duration.TotalSeconds `
                    -ExitCode 127 `
                    -Succeeded $false | Out-Null

                Emit-AgentExecutionCompleted -DurationSeconds $duration.TotalSeconds
                Emit-Log -Level "error" -Message "Execution failed: executable not found" -Component "agent"

                return @{
                    Output             = $output
                    Duration           = $duration
                    Parsed             = @{
                        Output     = $output
                        IsComplete = $false
                        NextMode   = $null
                        Error      = "AgentExecutableNotFound"
                    }
                    ExitCode           = 127
                    Succeeded          = $false
                    ResolvedExecutable = $null
                }
            }

            $processFilePath = $resolvedExecutable
            $processArgs = @($agentArgs)
            if ($resolvedExecutable -and $resolvedExecutable.EndsWith(".ps1")) {
                $processFilePath = "powershell.exe"
                $processArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $resolvedExecutable) + $agentArgs
            }
            elseif ($resolvedExecutable -and ($resolvedExecutable.EndsWith(".cmd") -or $resolvedExecutable.EndsWith(".bat"))) {
                $processFilePath = $resolvedExecutable
                $processArgs = @($agentArgs)
            }

            if ($AgentConfig.environment) {
                foreach ($prop in $AgentConfig.environment.PSObject.Properties) {
                    $key = $prop.Name
                    $value = [string]$prop.Value
                    # Only save the original value if not already backed up (e.g. CLAUDECODE was
                    # pre-cleared above; overwriting the backup here would discard the original).
                    if (-not $envBackup.ContainsKey($key)) {
                        $envBackup[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
                    }
                    [Environment]::SetEnvironmentVariable($key, $value, "Process")
                }
            }

            $processResult = Invoke-AgentSubprocess `
                -ProcessFilePath $processFilePath `
                -ProcessArgs $processArgs `
                -WorkingDirectory $agentCwd `
                -PromptMode $promptMode `
                -Prompt $formattedPrompt `
                -StartTime $startTime `
                -VerboseMode:$VerboseMode

            $output = $processResult.Output
            $exitCode = $processResult.ExitCode
            $succeeded = $processResult.Succeeded

            if ($adapterType -eq "copilot" -and ($processArgs -contains "--model") -and (Test-CopilotModelUnavailableOutput -Output $output)) {
                Emit-Log -Level "warn" -Message "Copilot rejected configured model '$($AgentConfig.model)'; retrying without --model" -Component "agent"
                $retriedWithoutExplicitModel = $true

                $retryProcessArgs = Remove-ArgumentPair -Arguments $processArgs -Flag "--model"
                $retryResult = Invoke-AgentSubprocess `
                    -ProcessFilePath $processFilePath `
                    -ProcessArgs $retryProcessArgs `
                    -WorkingDirectory $agentCwd `
                    -PromptMode $promptMode `
                    -Prompt $formattedPrompt `
                    -StartTime $startTime `
                    -VerboseMode:$VerboseMode

                $output = $retryResult.Output
                $exitCode = $retryResult.ExitCode
                $succeeded = $retryResult.Succeeded

                if ($succeeded) {
                    Emit-Log -Level "info" -Message "Copilot retry without explicit model succeeded" -Component "agent"
                }
            }

            if (-not $succeeded) {
                Emit-Error -ErrorType "AgentExecutionFailed" -Message "Agent process exited non-zero (exit code: $exitCode)" -Severity "error" -Context @{
                    agent_name = $AgentConfig.name
                    agent_id   = $AgentConfig.key
                    executable = $executable
                    resolved   = $resolvedExecutable
                    exit_code  = $exitCode
                }
            }
        }
    }
    catch {
        $succeeded = $false
        $exitCode = 1
        $output = "Agent execution threw an exception: $($_.ToString())"
        Emit-Error -ErrorType "AgentExecutionException" -Message "Agent execution failed: $($_.Exception.Message)" -Severity "fatal" -Context @{
            agent_name = $AgentConfig.name
            agent_id   = $AgentConfig.key
            executable = $executable
            resolved   = $resolvedExecutable
        }
    }
    finally {
        foreach ($key in $envBackup.Keys) {
            [Environment]::SetEnvironmentVariable($key, $envBackup[$key], "Process")
        }
    }
    $duration = (Get-Date) - $startTime
    
    # Parse normalized response using adapter while preserving raw output for artifacts.
    $normalizedOutput = Normalize-AgentOutput -Output $output -AdapterType $adapterType
    $parsedResponse = $adapter.ParseResponse((Get-AgentParseInput -Output $normalizedOutput))
    if (-not $parsedResponse.Output) {
        $parsedResponse.Output = $normalizedOutput
    }
    $parsedResponse.NormalizedOutput = $normalizedOutput
    if (-not $succeeded) {
        $parsedResponse.Error = "AgentExecutionFailed"
    }
    elseif ($parsedResponse.Error) {
        $succeeded = $false
        Emit-Error -ErrorType "AgentReportedFailure" -Message "Agent reported failure: $($parsedResponse.Error)" -Severity "error" -Context @{
            agent_name = $AgentConfig.name
            agent_id   = $AgentConfig.key
        }
    }
    
    # Emit response content for visibility (helps diagnose contract violations).
    # Use the parsed inner text if available so contract-checking signals (<promise> tags)
    # are visible; fall back to normalizedOutput for non-JSON adapters.
    $responseText = if ($parsedResponse.Output -and $parsedResponse.Output -ne $normalizedOutput) {
        $parsedResponse.Output
    }
    else {
        $normalizedOutput
    }
    $previewLen = 3000
    $responsePreview = if ($responseText.Length -gt $previewLen) {
        $responseText.Substring(0, $previewLen)
    }
    else {
        $responseText
    }
    Emit-Event -EventType "agent_response" -Data @{
        content   = $responsePreview
        length    = $responseText.Length
        truncated = ($responseText.Length -gt $previewLen)
    }

    # Write raw output to run directory
    $outputPath = Join-Path $RunDir "output.log"
    Set-Content $outputPath $output -Encoding UTF8
    $relPath = $outputPath.Replace($ProjectPath + "\", "")
    Emit-Artifact -Path $relPath -Type "log" -SizeBytes (Get-Item $outputPath).Length

    $usageRecord = Write-AgentUsageArtifact `
        -AgentConfig $AgentConfig `
        -AdapterType $adapterType `
        -RunId $RunId `
        -RunDir $RunDir `
        -ProjectPath $ProjectPath `
        -Output $output `
        -DurationSeconds $duration.TotalSeconds `
        -ExitCode $exitCode `
        -Succeeded $succeeded `
        -RetriedWithoutExplicitModel:$retriedWithoutExplicitModel
    
    Emit-AgentExecutionCompleted -DurationSeconds $duration.TotalSeconds
    Emit-Log -Level "info" -Message "Execution complete (Duration: $($duration.TotalSeconds.ToString("F1"))s)" -Component "agent"
    
    # Hook: OnPostExecution
    $hookResult = Invoke-PluginHookSafely -HookName "OnPostExecution" -RunId $RunId -HookData @{
        Output         = $output
        Duration       = $duration.TotalSeconds
        ParsedResponse = $parsedResponse
    }
    
    return @{
        Output             = $output
        Duration           = $duration
        Parsed             = $parsedResponse
        NormalizedOutput   = $normalizedOutput
        ExitCode           = $exitCode
        Succeeded          = $succeeded
        ResolvedExecutable = $resolvedExecutable
        Usage              = $usageRecord
    }
}

function Test-AndEnforcePlanningGuardrails {
    <#
    .SYNOPSIS
    Tests and enforces planning mode guardrails
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $BeforeState,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $true)]
        [string]$RunDir,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $true)]
        [string]$StateFile
    )
    
    # Workflow Stage: check_guardrails
    Set-WorkflowStage -Stage "check_guardrails" -ProjectPath $ProjectPath

    if (-not $BeforeState -or -not (Test-GitRepository -WorkingDir $ProjectPath)) {
        Emit-Log -Level "debug" -Message "Skipping planning guardrails: project is not a git repository" -Component "guardrail"
        return @{ Passed = $true }
    }
    
    $violations = Test-PlanningModeGuardrails -WorkingDir $ProjectPath -BeforeState $BeforeState -RunId $RunId
    if ($violations.HasViolations) {
        Undo-PlanningViolations -WorkingDir $ProjectPath -BeforeState $BeforeState -Violations $violations
        
        # Document guardrail violations
        $violationReport = @"
# Planning Mode Guardrail Violation

**Timestamp:** $(Get-Date -Format "o")

## Violations Detected

"@
        
        if ($violations.CommitMade) {
            $violationReport += "`n### Unauthorized Commit`n`nA commit was made during planning mode and has been reverted.`n"
        }
        
        if ($violations.UnauthorizedFiles.Count -gt 0) {
            $violationReport += "`n### Unauthorized File Modifications`n`nThe following files were modified outside allowed paths:`n`n"
            foreach ($file in $violations.UnauthorizedFiles) {
                $violationReport += "- $file`n"
            }
            $violationReport += "`nThese changes have been reverted.`n"
        }
        
        $violationReport += @"

## Allowed Modifications in Planning Mode

- runs/ directory (plan files)
- .felix/state.json (execution state)
- .felix/requirements.json (requirement status)
"@
        
        Set-Content (Join-Path $RunDir "guardrail-violation.md") $violationReport -Encoding UTF8
        $artifactPath = (Join-Path $RunDir "guardrail-violation.md").Replace($ProjectPath + "\", "")
        Emit-Artifact -Path $artifactPath -Type "report" -SizeBytes (Get-Item (Join-Path $RunDir "guardrail-violation.md")).Length
        
        # Update state
        $State.last_iteration_outcome = "guardrail_violation"
        $State.updated_at = Get-Date -Format "o"
        $State | ConvertTo-Json | Set-Content $StateFile
        
        Emit-Error -ErrorType "GuardrailViolation" -Message "Planning mode aborted due to guardrail violations" -Severity "error"
        
        return @{ Passed = $false }
    }
    
    return @{ Passed = $true }
}
