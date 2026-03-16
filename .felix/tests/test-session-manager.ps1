<#
.SYNOPSIS
Tests for session-manager.ps1
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/session-manager.ps1"

Describe "Register-Session" {

    It "should create sessions file with new session" {
        $tempDir = Join-Path $env:TEMP "test-session-$(Get-Random)"
        $felixDir = Join-Path $tempDir ".felix"
        New-Item -ItemType Directory -Path $felixDir -Force | Out-Null

        try {
            Register-Session -SessionId "sess-001" -RequirementId "S-0001" -ProcessId $PID -AgentName "droid" -ProjectPath $tempDir

            $sessionsFile = Join-Path $felixDir "sessions.json"
            Assert-True (Test-Path $sessionsFile) "sessions.json should exist"

            $sessions = Get-Content $sessionsFile -Raw | ConvertFrom-Json
            $session = @($sessions) | Where-Object { $_.session_id -eq "sess-001" }
            Assert-NotNull $session
            Assert-Equal "S-0001" $session.requirement_id
            Assert-Equal "droid" $session.agent
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should append to existing sessions" {
        $tempDir = Join-Path $env:TEMP "test-session-$(Get-Random)"
        $felixDir = Join-Path $tempDir ".felix"
        New-Item -ItemType Directory -Path $felixDir -Force | Out-Null

        try {
            Register-Session -SessionId "sess-001" -RequirementId "S-0001" -ProcessId $PID -AgentName "droid" -ProjectPath $tempDir
            Register-Session -SessionId "sess-002" -RequirementId "S-0002" -ProcessId $PID -AgentName "claude" -ProjectPath $tempDir

            $sessionsFile = Join-Path $felixDir "sessions.json"
            $raw = Get-Content $sessionsFile -Raw
            Assert-True ($raw -match 'sess-001') "Should contain first session"
            Assert-True ($raw -match 'sess-002') "Should contain second session"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Unregister-Session" {

    It "should remove session from file" {
        $tempDir = Join-Path $env:TEMP "test-session-$(Get-Random)"
        $felixDir = Join-Path $tempDir ".felix"
        New-Item -ItemType Directory -Path $felixDir -Force | Out-Null

        try {
            Register-Session -SessionId "sess-001" -RequirementId "S-0001" -ProcessId $PID -AgentName "droid" -ProjectPath $tempDir
            Register-Session -SessionId "sess-002" -RequirementId "S-0002" -ProcessId $PID -AgentName "claude" -ProjectPath $tempDir

            Unregister-Session -SessionId "sess-001" -ProjectPath $tempDir

            $sessionsFile = Join-Path $felixDir "sessions.json"
            $sessions = @(Get-Content $sessionsFile -Raw | ConvertFrom-Json)
            $remaining = @($sessions | Where-Object { $_.session_id -eq "sess-001" })
            Assert-Equal 0 $remaining.Count "Session should be removed"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should handle missing sessions file gracefully" {
        $tempDir = Join-Path $env:TEMP "test-session-$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        try {
            # Should not throw
            Unregister-Session -SessionId "nonexistent" -ProjectPath $tempDir
            Assert-True $true "Should complete without error"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should remove file when last session unregistered" {
        $tempDir = Join-Path $env:TEMP "test-session-$(Get-Random)"
        $felixDir = Join-Path $tempDir ".felix"
        New-Item -ItemType Directory -Path $felixDir -Force | Out-Null

        try {
            Register-Session -SessionId "sess-001" -RequirementId "S-0001" -ProcessId $PID -AgentName "droid" -ProjectPath $tempDir
            Unregister-Session -SessionId "sess-001" -ProjectPath $tempDir

            $sessionsFile = Join-Path $felixDir "sessions.json"
            Assert-False (Test-Path $sessionsFile) "File should be removed when empty"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults
