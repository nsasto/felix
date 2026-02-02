<#
.SYNOPSIS
Tests for plugin system
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/plugin-manager.ps1"

Describe "Plugin Discovery" {

    It "should discover plugins with valid manifests" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/test-plugins-$(Get-Random)" -Force
        
        # Create a test plugin
        $pluginDir = New-Item -ItemType Directory -Path "$tempDir/test-plugin" -Force
        $manifest = @{
            id      = "test-plugin"
            name    = "Test Plugin"
            version = "1.0.0"
            hooks   = @(
                @{ name = "OnTest"; type = "powershell"; script = "hook.ps1" }
            )
        } | ConvertTo-Json
        $manifest | Out-File "$pluginDir/plugin.json"
        
        $config = [PSCustomObject]@{
            plugins = @{
                enabled        = $true
                discovery_path = $tempDir
                disabled       = @()
            }
        }
        
        $result = Initialize-PluginSystem -Config $config -RunId "test-run"
        
        Assert-Equal $true $result.Enabled
        Assert-Equal 1 $result.Plugins.Count
        Assert-Equal "test-plugin" $result.Plugins[0].Id
        
        Remove-Item $tempDir -Recurse -Force
    }

    It "should skip plugins without manifests" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/test-plugins-$(Get-Random)" -Force
        
        # Create plugin directory without manifest
        New-Item -ItemType Directory -Path "$tempDir/invalid-plugin" -Force | Out-Null
        
        $config = [PSCustomObject]@{
            plugins = @{
                enabled        = $true
                discovery_path = $tempDir
                disabled       = @()
            }
        }
        
        $result = Initialize-PluginSystem -Config $config -RunId "test-run"
        
        Assert-Equal 0 $result.Plugins.Count
        
        Remove-Item $tempDir -Recurse -Force
    }

    It "should respect disabled plugins list" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/test-plugins-$(Get-Random)" -Force
        
        $pluginDir = New-Item -ItemType Directory -Path "$tempDir/disabled-plugin" -Force
        $manifest = @{
            id    = "disabled-plugin"
            name  = "Disabled Plugin"
            hooks = @()
        } | ConvertTo-Json
        $manifest | Out-File "$pluginDir/plugin.json"
        
        $config = [PSCustomObject]@{
            plugins = @{
                enabled        = $true
                discovery_path = $tempDir
                disabled       = @("disabled-plugin")
            }
        }
        
        $result = Initialize-PluginSystem -Config $config -RunId "test-run"
        
        Assert-Equal 0 $result.Plugins.Count
        
        Remove-Item $tempDir -Recurse -Force
    }

    It "should return disabled state when plugins not enabled" {
        $config = [PSCustomObject]@{
            plugins = @{
                enabled = $false
            }
        }
        
        $result = Initialize-PluginSystem -Config $config -RunId "test-run"
        
        Assert-Equal $false $result.Enabled
        Assert-Equal 0 $result.Plugins.Count
    }
}

Describe "Plugin Hook Execution" {

    It "should execute hooks successfully" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/test-plugins-$(Get-Random)" -Force
        
        $pluginDir = New-Item -ItemType Directory -Path "$tempDir/test-plugin" -Force
        $manifest = @{
            id    = "test-plugin"
            name  = "Test Plugin"
            hooks = @(
                @{ name = "OnTest"; type = "powershell"; script = "hook.ps1" }
            )
        } | ConvertTo-Json
        $manifest | Out-File "$pluginDir/plugin.json"
        
        # Create hook script
        '@{ ShouldContinue = $true; Message = "Hook executed" }' | Out-File "$pluginDir/hook.ps1"
        
        $config = [PSCustomObject]@{
            plugins = @{
                enabled        = $true
                discovery_path = $tempDir
                disabled       = @()
            }
        }
        
        Initialize-PluginSystem -Config $config -RunId "test-run" | Out-Null
        
        $result = Invoke-PluginHook -HookName "OnTest" -RunId "test-run" -HookData @{}
        
        Assert-True $result.ShouldContinue
        
        Remove-Item $tempDir -Recurse -Force
    }

    It "should return default when no plugins loaded" {
        $script:PluginCache = $null
        
        $result = Invoke-PluginHook -HookName "OnTest" -RunId "test-run" -HookData @{}
        
        Assert-True $result.ShouldContinue
    }
}

Describe "Plugin Circuit Breaker" {

    It "should increment failure count on errors" {
        $tempDir = New-Item -ItemType Directory -Path "$env:TEMP/test-plugins-$(Get-Random)" -Force
        
        $pluginDir = New-Item -ItemType Directory -Path "$tempDir/failing-plugin" -Force
        $manifest = @{
            id    = "failing-plugin"
            name  = "Failing Plugin"
            hooks = @(
                @{ name = "OnTest"; type = "powershell"; script = "hook.ps1" }
            )
        } | ConvertTo-Json
        $manifest | Out-File "$pluginDir/plugin.json"
        
        # Create hook script that throws error
        'throw "Plugin error"' | Out-File "$pluginDir/hook.ps1"
        
        $config = [PSCustomObject]@{
            plugins = @{
                enabled        = $true
                discovery_path = $tempDir
                disabled       = @()
            }
        }
        
        Initialize-PluginSystem -Config $config -RunId "test-run" | Out-Null
        
        # Execute hook multiple times to trigger circuit breaker
        1..3 | ForEach-Object {
            Invoke-PluginHook -HookName "OnTest" -RunId "test-run" -HookData @{} | Out-Null
        }
        
        # Circuit breaker should be active
        Assert-True ($script:PluginCircuitBreaker["failing-plugin"] -ge 3)
        
        Remove-Item $tempDir -Recurse -Force
    }

    It "should reset circuit breaker" {
        $script:PluginCircuitBreaker = @{ "test-plugin" = 3 }
        
        Reset-PluginCircuitBreaker -PluginId "test-plugin"
        
        Assert-Equal 0 $script:PluginCircuitBreaker["test-plugin"]
    }
}

Describe "Safe Plugin Execution" {

    It "should handle errors gracefully" {
        $script:PluginCache = $null
        
        # Should not throw
        $result = Invoke-PluginHookSafely -HookName "OnTest" -RunId "test-run" -HookData @{}
        
        Assert-True $result.ShouldContinue
    }
}

Get-TestResults
