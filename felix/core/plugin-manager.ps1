<#
.SYNOPSIS
Plugin system for Felix agent
#>

# Script-level variables for plugin state
$script:PluginCache = $null
$script:PluginCircuitBreaker = @{}

function Initialize-PluginSystem {
    <#
    .SYNOPSIS
    Discovers and loads plugins from plugin directory
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )
    
    # Check if plugins are enabled
    if (-not $Config.plugins -or -not $Config.plugins.enabled) {
        Write-Verbose "Plugin system disabled"
        $script:PluginCache = @{
            Enabled = $false
            Plugins = @()
        }
        return $script:PluginCache
    }
    
    $pluginDir = $Config.plugins.discovery_path
    if (-not $pluginDir) {
        $pluginDir = Join-Path $PSScriptRoot "../plugins"
    }
    
    if (-not (Test-Path $pluginDir)) {
        Write-Verbose "Plugin directory not found: $pluginDir"
        return @{
            Enabled = $true
            Plugins = @()
        }
    }
    
    # Discover plugins
    $disabledPlugins = if ($Config.plugins.disabled) { $Config.plugins.disabled } else { @() }
    
    $plugins = Get-ChildItem $pluginDir -Directory | ForEach-Object {
        $pluginName = $_.Name
        $manifestPath = Join-Path $_.FullName "plugin.json"
        
        if (-not (Test-Path $manifestPath)) {
            Write-Verbose "Skipping plugin ${pluginName}: No manifest found"
            return $null
        }
        
        try {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            
            # Check if plugin is disabled
            if ($disabledPlugins -contains $manifest.id -or $disabledPlugins -contains $pluginName) {
                Write-Verbose "Skipping plugin ${pluginName}: Disabled in config"
                return $null
            }
            
            # Basic validation
            if (-not $manifest.id -or -not $manifest.hooks) {
                Write-Warning "Invalid plugin manifest for $pluginName"
                return $null
            }
            
            $plugin = @{
                Id          = $manifest.id
                Name        = $manifest.name
                Path        = $_.FullName
                Hooks       = $manifest.hooks
                Permissions = if ($manifest.permissions) { $manifest.permissions } else { @() }
                Config      = if ($manifest.config) { $manifest.config } else { @{} }
            }
            
            Write-Verbose "Found plugin: $($plugin.Name) ($($plugin.Id))"
            return [PSCustomObject]$plugin
        }
        catch {
            Write-Warning "Failed to load plugin manifest for ${pluginName}: $_"
            return $null
        }
    } | Where-Object { $null -ne $_ }
    
    $script:PluginCache = @{
        Enabled = $true
        Plugins = @($plugins)
    }
    
    $count = @($plugins).Count
    Write-Host "[PLUGINS] Initialized plugin system ($count plugins active)" -ForegroundColor Green
    return $script:PluginCache
}

function Invoke-PluginHook {
    <#
    .SYNOPSIS
    Executes all plugins that implement the specified hook
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HookName,
        
        [Parameter(Mandatory = $true)]
        [string]$RunId,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$HookData = @{}
    )
    
    if (-not $script:PluginCache -or -not $script:PluginCache.Enabled) {
        return @{ ShouldContinue = $true }
    }
    
    $combinedResult = @{
        ShouldContinue = $true
        Reason         = ""
    }
    
    foreach ($plugin in $script:PluginCache.Plugins) {
        # Check if plugin implements this hook
        $hook = $plugin.Hooks | Where-Object { $_.name -eq $HookName }
        if (-not $hook) { continue }
        
        # Check circuit breaker
        $pluginId = $plugin.Id
        if ($script:PluginCircuitBreaker[$pluginId] -ge 3) {
            Write-Verbose "Plugin $pluginId is disabled due to repeated failures"
            continue
        }
        
        try {
            # Implementation depends on hook type (script or binary)
            $result = $null
            if ($hook.type -eq "powershell") {
                $hookScript = Join-Path $plugin.Path $hook.script
                if (Test-Path $hookScript) {
                    $result = & $hookScript -HookName $HookName -RunId $RunId -Data $HookData -Config $plugin.Config
                }
            }
            
            # Process result
            if ($result) {
                if ($result.PSObject.Properties['ShouldContinue'] -and $result.ShouldContinue -eq $false) {
                    $combinedResult.ShouldContinue = $false
                    $combinedResult.Reason = $result.Reason
                }
                
                # Merge other properties into combined result
                foreach ($prop in $result.PSObject.Properties) {
                    if ($prop.Name -ne "ShouldContinue" -and $prop.Name -ne "Reason") {
                        $combinedResult[$prop.Name] = $prop.Value
                    }
                }
            }
            
            # Reset circuit breaker on success
            $script:PluginCircuitBreaker[$pluginId] = 0
        }
        catch {
            Write-Warning "Plugin $($plugin.Name) failed on hook ${HookName}: $_"
            $currentCount = if ($script:PluginCircuitBreaker[$pluginId]) { $script:PluginCircuitBreaker[$pluginId] } else { 0 }
            $script:PluginCircuitBreaker[$pluginId] = $currentCount + 1
        }
    }
    
    return [PSCustomObject]$combinedResult
}

function Invoke-PluginHookSafely {
    <#
    .SYNOPSIS
    Safe wrapper for plugin hook execution with error handling
    #>
    param(
        [string]$HookName,
        [string]$RunId,
        [hashtable]$HookData
    )
    
    try {
        return Invoke-PluginHook -HookName $HookName -RunId $RunId -HookData $HookData
    }
    catch {
        Write-Host "[PLUGINS] $HookName hook failed: $_" -ForegroundColor Yellow
        return @{ ShouldContinue = $true }
    }
}

function Reset-PluginCircuitBreaker {
    <#
    .SYNOPSIS
    Resets circuit breaker for all or specific plugins
    #>
    param([string]$PluginId = $null)
    
    if ($PluginId) {
        $script:PluginCircuitBreaker[$PluginId] = 0
    }
    else {
        $script:PluginCircuitBreaker = @{}
    }
}

Export-ModuleMember -Function Initialize-PluginSystem, Invoke-PluginHook, Invoke-PluginHookSafely, Reset-PluginCircuitBreaker
