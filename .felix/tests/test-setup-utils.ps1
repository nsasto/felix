<#
.SYNOPSIS
Tests for setup-utils.ps1 - Copy-EngineFile, Test-ExecutableInstalled, New-AgentKey, Build-AgentRegistrationPayload
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/setup-utils.ps1"

Describe "Copy-EngineFile" {

    It "should copy file when source exists and dest does not" {
        $srcDir = Join-Path $env:TEMP "test-engine-$(Get-Random)"
        $destDir = Join-Path $env:TEMP "test-dest-$(Get-Random)"
        New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Set-Content (Join-Path $srcDir "test.txt") "hello" -Encoding UTF8

        try {
            $result = Copy-EngineFile -FelixRoot $srcDir -FelixDir $destDir -RelPath "test.txt"
            Assert-True $result "Should return true on copy"
            Assert-True (Test-Path (Join-Path $destDir "test.txt")) "File should exist at destination"
        }
        finally {
            Remove-Item $srcDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $destDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should not copy when dest already exists" {
        $srcDir = Join-Path $env:TEMP "test-engine-$(Get-Random)"
        $destDir = Join-Path $env:TEMP "test-dest-$(Get-Random)"
        New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Set-Content (Join-Path $srcDir "test.txt") "source" -Encoding UTF8
        Set-Content (Join-Path $destDir "test.txt") "dest" -Encoding UTF8

        try {
            $result = Copy-EngineFile -FelixRoot $srcDir -FelixDir $destDir -RelPath "test.txt"
            Assert-False $result "Should return false when dest exists"
            $content = Get-Content (Join-Path $destDir "test.txt") -Raw
            Assert-True ($content -match "dest") "Dest file should be unchanged"
        }
        finally {
            Remove-Item $srcDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $destDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should return false when source does not exist" {
        $srcDir = Join-Path $env:TEMP "test-engine-$(Get-Random)"
        $destDir = Join-Path $env:TEMP "test-dest-$(Get-Random)"
        New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null

        try {
            $result = Copy-EngineFile -FelixRoot $srcDir -FelixDir $destDir -RelPath "nonexistent.txt"
            Assert-False $result
        }
        finally {
            Remove-Item $srcDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $destDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should create intermediate directories for nested path" {
        $srcDir = Join-Path $env:TEMP "test-engine-$(Get-Random)"
        $destDir = Join-Path $env:TEMP "test-dest-$(Get-Random)"
        $nestedSrc = Join-Path $srcDir "sub\dir"
        New-Item -ItemType Directory -Path $nestedSrc -Force | Out-Null
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Set-Content (Join-Path $nestedSrc "file.txt") "nested" -Encoding UTF8

        try {
            $result = Copy-EngineFile -FelixRoot $srcDir -FelixDir $destDir -RelPath "sub\dir\file.txt"
            Assert-True $result
            Assert-True (Test-Path (Join-Path $destDir "sub\dir\file.txt"))
        }
        finally {
            Remove-Item $srcDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $destDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Test-ExecutableInstalled" {

    It "should return true for powershell" {
        $result = Test-ExecutableInstalled -ExecutableName "powershell"
        Assert-True $result
    }

    It "should return false for nonexistent executable" {
        $result = Test-ExecutableInstalled -ExecutableName "nonexistent-xyz-12345"
        Assert-False $result
    }
}

Describe "New-AgentKey" {

    It "should produce deterministic key" {
        $key1 = New-AgentKey -Provider "droid" -Model "o3" -AgentSettings @{} -ProjectRoot $env:TEMP
        $key2 = New-AgentKey -Provider "droid" -Model "o3" -AgentSettings @{} -ProjectRoot $env:TEMP
        Assert-Equal $key1 $key2
    }

    It "should produce different keys for different providers" {
        $key1 = New-AgentKey -Provider "droid" -Model "o3" -AgentSettings @{} -ProjectRoot $env:TEMP
        $key2 = New-AgentKey -Provider "claude" -Model "o3" -AgentSettings @{} -ProjectRoot $env:TEMP
        Assert-True ($key1 -ne $key2) "Different providers should produce different keys"
    }

    It "should produce different keys for different models" {
        $key1 = New-AgentKey -Provider "droid" -Model "o3" -AgentSettings @{} -ProjectRoot $env:TEMP
        $key2 = New-AgentKey -Provider "droid" -Model "gpt-4" -AgentSettings @{} -ProjectRoot $env:TEMP
        Assert-True ($key1 -ne $key2) "Different models should produce different keys"
    }

    It "should match ag_ prefix format" {
        $key = New-AgentKey -Provider "droid" -Model "o3" -AgentSettings @{} -ProjectRoot $env:TEMP
        Assert-True ($key -match '^ag_[a-f0-9]{9}$') "Key should match ag_XXXXXXXXX format"
    }

    It "should handle empty settings" {
        $key = New-AgentKey -Provider "droid" -Model "o3" -ProjectRoot $env:TEMP
        Assert-True ($key -match '^ag_') "Key should start with ag_"
    }
}

Describe "Build-AgentRegistrationPayload" {

    It "should build payload with correct provider from adapter" {
        $agentConfig = [PSCustomObject]@{
            name    = "my-agent"
            adapter = "claude"
            model   = "opus-4"
        }
        $payload = Build-AgentRegistrationPayload -AgentConfig $agentConfig -ProjectRoot $env:TEMP
        Assert-Equal "claude" $payload.provider
        Assert-Equal "opus-4" $payload.model
        Assert-Equal "my-agent" $payload.name
        Assert-True ($payload.key -match '^ag_') "Key should have ag_ prefix"
    }

    It "should use name as provider when no adapter field" {
        $agentConfig = [PSCustomObject]@{
            name  = "droid"
            model = "o3"
        }
        $payload = Build-AgentRegistrationPayload -AgentConfig $agentConfig -ProjectRoot $env:TEMP
        Assert-Equal "droid" $payload.provider
    }

    It "should handle agent config without model gracefully" {
        $agentConfig = [PSCustomObject]@{
            name  = "droid"
            model = $null
        }
        # Build-AgentRegistrationPayload passes empty string to New-AgentKey which requires non-empty Model
        # This is expected to throw for configs with no model
        Assert-Throws {
            Build-AgentRegistrationPayload -AgentConfig $agentConfig -ProjectRoot $env:TEMP
        }
    }

    It "should include required payload keys" {
        $agentConfig = [PSCustomObject]@{
            name    = "test-agent"
            adapter = "droid"
            model   = "o3"
        }
        $payload = Build-AgentRegistrationPayload -AgentConfig $agentConfig -ProjectRoot $env:TEMP
        Assert-NotNull $payload.key
        Assert-NotNull $payload.provider
        Assert-NotNull $payload.machine_id
        Assert-NotNull $payload.name
        Assert-Equal "cli" $payload.type
        Assert-NotNull $payload.metadata
    }
}

Get-TestResults
