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
        [string]$Output
    )

    return $Output -match 'Model\s+"[^"]+"\s+from\s+--model\s+flag\s+is\s+not\s+available'
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
        [datetime]$StartTime
    )

    $inputPath = $null
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()

    try {
        if ($PromptMode -eq "stdin") {
            $inputPath = [System.IO.Path]::GetTempFileName()
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($inputPath, $Prompt, $utf8NoBom)
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
        }

        $process.WaitForExit()
        $exitCode = [int]$process.ExitCode

        $stdout = ""
        $stderr = ""
        if (Test-Path $stdoutPath) { $stdout = Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue }
        if (Test-Path $stderrPath) { $stderr = Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue }

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
        foreach ($path in @($inputPath, $stdoutPath, $stderrPath)) {
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

            if ($AgentConfig.environment) {
                foreach ($prop in $AgentConfig.environment.PSObject.Properties) {
                    $key = $prop.Name
                    $value = [string]$prop.Value
                    $envBackup[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
                    [Environment]::SetEnvironmentVariable($key, $value, "Process")
                }
            }

            $processResult = Invoke-AgentSubprocess `
                -ProcessFilePath $processFilePath `
                -ProcessArgs $processArgs `
                -WorkingDirectory $agentCwd `
                -PromptMode $promptMode `
                -Prompt $formattedPrompt `
                -StartTime $startTime

            $output = $processResult.Output
            $exitCode = $processResult.ExitCode
            $succeeded = $processResult.Succeeded

            if ($adapterType -eq "copilot" -and ($processArgs -contains "--model") -and (Test-CopilotModelUnavailableOutput -Output $output)) {
                Emit-Log -Level "warn" -Message "Copilot rejected configured model '$($AgentConfig.model)'; retrying without --model" -Component "agent"

                $retryProcessArgs = Remove-ArgumentPair -Arguments $processArgs -Flag "--model"
                $retryResult = Invoke-AgentSubprocess `
                    -ProcessFilePath $processFilePath `
                    -ProcessArgs $retryProcessArgs `
                    -WorkingDirectory $agentCwd `
                    -PromptMode $promptMode `
                    -Prompt $formattedPrompt `
                    -StartTime $startTime

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
    $parsedResponse = $adapter.ParseResponse($normalizedOutput)
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
