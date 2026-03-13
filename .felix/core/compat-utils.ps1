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
    Attempts to resolve an executable name (e.g., "codex") to an absolute path,
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
        $source = (Get-Command $Executable -ErrorAction Stop).Source
        if ($source -and $source.EndsWith(".ps1")) {
            $cmdShim = [System.IO.Path]::ChangeExtension($source, "cmd")
            if (Test-Path $cmdShim) {
                return (Resolve-Path $cmdShim).Path
            }
            $exeShim = [System.IO.Path]::ChangeExtension($source, "exe")
            if (Test-Path $exeShim) {
                return (Resolve-Path $exeShim).Path
            }
        }
        return $source
    }
    catch { }

    $ext = [System.IO.Path]::GetExtension($Executable)
    $names = if ($ext) {
        @($Executable)
    }
    else {
        # Prefer Windows npm shims first to avoid PowerShell execution-policy issues.
        @("$Executable.cmd", "$Executable.exe", "$Executable.ps1", $Executable)
    }

    $candidateRoots = @()

    # Windows npm global shim directory is usually %APPDATA%\npm (and equals `npm prefix -g` on Windows).
    if ($env:APPDATA) {
        $candidateRoots += (Join-Path $env:APPDATA "npm")
    }

    # Try npm global prefix if npm is installed, even if its shim dir is not in PATH.
    try {
        $null = Get-Command npm -ErrorAction Stop
        $npmPrefix = (& npm prefix -g 2>$null).Trim()
        if (-not [string]::IsNullOrWhiteSpace($npmPrefix)) {
            $candidateRoots += $npmPrefix
            $candidateRoots += (Join-Path $npmPrefix "bin")
        }
    }
    catch { }

    foreach ($root in ($candidateRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        foreach ($name in $names) {
            try {
                $candidate = Join-Path $root $name
                if (Test-Path $candidate) {
                    return (Resolve-Path $candidate).Path
                }
            }
            catch { }
        }
    }

    return $null
}
