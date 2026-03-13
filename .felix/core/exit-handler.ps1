<#
.SYNOPSIS
Clean shutdown and exit handling for Felix agent

.DESCRIPTION
Provides functions for graceful agent termination with proper cleanup,
and utility functions for data conversion.
#>

function Exit-FelixAgent {
    <#
    .SYNOPSIS
    Cleanly exit the agent with proper cleanup
    
    .PARAMETER ExitCode
    Exit code to return (default: 0)
    
    .PARAMETER ProjectPath
    Project path for clearing workflow stage
    
    .PARAMETER AgentId
    Agent ID for unregistering from backend
    
    .PARAMETER HeartbeatJob
    Background job to stop
    
    .PARAMETER RunContext
    Optional run context for plugin hooks (requirement, iteration, paths, etc.)
    #>
    param(
        [Parameter(Mandatory = $false)]
        [int]$ExitCode = 0,
        
        [Parameter(Mandatory = $false)]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $false)]
        [string]$AgentId,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.Job]$HeartbeatJob,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$RunContext
    )
    
    # Log entry to Exit-Felix Agent
    if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
        Emit-Log -Level "debug" -Message "Exit-FelixAgent called with ExitCode=$ExitCode, HasRunContext=$($null -ne $RunContext)" -Component "exit"
    }
    
    # Clear workflow stage on exit
    if ($ProjectPath) {
        # Ensure workflow module is loaded
        if (Get-Command Set-WorkflowStage -ErrorAction SilentlyContinue) {
            Set-WorkflowStage -Clear -ProjectPath $ProjectPath
        }
    }
    
    # Stop heartbeat job
    if ($HeartbeatJob) {
        if (Get-Command Stop-HeartbeatJob -ErrorAction SilentlyContinue) {
            Stop-HeartbeatJob -Job $HeartbeatJob
        }
    }

    # Release work claim back to server queue on failure so another agent can pick it up.
    # On success (exit 0) the requirement is already marked complete by spec-sync; skip release.
    if ($ExitCode -ne 0 -and $RunContext -and $RunContext.Requirement -and $RunContext.Config) {
        $reqCode = $RunContext.Requirement.code
        $syncCfg = $RunContext.Config.sync
        $syncOn  = $syncCfg -and ($syncCfg.enabled -eq $true -or $syncCfg.enabled -eq "true")
        $syncUrl = if ($syncCfg) { $syncCfg.base_url } else { $null }
        if ($reqCode -and $syncOn -and $syncUrl) {
            if (Get-Command Send-WorkRelease -ErrorAction SilentlyContinue) {
                $apiKey = if ($syncCfg.api_key) { $syncCfg.api_key } else { "" }
                Send-WorkRelease -RequirementCode $reqCode -BaseUrl $syncUrl -ApiKey $apiKey
            }
            else {
                # Inline fallback in case work-selector isn't dot-sourced
                try {
                    $rHeaders = @{ "Content-Type" = "application/json" }
                    if ($syncCfg.api_key) { $rHeaders["Authorization"] = "Bearer $($syncCfg.api_key)" }
                    $rBody = @{ code = $reqCode } | ConvertTo-Json
                    Invoke-RestMethod -Uri "$($syncUrl.TrimEnd('/'))/api/sync/work/release" -Method POST -Headers $rHeaders -Body $rBody -ErrorAction Stop | Out-Null
                    Emit-Log -Level "info" -Message "Released $reqCode back to server queue (exit $ExitCode)" -Component "exit"
                }
                catch {
                    Emit-Log -Level "warn" -Message "Failed to release $reqCode on exit: $_" -Component "exit"
                }
            }
        }
    }

    # Unregister agent if we have an agent ID
    if ($AgentId) {
        if (Get-Command Unregister-Agent -ErrorAction SilentlyContinue) {
            if ($script:BackendBaseUrl) {
                Unregister-Agent -AgentId $AgentId -BackendBaseUrl $script:BackendBaseUrl
            }
        }
    }
    
    # Emit final run completion event
    if (Get-Command Emit-RunCompleted -ErrorAction SilentlyContinue) {
        $status = if ($ExitCode -eq 0) { "success" } elseif ($ExitCode -eq 2) { "blocked_backpressure" } elseif ($ExitCode -eq 3) { "blocked_validation" } else { "error" }
        Emit-RunCompleted -Status $status -ExitCode $ExitCode -DurationSeconds 0
        
        # Force flush to ensure completion event is delivered
        try {
            [Console]::Out.Flush()
        }
        catch {
            # Ignore flush errors
        }
        
        # Brief delay to ensure subprocess can read final output
        Start-Sleep -Milliseconds 100
    }
    
    # Invoke OnRunComplete plugin hook (sync, cleanup, etc.)
    if ($script:PluginCache -and $RunContext) {
        try {
            if (Get-Command Invoke-PluginHookSafely -ErrorAction SilentlyContinue) {
                # Use RunId from Paths if available, fallback to script-scoped RunId
                $hookRunId = if ($RunContext.Paths -and $RunContext.Paths.RunId) { $RunContext.Paths.RunId } else { $script:RunId }
                if (-not $hookRunId) {
                    # Generate RunId from requirement if not available (format: REQ-{timestamp})
                    $hookRunId = if ($RunContext.Requirement) { 
                        "$($RunContext.Requirement.id)-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    }
                    else { 
                        "unknown-$(Get-Date -Format 'yyyyMMdd-HHmmss')" 
                    }
                }
                
                if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                    Emit-Log -Level "debug" -Message "Invoking OnRunComplete hook with RunId: $hookRunId" -Component "plugins"
                }
                
                Invoke-PluginHookSafely -HookName "OnRunComplete" -RunId $hookRunId -HookData $RunContext | Out-Null
            }
            else {
                if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                    Emit-Log -Level "warn" -Message "Invoke-PluginHookSafely command not available, skipping OnRunComplete hook" -Component "plugins"
                }
            }
        }
        catch {
            # Don't let plugin errors prevent clean exit, but log the error for debugging
            if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                Emit-Log -Level "warn" -Message "OnRunComplete hook failed: $($_.Exception.Message)" -Component "plugins"
            }
        }
    }
    elseif ($RunContext) {
        if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
            Emit-Log -Level "debug" -Message "Skipping OnRunComplete hook: PluginCache not initialized (PluginCache=$($null -eq $script:PluginCache))" -Component "plugins"
        }
    }
    
    # Final log before exit
    if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
        Emit-Log -Level "debug" -Message "About to exit with code: $ExitCode" -Component "exit"
    }
    
    Write-Host "[EXIT-HANDLER] About to call exit with code: $ExitCode" -ForegroundColor Cyan
    exit $ExitCode
}

function ConvertTo-Hashtable {
    <#
    .SYNOPSIS
    Recursively converts PSCustomObject to hashtable
    
    .PARAMETER InputObject
    Object to convert (can be piped)
    
    .OUTPUTS
    Hashtable or original object if not convertible
    
    .DESCRIPTION
    Useful for converting JSON deserialization results to mutable hashtables.
    Handles nested objects and arrays recursively.
    #>
    param(
        [Parameter(ValueFromPipeline)]
        $InputObject
    )
    
    process {
        if ($null -eq $InputObject) { 
            return $null 
        }
        
        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @(
                foreach ($object in $InputObject) { 
                    ConvertTo-Hashtable $object 
                }
            )
            return , $collection
        }
        elseif ($InputObject -is [PSCustomObject]) {
            $hashtable = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hashtable[$property.Name] = ConvertTo-Hashtable $property.Value
            }
            return $hashtable
        }
        else {
            return $InputObject
        }
    }
}

