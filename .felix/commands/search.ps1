param(
    [string]$RepoRoot = (Get-Location).Path,
    [switch]$VerboseMode,
    [switch]$DebugMode
)

. "$PSScriptRoot\..\core\felixignore-utils.ps1"

function Invoke-Search {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ArgumentList
    )

    $pattern    = $null
    $scope      = "file"
    $inTarget   = "code"
    $maxResults = 50
    $jsonOutput = $false
    $relatedTo  = $null

    $i = 0
    while ($i -lt $ArgumentList.Count) {
        switch ($ArgumentList[$i]) {
            "--scope"      { $i++; $scope      = $ArgumentList[$i] }
            "--in"         { $i++; $inTarget   = $ArgumentList[$i] }
            "--max"        { $i++; $maxResults = [int]$ArgumentList[$i] }
            "--json"       { $jsonOutput = $true }
            "--related-to" { $i++; $relatedTo  = $ArgumentList[$i] }
            default {
                if (-not $ArgumentList[$i].StartsWith("--") -and $null -eq $pattern) {
                    $pattern = $ArgumentList[$i]
                }
            }
        }
        $i++
    }

    . "$PSScriptRoot\..\core\search-cache.ps1"
    $runDir = $env:FELIX_RUN_DIR

    if ($relatedTo) {
        $files  = Get-RelatedFiles -ProjectPath $RepoRoot -RequirementId $relatedTo
        $result = [ordered]@{
            files  = @($files)
            total  = $files.Count
            source = $relatedTo
        }
        if ($jsonOutput) {
            $result | ConvertTo-Json -Depth 3
        } else {
            foreach ($f in $files) { Write-Host $f }
        }
        return
    }

    if ($null -eq $pattern) {
        Write-Host "Usage: felix search <pattern> [--scope file|symbol] [--in code|specs|runs|all] [--max N] [--json] [--related-to <req-id>]" -ForegroundColor Red
        exit 1
    }

    # Cache lookup
    $cacheKey = $null
    if ($runDir) {
        $cacheKey = Get-SearchCacheKey -Query $pattern -Flags "$scope|$inTarget|$maxResults"
        $cached   = Get-SearchCache -RunDir $runDir -Key $cacheKey
        if ($null -ne $cached) {
            if ($jsonOutput) {
                $cached | ConvertTo-Json -Depth 5
            } else {
                foreach ($m in $cached.matches) {
                    Write-Host "$($m.path):$($m.line): $($m.text)"
                }
            }
            return
        }
    }

    # Build .felixignore exclusion globs
    $ignoreData  = Get-FelixIgnorePatterns -RepoRoot $RepoRoot
    $ignoredGlobs = [System.Collections.ArrayList]@()
    $rgExcludes   = [System.Collections.ArrayList]@()
    foreach ($entry in $ignoreData.Patterns) {
        if (-not $entry.Negated) {
            [void]$ignoredGlobs.Add($entry.Pattern)
            [void]$rgExcludes.Add("--glob")
            [void]$rgExcludes.Add("!$($entry.Pattern)")
        }
    }

    # Determine search paths
    $searchPaths = [System.Collections.ArrayList]@()
    switch ($inTarget) {
        "specs" {
            $specsDir = Join-Path $RepoRoot "specs"
            if (Test-Path $specsDir) { [void]$searchPaths.Add($specsDir) }
        }
        "runs" {
            $runsDir = Join-Path $RepoRoot "runs"
            if (Test-Path $runsDir) {
                $dirs = Get-ChildItem -Path $runsDir -Directory -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 10
                foreach ($d in $dirs) { [void]$searchPaths.Add($d.FullName) }
            }
        }
        "all" {
            [void]$searchPaths.Add($RepoRoot)
        }
        default {
            # code: search repo root; rg exclusions handle specs/ and runs/ via .felixignore
            [void]$searchPaths.Add($RepoRoot)
        }
    }

    $matchList = [System.Collections.ArrayList]@()
    $truncated = $false

    # Detect rg
    $hasRg = $false
    try {
        $null = & rg --version 2>&1
        if ($LASTEXITCODE -eq 0) { $hasRg = $true }
    } catch { }

    if ($hasRg) {
        $rgArgs = [System.Collections.ArrayList]@("--json", "-n")
        foreach ($ex in $rgExcludes) { [void]$rgArgs.Add($ex) }

        if ($inTarget -eq "code") {
            [void]$rgArgs.Add("--glob")
            [void]$rgArgs.Add("!specs/")
            [void]$rgArgs.Add("--glob")
            [void]$rgArgs.Add("!runs/")
        }

        [void]$rgArgs.Add($pattern)
        foreach ($sp in $searchPaths) { [void]$rgArgs.Add($sp) }

        $rgArgArray = $rgArgs.ToArray()
        $rgOutput   = & rg @rgArgArray 2>&1
        foreach ($line in $rgOutput) {
            if ($matchList.Count -ge $maxResults) { $truncated = $true; break }
            $lineStr = [string]$line
            if (-not $lineStr.StartsWith("{")) { continue }
            try {
                $obj = $lineStr | ConvertFrom-Json
                if ($obj.type -eq "match") {
                    $data    = $obj.data
                    $relPath = $data.path.text
                    try {
                        $absPath = [System.IO.Path]::GetFullPath($data.path.text)
                        $root    = [System.IO.Path]::GetFullPath($RepoRoot)
                        if ($absPath.StartsWith($root)) {
                            $relPath = $absPath.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
                        }
                    } catch { }

                    $col = 1
                    if ($data.submatches -and $data.submatches.Count -gt 0) {
                        $col = $data.submatches[0].start + 1
                    }

                    $matchEntry = [ordered]@{
                        path    = $relPath
                        line    = [int]$data.line_number
                        col     = $col
                        text    = ([string]$data.lines.text).TrimEnd()
                        rank    = [math]::Round(1.0 / [math]::Max(1, $matchList.Count + 1), 2)
                        context = @()
                    }
                    [void]$matchList.Add($matchEntry)
                }
            } catch { }
        }
    } else {
        # Fallback: Select-String with manual ignore filtering
        $loadedPatterns = $ignoreData.Patterns
        foreach ($searchPath in $searchPaths) {
            if (-not (Test-Path $searchPath)) { continue }
            $files = Get-ChildItem -Path $searchPath -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object {
                    -not (Test-FelixIgnored -Path $_.FullName -RepoRoot $RepoRoot -Patterns $loadedPatterns)
                }
            foreach ($file in $files) {
                if ($matchList.Count -ge $maxResults) { $truncated = $true; break }
                $ssResults = Select-String -Path $file.FullName -Pattern $pattern -ErrorAction SilentlyContinue
                foreach ($r in $ssResults) {
                    if ($matchList.Count -ge $maxResults) { $truncated = $true; break }
                    $relPath = $r.Path
                    try {
                        $root    = [System.IO.Path]::GetFullPath($RepoRoot)
                        $absPath = [System.IO.Path]::GetFullPath($r.Path)
                        if ($absPath.StartsWith($root)) {
                            $relPath = $absPath.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
                        }
                    } catch { }

                    $matchEntry = [ordered]@{
                        path    = $relPath
                        line    = $r.LineNumber
                        col     = 1
                        text    = ([string]$r.Line).TrimEnd()
                        rank    = [math]::Round(1.0 / [math]::Max(1, $matchList.Count + 1), 2)
                        context = @()
                    }
                    [void]$matchList.Add($matchEntry)
                }
            }
            if ($truncated) { break }
        }
    }

    $resultObj = [ordered]@{
        matches       = $matchList.ToArray()
        truncated     = $truncated
        total         = $matchList.Count
        ignored_globs = $ignoredGlobs.ToArray()
    }

    if ($runDir -and $cacheKey) {
        Set-SearchCache -RunDir $runDir -Key $cacheKey -Value $resultObj
    }

    if ($jsonOutput) {
        $resultObj | ConvertTo-Json -Depth 5
    } else {
        foreach ($m in $matchList) {
            Write-Host "$($m.path):$($m.line): $($m.text)"
        }
    }
}

function Get-RelatedFiles {
    param(
        [string]$ProjectPath,
        [string]$RequirementId
    )

    $filesHash = @{}

    $runsDir = Join-Path $ProjectPath "runs"
    if (-not (Test-Path $runsDir)) { return @() }

    $matchingRuns = Get-ChildItem -Path $runsDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$RequirementId-*" }

    foreach ($runDirItem in $matchingRuns) {
        # Read context-map.md
        $contextMapPath = Join-Path $runDirItem.FullName "context-map.md"
        if (Test-Path $contextMapPath) {
            $inSection = $false
            $lines = Get-Content $contextMapPath -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                if ($line -match "^## Files (likely to change|to read for context)") {
                    $inSection = $true
                    continue
                }
                if ($inSection -and $line -match "^## ") {
                    $inSection = $false
                    continue
                }
                if ($inSection -and $line -match "^[-*]\s+(.+)") {
                    $fp = $Matches[1].Trim()
                    if ($fp) { $filesHash[$fp] = $true }
                }
            }
        }

        # Read iteration plan files for file-path-looking lines
        $iterDirs = Get-ChildItem -Path $runDirItem.FullName -Directory -Filter "iteration-*" -ErrorAction SilentlyContinue
        foreach ($iterDir in $iterDirs) {
            $planFiles = Get-ChildItem -Path $iterDir.FullName -Filter "plan-*.md" -ErrorAction SilentlyContinue
            foreach ($planFile in $planFiles) {
                $lines = Get-Content $planFile.FullName -ErrorAction SilentlyContinue
                foreach ($line in $lines) {
                    if ($line -match "^- (.+)") {
                        $token = $Matches[1].Trim()
                        if ($token -match "\." -or $token.StartsWith("/")) {
                            $filesHash[$token] = $true
                        }
                    }
                }
            }
        }
    }

    $result = $filesHash.Keys | Sort-Object
    return @($result)
}
