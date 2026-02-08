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
    #>
    param(
        [Parameter(Mandatory = $false)]
        [int]$ExitCode = 0,
        
        [Parameter(Mandatory = $false)]
        [string]$ProjectPath,
        
        [Parameter(Mandatory = $false)]
        [int]$AgentId,

        [Parameter(Mandatory = $false)]
        [string]$BackendBaseUrl,
        
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.Job]$HeartbeatJob
    )
    
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
    
    # Unregister agent if we have an agent ID
    if ($AgentId) {
        if (Get-Command Unregister-Agent -ErrorAction SilentlyContinue) {
            if ($BackendBaseUrl) {
                Unregister-Agent -AgentId $AgentId -BackendBaseUrl $BackendBaseUrl
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

