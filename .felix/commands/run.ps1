
function Invoke-Run {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    if ($Args.Count -eq 0) {
        Write-Error "Usage: felix run <requirement-id> [--format <json|plain|rich>]"
        exit 1
    }

    $requirementId = $Args[0]
    $formatValue = $Format  # Use script-level default
    $syncEnabled = $false
    $exploreEnabled = $false
    $noExploreEnabled = $false
    
    # Parse optional flags
    for ($i = 1; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq "--format" -and ($i + 1) -lt $Args.Count) {
            $formatValue = $Args[$i + 1]
            $i++
        }
        elseif ($Args[$i] -eq "--sync") {
            $syncEnabled = $true
        }
        elseif ($Args[$i] -eq "--explore") {
            $exploreEnabled = $true
        }
        elseif ($Args[$i] -eq "--no-explore") {
            $noExploreEnabled = $true
        }
    }

    # Execute felix-cli.ps1 which spawns agent internally
    $cliArgs = @(
        "-ProjectPath", $RepoRoot,
        "-RequirementId", $requirementId,
        "-Format", $formatValue
    )
    if ($VerboseMode)     { $cliArgs += @("-VerboseMode") }
    if ($DebugMode)       { $cliArgs += @("-DebugMode") }
    if ($syncEnabled)     { $cliArgs += @("-Sync") }
    if ($exploreEnabled)  { $cliArgs += @("-Explore") }
    if ($noExploreEnabled){ $cliArgs += @("-NoExplore") }
    if ($NoStats)         { $cliArgs += @("-NoStats") }

    & "$PSScriptRoot\..\felix-cli.ps1" @cliArgs

    exit $LASTEXITCODE
}

function Invoke-RunReplay {
    <#
    .SYNOPSIS
    Opens the prompt artifact from a previous run (A7).
    Finds runs/<run-id>/iteration-N/prompt.txt and opens it.
    #>
    param(
        [string]$RunId,
        [string]$RepoRoot = (Get-Location).Path,
        [string]$Iteration = ""
    )

    $runsDir = Join-Path $RepoRoot "runs"
    $runDir  = Join-Path $runsDir $RunId

    if (-not (Test-Path $runDir)) {
        Write-Host "Run not found: $runDir" -ForegroundColor Red
        exit 1
    }

    # Find iteration directory
    $promptPath = $null
    if ($Iteration) {
        $iterDir = Join-Path $runDir "iteration-$Iteration"
        $promptPath = Join-Path $iterDir "prompt.txt"
    } else {
        # Latest iteration
        $iterDirs = Get-ChildItem -Path $runDir -Directory -Filter "iteration-*" |
            Sort-Object { [int]($_.Name -replace "iteration-", "") } -Descending
        if ($iterDirs) {
            $promptPath = Join-Path $iterDirs[0].FullName "prompt.txt"
        }
    }

    if (-not $promptPath -or -not (Test-Path $promptPath)) {
        Write-Host "No prompt artifact found for run '$RunId'." -ForegroundColor Red
        Write-Host "Expected: $promptPath" -ForegroundColor Gray
        exit 1
    }

    Write-Host "Opening prompt artifact: $promptPath" -ForegroundColor Cyan
    # Open in default editor or print to stdout
    if ($env:EDITOR) {
        & $env:EDITOR $promptPath
    } elseif (Get-Command code -ErrorAction SilentlyContinue) {
        code $promptPath
    } else {
        Get-Content $promptPath
    }
}
