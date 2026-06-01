<#
.SYNOPSIS
Memory context loader (Phase E4).

.DESCRIPTION
Loads .felix/memory/ files (repo + requirement scopes) and optionally
global memory from %USERPROFILE%\.felix\memory\global\*.md.
Returns concatenated content for injection into {{MEMORY}} prompt placeholder.
#>

function Get-MemoryContext {
    <#
    .SYNOPSIS
    Loads and concatenates memory files for the current iteration context.

    .PARAMETER FelixDir
    Path to the .felix directory.

    .PARAMETER RequirementId
    Optional requirement ID to load requirement-scoped memory.

    .PARAMETER IncludeGlobal
    Whether to include global (user-level) memory. Default: true.

    .OUTPUTS
    String containing all loaded memory content, separated by --- dividers.
    Empty string if no memory files found.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FelixDir,

        [Parameter(Mandatory = $false)]
        [string]$RequirementId = "",

        [Parameter(Mandatory = $false)]
        [bool]$IncludeGlobal = $true
    )

    $sections = [System.Collections.ArrayList]@()

    # Global scope: %USERPROFILE%\.felix\memory\global\*.md
    if ($IncludeGlobal) {
        $globalDir = Join-Path $env:USERPROFILE ".felix\memory\global"
        if (Test-Path $globalDir) {
            $globalFiles = Get-ChildItem -Path $globalDir -Filter "*.md" -ErrorAction SilentlyContinue |
                Sort-Object Name
            foreach ($f in $globalFiles) {
                try {
                    $content = Get-Content $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                    if ($content) {
                        [void]$sections.Add("<!-- memory: global/$($f.Name) -->`n$content")
                    }
                } catch {}
            }
        }
    }

    # Repo scope: .felix/memory/repo/*.md
    $repoMemDir = Join-Path $FelixDir "memory\repo"
    if (Test-Path $repoMemDir) {
        $repoFiles = Get-ChildItem -Path $repoMemDir -Filter "*.md" -ErrorAction SilentlyContinue |
            Sort-Object Name
        foreach ($f in $repoFiles) {
            try {
                $content = Get-Content $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($content) {
                    [void]$sections.Add("<!-- memory: repo/$($f.Name) -->`n$content")
                }
            } catch {}
        }
    }

    # Requirement scope: .felix/memory/requirement/<req-id>/*.md
    if ($RequirementId) {
        $reqMemDir = Join-Path $FelixDir "memory\requirement\$RequirementId"
        if (Test-Path $reqMemDir) {
            $reqFiles = Get-ChildItem -Path $reqMemDir -Filter "*.md" -ErrorAction SilentlyContinue |
                Sort-Object Name
            foreach ($f in $reqFiles) {
                try {
                    $content = Get-Content $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                    if ($content) {
                        [void]$sections.Add("<!-- memory: requirement/$RequirementId/$($f.Name) -->`n$content")
                    }
                } catch {}
            }
        }
    }

    if ($sections.Count -eq 0) {
        return ""
    }

    return ($sections -join "`n`n---`n`n")
}
