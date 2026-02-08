<#
.SYNOPSIS
PowerShell 5.1 compatible utility functions
.DESCRIPTION
Provides safe alternatives to PS 7+ features
#>

function Coalesce-Value {
    <#
    .SYNOPSIS
    Replaces ?? operator for PS 5.1 compatibility
    #>
    param(
        [Parameter(ValueFromPipeline)]
        $Value,
        $Default
    )
    if ($null -eq $Value -or $Value -eq '') { return $Default }
    return $Value
}

function Ternary {
    <#
    .SYNOPSIS
    Replaces ?: operator for PS 5.1 compatibility
    #>
    param(
        [bool]$Condition,
        $IfTrue,
        $IfFalse
    )
    if ($Condition) { return $IfTrue } else { return $IfFalse }
}

function Safe-Interpolate {
    <#
    .SYNOPSIS
    Safe string interpolation without drive reference bugs
    #>
    param(
        [string]$Template,
        [hashtable]$Variables
    )
    $result = $Template
    foreach ($key in $Variables.Keys) {
        $placeholder = "`${$key}"
        $result = $result -replace [regex]::Escape($placeholder), $Variables[$key]
    }
    return $result
}

function Invoke-SafeCommand {
    <#
    .SYNOPSIS
    Secure command execution without Invoke-Expression
    #>
    param(
        [string]$Command,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $PWD
    )

    $originalLocation = Get-Location
    try {
        if ($WorkingDirectory) {
            Set-Location $WorkingDirectory
        }

        # Use call operator with explicit arguments - no command injection
        $result = & $Command @Arguments 2>&1
        return @{
            output   = $result
            exitCode = $LASTEXITCODE
        }
    }
    finally {
        Set-Location $originalLocation
    }
}

function Resolve-FelixExecutablePath {
    <#
    .SYNOPSIS
    Resolves an executable to a runnable filesystem path
    
    .DESCRIPTION
    Attempts to resolve an executable name (e.g., "codex", "droid") to an absolute path,
    even when npm global shim directories are not on PATH.
    
    Returns $null if not found.
    #>
    param([Parameter(Mandatory = $true)][string]$Executable)
    
    if ([string]::IsNullOrWhiteSpace($Executable)) {
        return $null
    }
    
    # Direct path (relative or absolute)
    try {
        if (Test-Path $Executable) {
            return (Resolve-Path $Executable).Path
        }
    }
    catch { }
    
    # PATH / registered command
    try {
        return (Get-Command $Executable -ErrorAction Stop).Source
    }
    catch { }
    
    # Check npm global on Windows (common but not always on PATH)
    if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6)) {
        $npmPrefix = $null
        try {
            $npmPrefix = npm config get prefix 2>$null
        }
        catch { }
        
        if ($npmPrefix -and (Test-Path $npmPrefix)) {
            $candidates = @(
                (Join-Path $npmPrefix "$Executable.cmd"),
                (Join-Path $npmPrefix "$Executable.ps1"),
                (Join-Path $npmPrefix "$Executable")
            )
            foreach ($candidate in $candidates) {
                if (Test-Path $candidate) {
                    return (Resolve-Path $candidate).Path
                }
            }
        }
    }
    
    return $null
}
