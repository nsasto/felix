# session-manager.ps1
# Manages active felix agent sessions for tracking and control

function Register-Session {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        
        [Parameter(Mandatory = $true)]
        [string]$RequirementId,
        
        [Parameter(Mandatory = $true)]
        [int]$ProcessId,
        
        [Parameter(Mandatory = $true)]
        [string]$AgentName,
        
        [string]$ProjectPath = $PWD
    )
    
    $sessionsFile = Join-Path (Join-Path $ProjectPath ".felix") "sessions.json"
    
    # Load existing sessions
    $sessions = @()
    if (Test-Path $sessionsFile) {
        try {
            $content = Get-Content $sessionsFile -Raw | ConvertFrom-Json
            $sessions = @($content)
        }
        catch {
            # Corrupt file, start fresh
            $sessions = @()
        }
    }
    
    # Clean up stale sessions (PIDs that no longer exist)
    $activeSessions = $sessions | Where-Object {
        $proc = Get-Process -Id $_.pid -ErrorAction SilentlyContinue
        $null -ne $proc
    }
    
    # Add new session
    $newSession = @{
        session_id     = $SessionId
        requirement_id = $RequirementId
        pid            = $ProcessId
        agent          = $AgentName
        start_time     = (Get-Date).ToUniversalTime().ToString("o")
        status         = "running"
    }
    
    $activeSessions = @($activeSessions) + $newSession
    
    # Save
    $activeSessions | ConvertTo-Json -Depth 10 | Set-Content $sessionsFile -Encoding UTF8
}

function Unregister-Session {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        
        [string]$ProjectPath = $PWD
    )
    
    $sessionsFile = Join-Path (Join-Path $ProjectPath ".felix") "sessions.json"
    
    if (-not (Test-Path $sessionsFile)) {
        return
    }
    
    try {
        $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json
        $sessions = @($sessions | Where-Object { $_.session_id -ne $SessionId })
        
        if ($sessions.Count -eq 0) {
            Remove-Item $sessionsFile -Force -ErrorAction SilentlyContinue
        }
        else {
            $sessions | ConvertTo-Json -Depth 10 | Set-Content $sessionsFile -Encoding UTF8
        }
    }
    catch {
        # Ignore errors during cleanup
    }
}

function Get-ActiveSessions {
    param(
        [string]$ProjectPath = $PWD
    )
    
    $sessionsFile = Join-Path (Join-Path $ProjectPath ".felix") "sessions.json"
    
    if (-not (Test-Path $sessionsFile)) {
        return @()
    }
    
    try {
        $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json
        
        # Verify each session's process is still running
        $activeSessions = @()
        $needsUpdate = $false
        
        foreach ($session in $sessions) {
            $proc = Get-Process -Id $session.pid -ErrorAction SilentlyContinue
            if ($proc) {
                $activeSessions += $session
            }
            else {
                $needsUpdate = $true
            }
        }
        
        # Clean up if stale sessions were found
        if ($needsUpdate) {
            if ($activeSessions.Count -eq 0) {
                Remove-Item $sessionsFile -Force -ErrorAction SilentlyContinue
            }
            else {
                $activeSessions | ConvertTo-Json -Depth 10 | Set-Content $sessionsFile -Encoding UTF8
            }
        }
        
        return $activeSessions
    }
    catch {
        return @()
    }
}

function Stop-Session {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionId,
        
        [string]$ProjectPath = $PWD
    )
    
    $sessions = Get-ActiveSessions -ProjectPath $ProjectPath
    $session = $sessions | Where-Object { $_.session_id -eq $SessionId } | Select-Object -First 1
    
    if (-not $session) {
        Write-Error "Session not found: $SessionId"
        return $false
    }
    
    try {
        $proc = Get-Process -Id $session.pid -ErrorAction SilentlyContinue
        if ($proc) {
            # Use taskkill for cross-version compatibility (kills process tree)
            # PowerShell 5.1 doesn't support Kill($true), PowerShell 7+ does
            if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
                # Windows: use taskkill to kill process tree
                & taskkill /F /T /PID $session.pid 2>&1 | Out-Null
            }
            else {
                # Unix-like: use Kill with tree parameter if available
                try {
                    $proc.Kill($true)
                }
                catch {
                    # Fallback for older PowerShell versions
                    $proc.Kill()
                }
            }
            
            Start-Sleep -Milliseconds 500
            
            # Verify it's dead
            $proc = Get-Process -Id $session.pid -ErrorAction SilentlyContinue
            if ($proc) {
                Write-Warning "Process $($session.pid) did not terminate immediately"
            }
        }
        
        # Remove from sessions file
        Unregister-Session -SessionId $SessionId -ProjectPath $ProjectPath
        return $true
    }
    catch {
        Write-Error "Failed to stop session: $_"
        return $false
    }
}
