<#
.SYNOPSIS
Glob-pattern path matching helper (Phase F1).

.DESCRIPTION
Converts glob patterns to regex and matches file paths.
Supports ** (any path segment), * (single segment chars), ? (single char).
Used by backpressure per-path filtering and tool allowlist.
#>

function ConvertTo-GlobRegex {
    <#
    .SYNOPSIS
    Converts a glob pattern string to a PowerShell regex pattern.
    ** matches any path including separators. * matches within a single segment.
    #>
    param([Parameter(Mandatory=$true)][string]$Glob)

    # Normalise separators to forward slash
    $g = $Glob.Replace('\', '/')

    $sb = [System.Text.StringBuilder]::new()
    $i  = 0
    while ($i -lt $g.Length) {
        $c = $g[$i]
        if ($c -eq '*') {
            if ($i + 1 -lt $g.Length -and $g[$i+1] -eq '*') {
                # ** -- match anything including separators
                [void]$sb.Append('.*')
                $i += 2
                # Consume optional trailing /
                if ($i -lt $g.Length -and $g[$i] -eq '/') { $i++ }
                continue
            }
            # * -- match any non-separator chars
            [void]$sb.Append('[^/]*')
        }
        elseif ($c -eq '?') {
            [void]$sb.Append('[^/]')
        }
        elseif ($c -eq '.') {
            [void]$sb.Append('\.')
        }
        else {
            [void]$sb.Append([regex]::Escape([string]$c))
        }
        $i++
    }

    return '^' + $sb.ToString() + '$'
}

function Test-GlobMatch {
    <#
    .SYNOPSIS
    Returns true if the given file path matches at least one of the supplied glob patterns.

    .PARAMETER Path
    A relative or absolute file path (separators normalised internally).

    .PARAMETER Patterns
    Array of glob patterns.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string[]]$Patterns
    )

    $normalised = $Path.Replace('\', '/')

    foreach ($pattern in $Patterns) {
        $regex = ConvertTo-GlobRegex -Glob $pattern
        if ($normalised -imatch $regex) { return $true }
        # Also try matching against the file name alone
        $leaf = Split-Path $normalised -Leaf
        if ($leaf -imatch $regex) { return $true }
    }
    return $false
}
