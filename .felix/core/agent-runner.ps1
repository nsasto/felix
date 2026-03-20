<#
.SYNOPSIS
Agent process executor and planning guardrails

.DESCRIPTION
Handles agent subprocess execution via adapter and enforces planning mode restrictions.
#>

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
    $resolvedExecutable = $null
    $invocation = Get-AgentInvocation -AdapterType $adapterType -Config $AgentConfig -Prompt $Prompt -VerboseMode:$VerboseMode.IsPresent
    $formattedPrompt = $invocation.FormattedPrompt
    $agentArgs = @($invocation.Arguments)
    $promptMode = $invocation.PromptMode
    $agentWorkingDir = if ($AgentConfig.working_directory) { $AgentConfig.working_directory } else { "." }
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

        # Write raw output to run directory
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

    # Execute the agent and capture output
    $agentCwd = if ([System.IO.Path]::IsPathRooted($agentWorkingDir)) {
        $agentWorkingDir
    }
    else {
        Join-Path $ProjectPath $agentWorkingDir
    }

    $processFilePath = $resolvedExecutable
    $processArgs = @($agentArgs)
    if ($resolvedExecutable -and $resolvedExecutable.EndsWith(".ps1")) {
        $processFilePath = "powershell.exe"
        $processArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $resolvedExecutable) + $agentArgs
    }

    $envBackup = @{}
    $exitCode = 0
    $succeeded = $true
    try {
        # Apply agent environment variables (best-effort)
        if ($AgentConfig.environment) {
            foreach ($prop in $AgentConfig.environment.PSObject.Properties) {
                $key = $prop.Name
                $value = [string]$prop.Value
                $envBackup[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }

        # Execute using Start-Process + redirected streams to avoid PowerShell treating stderr lines as errors
        $inputPath = $null
        $stdoutPath = [System.IO.Path]::GetTempFileName()
        $stderrPath = [System.IO.Path]::GetTempFileName()

        try {
            if ($promptMode -eq "stdin") {
                $inputPath = [System.IO.Path]::GetTempFileName()
                $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                [System.IO.File]::WriteAllText($inputPath, $formattedPrompt, $utf8NoBom)
            }

            $argString = (@($processArgs) | ForEach-Object {
                    $a = [string]$_
                    if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
                }) -join ' '

            if ($promptMode -eq "stdin") {
                $p = Start-Process `
                    -FilePath $processFilePath `
                    -ArgumentList $argString `
                    -WorkingDirectory $agentCwd `
                    -NoNewWindow `
                    -PassThru `
                    -RedirectStandardInput $inputPath `
                    -RedirectStandardOutput $stdoutPath `
                    -RedirectStandardError $stderrPath
            }
            else {
                $p = Start-Process `
                    -FilePath $processFilePath `
                    -ArgumentList $argString `
                    -WorkingDirectory $agentCwd `
                    -NoNewWindow `
                    -PassThru `
                    -RedirectStandardOutput $stdoutPath `
                    -RedirectStandardError $stderrPath
            }

            # Poll for process exit, emitting heartbeat events every 20s so the
            # NDJSON consumer and server know the agent is alive during long LLM calls.
            # (Start-Process -Wait would block the PS thread, preventing any emission.)
            $heartbeatIntervalSec = 20
            $lastHeartbeat = Get-Date
            while (-not $p.HasExited) {
                Start-Sleep -Milliseconds 500
                $elapsed = ((Get-Date) - $lastHeartbeat).TotalSeconds
                if ($elapsed -ge $heartbeatIntervalSec) {
                    Emit-Event -EventType "agent_heartbeat" -Data @{
                        agent_running   = $true
                        elapsed_seconds = [int]((Get-Date) - $startTime).TotalSeconds
                    }
                    $lastHeartbeat = Get-Date
                }
            }
            $p.WaitForExit()
            $exitCode = [int]$p.ExitCode

            $stdout = ""
            $stderr = ""
            if (Test-Path $stdoutPath) { $stdout = Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue }
            if (Test-Path $stderrPath) { $stderr = Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue }

            $output = $stdout
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                if (-not [string]::IsNullOrWhiteSpace($output)) { $output += "`n" }
                $output += $stderr
            }

            if ($exitCode -ne 0) {
                $succeeded = $false
                Emit-Error -ErrorType "AgentExecutionFailed" -Message "Agent process exited non-zero (exit code: $exitCode)" -Severity "error" -Context @{
                    agent_name = $AgentConfig.name
                    agent_id   = $AgentConfig.key
                    executable = $executable
                    resolved   = $resolvedExecutable
                    exit_code  = $exitCode
                }
            }
        }
        finally {
            foreach ($path in @($inputPath, $stdoutPath, $stderrPath)) {
                try { if ($path -and (Test-Path $path)) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } } catch { }
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
    
    # Parse response using adapter
    $parsedResponse = $adapter.ParseResponse($output)
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
