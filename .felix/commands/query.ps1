<#
.SYNOPSIS
felix query  -  stable versioned JSON interface for agent-readable state (Phase F3).

.DESCRIPTION
Exposes Invoke-Query for felix.ps1 dispatch.
Kinds: requirements | runs | state

Examples:
  felix query requirements --status planned --json
  felix query runs --since 24h --requirement S-0042
  felix query state --json
#>

function Invoke-Query {
    param(
        [string[]]$CmdArgs = @(),
        [string]$ProjectPath = (Get-Location).Path
    )

    $felixDir = Join-Path $ProjectPath ".felix"
    $json     = $CmdArgs -icontains "--json"

    # Resolve kind
    $kind = ""
    foreach ($a in $CmdArgs) {
        if (-not $a.StartsWith("-")) { $kind = $a.ToLower(); break }
    }

    function Write-Result {
        param($Obj)
        if ($json) {
            $Obj | ConvertTo-Json -Depth 6
        } else {
            $Obj | Format-List
        }
    }

    function Error-Out {
        param([string]$Msg, [int]$Code = 1)
        if ($json) {
            [ordered]@{ _v = 1; error = $Msg } | ConvertTo-Json
        } else {
            Write-Host "Error: $Msg" -ForegroundColor Red
        }
        exit $Code
    }

    switch ($kind) {
        "requirements" {
            $reqFile = Join-Path $felixDir "requirements.json"
            if (-not (Test-Path $reqFile)) { Error-Out "requirements.json not found" }

            $data = Get-Content $reqFile -Raw | ConvertFrom-Json
            $reqs = @($data.requirements)

            # Filter --status
            $statusFilter = $null
            for ($i = 0; $i -lt $CmdArgs.Count - 1; $i++) {
                if ($CmdArgs[$i] -ieq "--status") { $statusFilter = $CmdArgs[$i+1]; break }
            }
            if ($statusFilter) {
                $reqs = @($reqs | Where-Object { $_.status -ieq $statusFilter })
            }

            $result = [ordered]@{
                _v           = 1
                kind         = "requirements"
                total        = $reqs.Count
                requirements = @($reqs | ForEach-Object {
                    [ordered]@{
                        id          = $_.id
                        title       = $_.title
                        status      = $_.status
                        priority    = $_.priority
                        spec_path   = $_.spec_path
                        tags        = @($_.tags)
                    }
                })
            }
            Write-Result $result
        }

        "runs" {
            $runsDir = Join-Path $ProjectPath "runs"
            if (-not (Test-Path $runsDir)) { Error-Out "runs/ directory not found" }

            # Filters
            $sinceArg = $null
            $reqFilter = $null
            for ($i = 0; $i -lt $CmdArgs.Count - 1; $i++) {
                if ($CmdArgs[$i] -ieq "--since")       { $sinceArg  = $CmdArgs[$i+1] }
                if ($CmdArgs[$i] -ieq "--requirement") { $reqFilter = $CmdArgs[$i+1] }
            }

            $cutoff = $null
            if ($sinceArg) {
                if ($sinceArg -match '^(\d+)h$') {
                    $cutoff = (Get-Date).AddHours(-[int]$Matches[1])
                } elseif ($sinceArg -match '^(\d+)d$') {
                    $cutoff = (Get-Date).AddDays(-[int]$Matches[1])
                }
            }

            $runDirs = Get-ChildItem -Path $runsDir -Directory -ErrorAction SilentlyContinue |
                Where-Object {
                    if ($reqFilter -and $_.Name -notmatch [regex]::Escape($reqFilter)) { return $false }
                    if ($cutoff -and $_.LastWriteTime -lt $cutoff) { return $false }
                    return $true
                } |
                Sort-Object LastWriteTime -Descending

            $runs = @($runDirs | ForEach-Object {
                $d = $_
                $planFile  = Join-Path $d.FullName "plan.md"
                $stateFile = Join-Path $d.FullName "state.json"
                $outcome   = "unknown"
                if (Test-Path $stateFile) {
                    try { $outcome = (Get-Content $stateFile -Raw | ConvertFrom-Json).outcome } catch {}
                }
                [ordered]@{
                    id           = $d.Name
                    path         = $d.FullName.Replace($ProjectPath + "\", "")
                    last_modified = $d.LastWriteTime.ToString("o")
                    has_plan     = (Test-Path $planFile)
                    outcome      = $outcome
                }
            })

            $result = [ordered]@{
                _v    = 1
                kind  = "runs"
                total = $runs.Count
                runs  = $runs
            }
            Write-Result $result
        }

        "state" {
            $stateFile = Join-Path $felixDir "state.json"
            $state     = [ordered]@{}
            if (Test-Path $stateFile) {
                try {
                    $raw = Get-Content $stateFile -Raw | ConvertFrom-Json
                    foreach ($p in $raw.PSObject.Properties) { $state[$p.Name] = $p.Value }
                } catch {}
            }

            $result = [ordered]@{
                _v            = 1
                kind          = "state"
                project_path  = $ProjectPath
                felix_dir     = $felixDir
                state         = $state
            }
            Write-Result $result
        }

        default {
            if ($kind -in @("events","plugins","skills","memory")) {
                $alternatives = @{
                    events  = "felix event query"
                    plugins = "felix plugin list"
                    skills  = "felix skill list"
                    memory  = "felix memory view"
                }
                $alt = $alternatives[$kind]
                if ($json) {
                    [ordered]@{
                        _v    = 1
                        error = "Kind '$kind' is not supported by 'felix query'. Use '$alt' instead."
                    } | ConvertTo-Json
                } else {
                    Write-Host "Error: 'felix query $kind' is not supported." -ForegroundColor Red
                    Write-Host "Use '$alt' instead." -ForegroundColor Yellow
                }
                exit 1
            }

            Write-Host "felix query - usage:" -ForegroundColor Cyan
            Write-Host "  felix query requirements [--status <status>] [--json]"
            Write-Host "  felix query runs [--since <Nh|Nd>] [--requirement <id>] [--json]"
            Write-Host "  felix query state [--json]"
        }
    }
}
