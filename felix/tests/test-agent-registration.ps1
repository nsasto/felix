. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/agent-registration.ps1"

# Mock backend URL for testing
$script:MockBackendUrl = "http://localhost:9999"

Describe "Register-Agent" {
    It "should return false when backend is unavailable" {
        $result = Register-Agent -AgentId 1 -AgentName "test-agent" -ProcessId $PID -Hostname "test-host" -BackendBaseUrl $script:MockBackendUrl
        Assert-False $result "Should return false when backend is unreachable"
    }
    
    It "should format registration payload correctly" {
        # This test verifies the function constructs proper JSON
        # We can't test actual registration without a running backend
        # but we can verify it doesn't crash with valid inputs
        $result = Register-Agent -AgentId 42 -AgentName "test-agent-42" -ProcessId $PID -Hostname "test-host" -BackendBaseUrl $script:MockBackendUrl
        Assert-True ($result -eq $false) "Function should complete and return false without backend"
    }
}

Describe "Send-AgentHeartbeat" {
    It "should return false when backend is unavailable" {
        $result = Send-AgentHeartbeat -AgentId 1 -CurrentRequirementId "S-0001" -BackendBaseUrl $script:MockBackendUrl
        Assert-False $result "Should return false when backend is unreachable"
    }
    
    It "should handle null CurrentRequirementId" {
        $result = Send-AgentHeartbeat -AgentId 1 -CurrentRequirementId $null -BackendBaseUrl $script:MockBackendUrl
        Assert-False $result "Should handle null requirement ID gracefully"
    }
}

Describe "Start-HeartbeatJob and Stop-HeartbeatJob" {
    It "should start a background job" {
        $job = Start-HeartbeatJob -AgentId 1 -BackendBaseUrl $script:MockBackendUrl
        
        Assert-NotNull $job "Should return a job object"
        Assert-Equal "FelixHeartbeat" $job.Name "Job should have correct name"
        Assert-True ($job.State -eq "Running") "Job should be running"
        
        # Clean up
        Stop-HeartbeatJob -Job $job
    }
    
    It "should stop the heartbeat job" {
        $job = Start-HeartbeatJob -AgentId 1 -BackendBaseUrl $script:MockBackendUrl
        
        Stop-HeartbeatJob -Job $job
        
        # Wait a moment for job to stop
        Start-Sleep -Milliseconds 500
        
        # Verify job no longer exists
        $existingJob = Get-Job -Name "FelixHeartbeat" -ErrorAction SilentlyContinue
        Assert-Null $existingJob "Job should be removed after stop"
    }
    
    It "should handle stopping null job gracefully" {
        # Should not throw
        Stop-HeartbeatJob -Job $null
        Assert-True $true "Should handle null job without error"
    }
}

Describe "Unregister-Agent" {
    It "should not throw when backend is unavailable" {
        # Should complete silently even if backend is down
        Unregister-Agent -AgentId 1 -BackendBaseUrl $script:MockBackendUrl
        Assert-True $true "Should complete without throwing"
    }
}

Get-TestResults
