<#
.SYNOPSIS
Python command resolution utilities for Felix agent

.DESCRIPTION
Provides functions to resolve and validate Python executable paths,
supporting py launcher, python, and python3 commands with configurable
executables and arguments.
#>

function Resolve-PythonCommand {
    <#
    .SYNOPSIS
    Resolves a usable Python command (application only) with optional args
    
    .PARAMETER Config
    Felix configuration object (may contain python.executable and python.args)
    
    .OUTPUTS
    Hashtable with 'cmd' (full path to Python executable) and 'args' (array of arguments)
    
    .EXAMPLE
    $python = Resolve-PythonCommand -Config $config
    & $python.cmd @python.args -c "print('hello')"
    #>
    param(
        [Parameter(Mandatory=$false)]
        [object]$Config
    )
    
    $pythonCmd = $null
    $pythonArgs = @()
    
    # Check config for explicit Python executable
    if ($Config -and $Config.python -and $Config.python.executable) {
        $candidate = $Config.python.executable
        if ($Config.python.args) {
            $pythonArgs = @($Config.python.args)
        }
        
        # Try resolving as absolute path first
        if (Test-Path $candidate) {
            $pythonCmd = (Resolve-Path $candidate).Path
        }
        else {
            # Try finding in PATH
            $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.CommandType -eq "Application") {
                $pythonCmd = $cmd.Source
            }
        }
        
        if (-not $pythonCmd) {
            throw "Python executable not found or not an application: $candidate"
        }
        
        return @{ cmd = $pythonCmd; args = $pythonArgs }
    }
    
    # Try py launcher (Windows)
    $cmd = Get-Command py -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.CommandType -eq "Application") {
        return @{ cmd = $cmd.Source; args = @("-3") }
    }
    
    # Try python command
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.CommandType -eq "Application") {
        return @{ cmd = $cmd.Source; args = @() }
    }
    
    # Try python3 command
    $cmd = Get-Command python3 -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.CommandType -eq "Application") {
        return @{ cmd = $cmd.Source; args = @() }
    }
    
    throw "Python executable not found. Set .felix/config.json -> python.executable (and optional python.args) or install Python."
}

