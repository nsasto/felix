<#
.SYNOPSIS
.felixignore support for Felix v2.

.DESCRIPTION
Implements two-layer gitignore-compatible ignore policy:
  Layer 1: <repo-root>/.felixignore  (committed, project-scope)
  Layer 2: %USERPROFILE%/.felix/ignore  (user-scope, cross-repo)

Deepest-pattern-wins within each layer. Both layers are merged and honored
by all Felix search/read helpers.

Debugging: felix doctor --explain <path> calls Get-FelixIgnoreExplanation.
#>

$script:DEFAULT_FELIXIGNORE_CONTENT = @"
# Felix ignore file — gitignore-compatible syntax
# Honored by all Felix search/read helpers.

runs/
publish-out/
obj/
bin/
.locks/
node_modules/
__pycache__/
*.min.js
*.map
"@

function Get-FelixIgnorePatterns {
    <#
    .SYNOPSIS
    Loads and merges .felixignore patterns from both layers.

    .PARAMETER RepoRoot
    Repository root path.

    .OUTPUTS
    A hashtable with:
      Patterns – merged array of {Pattern, Source, Layer}
      RepoPatterns – patterns from repo-root layer
      UserPatterns – patterns from user-scope layer
    #>
    param(
        [string]$RepoRoot = (Get-Location).Path
    )

    $repoPatterns = @()
    $userPatterns = @()

    # Layer 1: repo-root .felixignore
    $repoIgnorePath = Join-Path $RepoRoot ".felixignore"
    if (Test-Path $repoIgnorePath) {
        $repoPatterns = Read-IgnoreFile -Path $repoIgnorePath -Layer "repo"
    }

    # Layer 2: user-scope ignore
    $userIgnorePath = Join-Path $env:USERPROFILE ".felix\ignore"
    if (Test-Path $userIgnorePath) {
        $userPatterns = Read-IgnoreFile -Path $userIgnorePath -Layer "user"
    }

    $allPatterns = @($repoPatterns) + @($userPatterns)

    return @{
        Patterns     = $allPatterns
        RepoPatterns = $repoPatterns
        UserPatterns = $userPatterns
    }
}

function Read-IgnoreFile {
    <#
    .SYNOPSIS
    Parses a single ignore file into pattern objects.
    #>
    param(
        [string]$Path,
        [string]$Layer
    )

    $patterns = [System.Collections.ArrayList]@()
    $lines = Get-Content $Path -ErrorAction SilentlyContinue
    if (-not $lines) { return @() }

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }

        $negated = $false
        if ($trimmed.StartsWith("!")) {
            $negated = $true
            $trimmed = $trimmed.Substring(1).Trim()
        }

        [void]$patterns.Add(@{
            Pattern  = $trimmed
            Negated  = $negated
            Source   = $Path
            Layer    = $Layer
        })
    }
    return $patterns.ToArray()
}

function Test-FelixIgnored {
    <#
    .SYNOPSIS
    Tests whether a given path matches any .felixignore pattern.

    .PARAMETER Path
    The file or directory path to test (relative or absolute).

    .PARAMETER RepoRoot
    Repository root — used to compute relative path.

    .PARAMETER Patterns
    Pre-loaded patterns from Get-FelixIgnorePatterns. If omitted, loads from disk.

    .OUTPUTS
    $true if the path should be ignored, $false otherwise.
    #>
    param(
        [string]$Path,
        [string]$RepoRoot = (Get-Location).Path,
        [array]$Patterns  = $null
    )

    if ($null -eq $Patterns) {
        $loaded  = Get-FelixIgnorePatterns -RepoRoot $RepoRoot
        $Patterns = $loaded.Patterns
    }

    # Normalize to forward-slash relative path
    $absPath  = [System.IO.Path]::GetFullPath($Path)
    $relPath  = $absPath.Replace([System.IO.Path]::GetFullPath($RepoRoot), "").TrimStart('\', '/').Replace('\', '/')

    $ignored = $false
    foreach ($entry in $Patterns) {
        $pattern = $entry.Pattern.Replace('\', '/')
        if (Invoke-GlobMatch -Pattern $pattern -Path $relPath) {
            $ignored = -not $entry.Negated
        }
    }
    return $ignored
}

function Get-FelixIgnoreExplanation {
    <#
    .SYNOPSIS
    Reports which pattern in which layer matched a given path (for felix doctor --explain).

    .PARAMETER Path
    Path to explain.

    .PARAMETER RepoRoot
    Repository root.

    .OUTPUTS
    A hashtable: Ignored, MatchedPattern, Layer, Source
    #>
    param(
        [string]$Path,
        [string]$RepoRoot = (Get-Location).Path
    )

    $loaded   = Get-FelixIgnorePatterns -RepoRoot $RepoRoot
    $patterns = $loaded.Patterns

    $absPath = [System.IO.Path]::GetFullPath($Path)
    $relPath = $absPath.Replace([System.IO.Path]::GetFullPath($RepoRoot), "").TrimStart('\', '/').Replace('\', '/')

    $result = @{
        Ignored        = $false
        MatchedPattern = $null
        Layer          = $null
        Source         = $null
        RelPath        = $relPath
    }

    foreach ($entry in $patterns) {
        $pattern = $entry.Pattern.Replace('\', '/')
        if (Invoke-GlobMatch -Pattern $pattern -Path $relPath) {
            $result.Ignored        = -not $entry.Negated
            $result.MatchedPattern = $entry.Pattern
            $result.Layer          = $entry.Layer
            $result.Source         = $entry.Source
        }
    }
    return $result
}

function Invoke-GlobMatch {
    <#
    .SYNOPSIS
    Tests a path against a gitignore-style glob pattern.
    #>
    param(
        [string]$Pattern,
        [string]$Path
    )

    # Directory-only pattern (trailing /)
    $dirOnly = $Pattern.EndsWith("/")
    if ($dirOnly) {
        $Pattern = $Pattern.TrimEnd("/")
    }

    # Convert glob to regex
    $regexPattern = ConvertTo-GlobRegex -Glob $Pattern

    # Match against full relative path or last segment
    if ($Pattern.Contains("/")) {
        return $Path -match $regexPattern
    }
    else {
        # No slash — match against any path segment (filename or directory name)
        $segments = $Path -split "/"
        foreach ($seg in $segments) {
            if ($seg -match $regexPattern) { return $true }
        }
        # Also match prefix (e.g. pattern "runs/" matches "runs/foo")
        return $Path -match $regexPattern
    }
}

function ConvertTo-GlobRegex {
    <#
    .SYNOPSIS
    Converts a gitignore-compatible glob pattern to a regex string.
    #>
    param([string]$Glob)

    $escaped = [regex]::Escape($Glob)
    # Restore ** and * wildcards after escaping
    $regex = $escaped `
        -replace '\\\*\\\*', '.*' `
        -replace '\\\*', '[^/]*' `
        -replace '\\\?', '[^/]'

    return "^$regex$"
}

function New-DefaultFelixIgnore {
    <#
    .SYNOPSIS
    Writes the default .felixignore file to the given repo root.
    Used by felix migrate (A6) and felix setup.

    .PARAMETER RepoRoot
    Target directory.

    .PARAMETER Force
    Overwrite if exists.
    #>
    param(
        [string]$RepoRoot,
        [switch]$Force
    )

    $path = Join-Path $RepoRoot ".felixignore"
    if ((Test-Path $path) -and -not $Force) {
        return @{ Created = $false; Path = $path; Reason = "already exists" }
    }

    # Detect project type and add addenda
    $extra = [System.Collections.ArrayList]@()
    if (Test-Path (Join-Path $RepoRoot "*.csproj") -ErrorAction SilentlyContinue) {
        [void]$extra.Add("# .NET addendum")
        [void]$extra.Add("bin/")
        [void]$extra.Add("obj/")
    }
    if (Test-Path (Join-Path $RepoRoot "package.json")) {
        [void]$extra.Add("# Node addendum")
        [void]$extra.Add("dist/")
        [void]$extra.Add("coverage/")
    }

    $content = $script:DEFAULT_FELIXIGNORE_CONTENT
    if ($extra.Count -gt 0) {
        $content += "`n" + ($extra -join "`n")
    }

    Set-Content -Path $path -Value $content -Encoding UTF8
    return @{ Created = $true; Path = $path }
}
