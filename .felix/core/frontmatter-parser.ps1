<#
.SYNOPSIS
frontmatter-parser.ps1 - Phase B5 spec frontmatter parser for Felix v2.

.DESCRIPTION
Parses YAML frontmatter blocks from spec files:
  ---
  id: S-0042
  title: Add hierarchical AGENTS.md loader
  status: planned
  applyTo:
    - "src/Felix.Cli/**"
  tags: [context, prompt]
  skills: [build-context]
  gates: ["pwsh.unit", "pwsh.lint"]
  depends_on: [S-0040]
  ---

The parser is intentionally simple: no external YAML library required.
Handles the subset of YAML used in Felix spec frontmatter.
#>

function Get-SpecFrontmatter {
    <#
    .SYNOPSIS
    Parses YAML frontmatter from a spec file path.
    Returns $null if no frontmatter block present.
    #>
    param([string]$SpecPath)

    if (-not (Test-Path $SpecPath)) { return $null }

    $lines = Get-Content $SpecPath -ErrorAction SilentlyContinue
    if (-not $lines -or $lines.Count -lt 3) { return $null }
    if ($lines[0].Trim() -ne "---") { return $null }

    $endIdx = $null
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "---") { $endIdx = $i; break }
    }
    if ($null -eq $endIdx) { return $null }

    $yamlLines = $lines[1..($endIdx - 1)]
    return Parse-SimpleYaml -Lines $yamlLines
}

function Parse-SimpleYaml {
    <#
    .SYNOPSIS
    Parses the subset of YAML used in Felix frontmatter.
    Handles: scalar strings, inline arrays [a, b], and list items (- value).
    #>
    param([string[]]$Lines)

    $result = [ordered]@{}
    $currentKey = $null
    $currentList = $null

    foreach ($line in $Lines) {
        # Skip blank lines and comments
        if ($line -match "^\s*#" -or $line.Trim() -eq "") { continue }

        # Continuation list item: "  - value"
        if ($line -match "^\s+-\s+(.+)$" -and $currentKey) {
            $val = $Matches[1].Trim().Trim('"').Trim("'")
            if ($null -eq $currentList) {
                $currentList = [System.Collections.ArrayList]@()
                $result[$currentKey] = $currentList
            }
            [void]$currentList.Add($val)
            continue
        }

        # Key-value pair: "key: value" or "key: [a, b, c]"
        if ($line -match "^(\w[\w_-]*)\s*:\s*(.*)$") {
            $currentList = $null
            $currentKey  = $Matches[1].Trim()
            $rawVal      = $Matches[2].Trim()

            if ($rawVal -eq "" -or $rawVal -eq $null) {
                # Value on next lines (list)
                $result[$currentKey] = $null
            } elseif ($rawVal -match "^\[(.+)\]$") {
                # Inline array: [a, b, c]
                $items = $Matches[1] -split "," | ForEach-Object { $_.Trim().Trim('"').Trim("'") }
                $result[$currentKey] = @($items)
            } else {
                # Scalar
                $result[$currentKey] = $rawVal.Trim('"').Trim("'")
            }
            continue
        }
    }

    # Convert any ArrayList values to plain arrays
    $final = [ordered]@{}
    foreach ($k in $result.Keys) {
        $v = $result[$k]
        if ($v -is [System.Collections.ArrayList]) {
            $final[$k] = $v.ToArray()
        } else {
            $final[$k] = $v
        }
    }

    return $final
}

function Get-SpecBody {
    <#
    .SYNOPSIS
    Returns the markdown body of a spec file, stripping the frontmatter block.
    #>
    param([string]$SpecPath)

    if (-not (Test-Path $SpecPath)) { return "" }
    $lines = Get-Content $SpecPath -ErrorAction SilentlyContinue
    if (-not $lines -or $lines[0].Trim() -ne "---") {
        return ($lines -join "`n")
    }

    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "---") {
            $body = if ($i + 1 -lt $lines.Count) { $lines[($i + 1)..($lines.Count - 1)] } else { @() }
            return ($body -join "`n").TrimStart()
        }
    }
    return ($lines -join "`n")
}

function Format-SpecFrontmatter {
    <#
    .SYNOPSIS
    Serialises a frontmatter hashtable back to a YAML block (with --- delimiters).
    #>
    param([hashtable]$Frontmatter)

    $lines = [System.Collections.ArrayList]@()
    [void]$lines.Add("---")

    foreach ($k in $Frontmatter.Keys) {
        $v = $Frontmatter[$k]
        if ($null -eq $v) {
            [void]$lines.Add("${k}:")
        } elseif ($v -is [array] -or $v -is [System.Collections.ArrayList]) {
            if ($v.Count -eq 0) {
                [void]$lines.Add("${k}: []")
            } else {
                [void]$lines.Add("${k}:")
                foreach ($item in $v) { [void]$lines.Add("  - ""$item""") }
            }
        } else {
            [void]$lines.Add("${k}: $v")
        }
    }

    [void]$lines.Add("---")
    return $lines -join "`n"
}

function New-DefaultFrontmatter {
    <#
    .SYNOPSIS
    Infers frontmatter fields from a v1 spec file body.
    Used by B6 spec fix --frontmatter.
    #>
    param(
        [string]$SpecPath,
        [string]$SpecId = ""
    )

    $lines = Get-Content $SpecPath -ErrorAction SilentlyContinue
    $body  = $lines -join "`n"

    # Infer ID from filename if not provided
    if (-not $SpecId) {
        $fname  = [System.IO.Path]::GetFileNameWithoutExtension($SpecPath)
        $SpecId = if ($fname -match "^(S-\d+)") { $Matches[1] } else { $fname }
    }

    # Infer title from first # heading
    $title = ""
    foreach ($l in $lines) {
        if ($l -match "^#+\s+(.+)") { $title = $Matches[1] -replace "^S-\d+[:\s]*", ""; break }
    }

    # Infer status: look for "status:" keyword in body
    $status = "planned"
    if ($body -match "(?i)status[:\s]+(complete|done|finished)") { $status = "complete" }
    if ($body -match "(?i)status[:\s]+(in.?progress|wip)") { $status = "in-progress" }
    if ($body -match "(?i)status[:\s]+(blocked)") { $status = "blocked" }

    return [ordered]@{
        id         = $SpecId
        title      = $title
        status     = $status
        applyTo    = @()
        tags       = @()
        skills     = @()
        gates      = @()
        depends_on = @()
    }
}
