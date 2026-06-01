<#
.SYNOPSIS
Hierarchical AGENTS.md loader for Felix v2.

.DESCRIPTION
Walks from the current working directory (or requirement-implied path) up to the
repo root, concatenating every AGENTS.md found  -  deepest first (most local wins)  - 
with section headers.

Produces a deterministic "layered context blob" with a SHA-256 hash that can be
used for snapshot/replay (Phase A7).

Per-level budget: default 4 KB (4096 chars). Overflow logs a warning and truncates
with a marker so the builder stays within the prompt budget.
#>

$script:DEFAULT_PER_LEVEL_BUDGET_CHARS = 4096

function Get-LayeredAgentsContext {
    <#
    .SYNOPSIS
    Walks from $StartPath up to the repo root and concatenates all AGENTS.md files.

    .PARAMETER StartPath
    Starting directory for the walk (default: current working directory).

    .PARAMETER RepoRoot
    The git repository root. Walk stops here.

    .PARAMETER PerLevelBudgetChars
    Maximum characters to include from each AGENTS.md level (default 4096).

    .OUTPUTS
    A hashtable with:
      Blob     – the assembled layered context string
      Hash     – SHA-256 hex of Blob (for snapshot/replay)
      Levels   – array of hashtables {Path, RelPath, Chars, Truncated}
      TotalChars – total chars in Blob
    #>
    param(
        [string]$StartPath = (Get-Location).Path,
        [string]$RepoRoot  = "",
        [int]$PerLevelBudgetChars = $script:DEFAULT_PER_LEVEL_BUDGET_CHARS
    )

    # Resolve repo root if not provided
    if (-not $RepoRoot) {
        $RepoRoot = Resolve-RepoRoot -Path $StartPath
    }

    # Collect AGENTS.md paths from StartPath up to RepoRoot
    $levels = [System.Collections.ArrayList]@()
    $current = $StartPath

    while ($true) {
        $candidate = Join-Path $current "AGENTS.md"
        if (Test-Path $candidate) {
            [void]$levels.Add($candidate)
        }

        # Stop if we're at the repo root
        if ([System.IO.Path]::GetFullPath($current) -eq [System.IO.Path]::GetFullPath($RepoRoot)) {
            break
        }

        $parent = Split-Path $current -Parent
        if (-not $parent -or $parent -eq $current) {
            break
        }
        $current = $parent
    }

    # Deepest first (most local wins)  -  already collected deepest-first
    $blobParts  = [System.Collections.ArrayList]@()
    $levelInfos = [System.Collections.ArrayList]@()

    $headerIndex = 1
    foreach ($agentsPath in $levels) {
        $relPath = $agentsPath.Replace([System.IO.Path]::GetFullPath($RepoRoot), "").TrimStart('\', '/')
        $raw = Get-Content $agentsPath -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { continue }

        $truncated = $false
        if ($raw.Length -gt $PerLevelBudgetChars) {
            $raw = $raw.Substring(0, $PerLevelBudgetChars) + "`n`n[... truncated: exceeded per-level budget of $PerLevelBudgetChars chars ...]"
            $truncated = $true
            if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                Emit-Log -Level "warn" -Message "AGENTS.md at '$relPath' truncated to $PerLevelBudgetChars chars (budget exceeded)" -Component "agents-loader"
            }
        }

        $header = "## Level $headerIndex  -  $relPath"
        [void]$blobParts.Add("$header`n`n$raw")
        [void]$levelInfos.Add(@{
            Path      = $agentsPath
            RelPath   = $relPath
            Chars     = $raw.Length
            Truncated = $truncated
        })
        $headerIndex++
    }

    $blob = $blobParts -join "`n`n---`n`n"

    # Compute SHA-256 hash of the blob for snapshot/replay
    $hash = ""
    if ($blob) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($blob)
        $sha   = [System.Security.Cryptography.SHA256]::Create()
        $hash  = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
    }

    return @{
        Blob       = $blob
        Hash       = $hash
        Levels     = $levelInfos.ToArray()
        TotalChars = $blob.Length
    }
}

function Resolve-RepoRoot {
    <#
    .SYNOPSIS
    Resolves the git repository root for a given path.

    .PARAMETER Path
    Starting path to search from.
    #>
    param([string]$Path = (Get-Location).Path)

    $current = [System.IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path (Join-Path $current ".git")) {
            return $current
        }
        $parent = Split-Path $current -Parent
        if (-not $parent -or $parent -eq $current) {
            break
        }
        $current = $parent
    }
    # Fall back to the provided path if no git root found
    return [System.IO.Path]::GetFullPath($Path)
}
