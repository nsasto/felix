<#
.SYNOPSIS
Shared state management for HTTP sync plugin

.DESCRIPTION
Manages sync client instance, run tracking, event queue, and throttle timers
#>

# Import HTTP client
. "$PSScriptRoot/http-client.ps1"

# Plugin state (shared across all hooks)
if (-not $Global:HttpSyncState) {
    $Global:HttpSyncState = @{
        Client = $null
        RunId = $null
        EventQueue = [System.Collections.ArrayList]::new()
        LastEventFlush = [datetime]::MinValue
        LastStatusUpdate = [datetime]::MinValue
        FlushTimer = $null
        RunStartTime = $null
    }
}

function Initialize-HttpSyncClient {
    <#
    .SYNOPSIS
    Initialize the HTTP sync client
    
    .PARAMETER Config
    Plugin configuration from Felix config
    
    .PARAMETER FelixDir
    Path to .felix directory for outbox
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$FelixDir
    )
    
    # Build sync config with precedence: env var > config file
    $syncConfig = @{
        base_url = if ($env:FELIX_SYNC_URL) { $env:FELIX_SYNC_URL } else { $Config.sync.base_url }
        api_key = if ($env:FELIX_SYNC_KEY) { $env:FELIX_SYNC_KEY } else { $Config.sync.api_key }
    }
    
    # Initialize HttpSync client
    $Global:HttpSyncState.Client = [HttpSync]::new($syncConfig, $FelixDir)
    
    Write-Verbose "[sync-http] Client initialized: $($syncConfig.base_url)"
}

function Start-EventFlushTimer {
    <#
    .SYNOPSIS
    Start background timer to flush events
    
    .PARAMETER IntervalSeconds
    Flush interval in seconds (default: 5)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$IntervalSeconds = 5
    )
    
    if ($Global:HttpSyncState.FlushTimer) {
        Write-Verbose "[sync-http] Flush timer already running"
        return
    }
    
    $Global:HttpSyncState.FlushTimer = [System.Timers.Timer]::new($IntervalSeconds * 1000)
    $Global:HttpSyncState.FlushTimer.AutoReset = $true
    
    # Register event handler
    Register-ObjectEvent -InputObject $Global:HttpSyncState.FlushTimer -EventName Elapsed -Action {
        try {
            & "$PSScriptRoot/sync-state.ps1"
            Invoke-EventFlush
        }
        catch {
            Write-Verbose "[sync-http] Flush timer error: $_"
        }
    } | Out-Null
    
    $Global:HttpSyncState.FlushTimer.Start()
    Write-Verbose "[sync-http] Event flush timer started (${IntervalSeconds}s interval)"
}

function Stop-EventFlushTimer {
    <#
    .SYNOPSIS
    Stop and dispose flush timer
    #>
    if ($Global:HttpSyncState.FlushTimer) {
        $Global:HttpSyncState.FlushTimer.Stop()
        $Global:HttpSyncState.FlushTimer.Dispose()
        $Global:HttpSyncState.FlushTimer = $null
        Write-Verbose "[sync-http] Flush timer stopped"
    }
}

function Invoke-EventFlush {
    <#
    .SYNOPSIS
    Flush queued events to backend (batch)
    #>
    $state = $Global:HttpSyncState
    
    if (-not $state.Client -or -not $state.RunId) {
        return
    }
    
    if ($state.EventQueue.Count -eq 0) {
        return
    }
    
    try {
        # Copy and clear queue
        $events = $state.EventQueue.ToArray()
        $state.EventQueue.Clear()
        
        # Send batch
        $state.Client.AppendEvents($state.RunId, $events)
        $state.LastEventFlush = Get-Date
        
        Write-Verbose "[sync-http] Flushed $($events.Count) events"
    }
    catch {
        # Re-queue on failure (outbox will handle retry)
        foreach ($event in $events) {
            $state.EventQueue.Add($event) | Out-Null
        }
        Write-Verbose "[sync-http] Flush failed, events re-queued: $_"
    }
}

function Add-EventToQueue {
    <#
    .SYNOPSIS
    Add event to queue for batching
    
    .PARAMETER Event
    Event hashtable to queue
    
    .PARAMETER Flush
    Force immediate flush (for critical events)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Event,
        
        [Parameter(Mandatory = $false)]
        [switch]$Flush
    )
    
    $Global:HttpSyncState.EventQueue.Add($Event) | Out-Null
    
    if ($Flush) {
        Invoke-EventFlush
    }
}

function Update-RunStatus {
    <#
    .SYNOPSIS
    Update run status with throttling
    
    .PARAMETER Status
    Status hashtable
    
    .PARAMETER Force
    Bypass throttling
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Status,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    $state = $Global:HttpSyncState
    
    if (-not $state.Client -or -not $state.RunId) {
        return
    }
    
    # Throttle: max 1/second unless forced
    $elapsed = (Get-Date) - $state.LastStatusUpdate
    if (-not $Force -and $elapsed.TotalMilliseconds -lt 1000) {
        Write-Verbose "[sync-http] Status update throttled ($($elapsed.TotalMilliseconds)ms since last)"
        return
    }
    
    try {
        # Queue as status_update event
        $statusEvent = @{
            type = "status_update"
            timestamp = Get-Date -Format "o"
            data = $Status
        }
        
        Add-EventToQueue -Event $statusEvent -Flush:$Force
        
        $state.LastStatusUpdate = Get-Date
        Write-Verbose "[sync-http] Status updated: $($Status | ConvertTo-Json -Compress)"
    }
    catch {
        Write-Verbose "[sync-http] Status update failed: $_"
    }
}
