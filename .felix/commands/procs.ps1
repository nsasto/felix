
function Invoke-ProcessList {
    param([string[]]$Arguments)
    
    # Load session manager
    . "$PSScriptRoot\..\core\session-manager.ps1"
    
    $subCmd = if ($Arguments -and $Arguments.Count -gt 0) { $Arguments[0] } else { "list" }
    
    # Handle array extraction carefully - PowerShell unwraps single-element @() arrays
    $subArgs = if ($Arguments.Count -eq 2) {
        $temp = [System.Collections.ArrayList]@()
        $null = $temp.Add($Arguments[1])
        , $temp.ToArray()
    }
    elseif ($Arguments.Count -gt 2) {
        $Arguments[1..($Arguments.Count - 1)]
    }
    else {
        @()
    }
    
    switch ($subCmd) {
        "list" {
            $sessions = Get-ActiveSessions -ProjectPath $RepoRoot
            
            if ($sessions.Count -eq 0) {
                Write-Host ""
                Write-Host "No active sessions" -ForegroundColor Gray
                Write-Host ""
                exit 0
            }
            
            Write-Host ""
            Write-Host "Active Sessions:" -ForegroundColor Cyan
            Write-Host ""
            
            $sessions | ForEach-Object {
                $duration = (Get-Date).ToUniversalTime() - [DateTime]::Parse($_.start_time)
                $durationStr = if ($duration.TotalHours -ge 1) {
                    "{0:hh\:mm\:ss}" -f $duration
                }
                else {
                    "{0:mm\:ss}" -f $duration
                }
                
                Write-Host "  Session: $($_.session_id)" -ForegroundColor Yellow
                Write-Host "  Requirement: $($_.requirement_id)" -ForegroundColor White
                Write-Host "  Agent: $($_.agent)" -ForegroundColor Gray
                Write-Host "  PID: $($_.pid)" -ForegroundColor Gray
                Write-Host "  Duration: $durationStr" -ForegroundColor Gray
                Write-Host "  Status: $($_.status)" -ForegroundColor $(if ($_.status -eq "running") { "Green" } else { "Yellow" })
                Write-Host ""
            }
            
            Write-Host "Commands:" -ForegroundColor Cyan
            Write-Host "  felix procs kill <session-id>    Terminate a session"
            Write-Host "  felix procs kill all             Terminate all sessions"
            Write-Host ""
        }
        "kill" {
            if ($subArgs.Count -eq 0) {
                Write-Error "Usage: felix procs kill <session-id|all>"
                Write-Host ""
                Write-Host "Tip: Use 'felix procs list' to see active sessions"
                Write-Host ""
                exit 1
            }

            $target = $subArgs[0]

            if ($target -eq "all") {
                $sessions = Get-ActiveSessions -ProjectPath $RepoRoot

                if ($sessions.Count -eq 0) {
                    Write-Host ""
                    Write-Host "No active sessions to kill" -ForegroundColor Gray
                    Write-Host ""
                    exit 0
                }

                Write-Host ""
                Write-Host "Terminating $($sessions.Count) session(s)..." -ForegroundColor Yellow
                Write-Host ""

                $failed = 0
                foreach ($session in $sessions) {
                    $success = Stop-Session -SessionId $session.session_id -ProjectPath $RepoRoot
                    if ($success) {
                        Write-Host "  Killed: $($session.session_id) (req: $($session.requirement_id), PID: $($session.pid))" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  Failed: $($session.session_id)" -ForegroundColor Red
                        $failed++
                    }
                }

                Write-Host ""
                if ($failed -eq 0) {
                    Write-Host "All sessions terminated" -ForegroundColor Green
                }
                else {
                    Write-Host "$failed session(s) could not be terminated" -ForegroundColor Yellow
                }
                Write-Host ""
                if ($failed -gt 0) { exit 1 }
            }
            else {
                $sessionId = $target

                Write-Host ""
                Write-Host "Terminating session: $sessionId" -ForegroundColor Yellow
                Write-Host ""

                $success = Stop-Session -SessionId $sessionId -ProjectPath $RepoRoot

                if ($success) {
                    Write-Host "Session terminated successfully" -ForegroundColor Green
                    Write-Host ""
                }
                else {
                    Write-Host "Failed to terminate session" -ForegroundColor Red
                    Write-Host ""
                    exit 1
                }
            }
        }
        default {
            Write-Error "Unknown procs subcommand: $subCmd"
            Write-Host "Usage: felix procs <list|kill> [args]"
            exit 1
        }
    }
}
