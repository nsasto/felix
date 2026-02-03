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
