
function Invoke-Run {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    if ($Args.Count -eq 0) {
        Write-Error "Usage: felix run <requirement-id> [--format <json|plain|rich>]"
        exit 1
    }

    $requirementId = $Args[0]
    $formatValue = $Format  # Use script-level default
    $syncEnabled = $false
    
    # Parse optional flags
    for ($i = 1; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq "--format" -and ($i + 1) -lt $Args.Count) {
            $formatValue = $Args[$i + 1]
            $i++  # Skip the format value
        }
        elseif ($Args[$i] -eq "--sync") {
            $syncEnabled = $true
        }
    }

    # Execute felix-cli.ps1 which spawns agent internally
    if ($NoStats) {
        & "$PSScriptRoot\..\felix-cli.ps1" -ProjectPath $RepoRoot -RequirementId $requirementId -Format $formatValue -NoStats -VerboseMode:$VerboseMode -Sync:$syncEnabled
    }
    else {
        & "$PSScriptRoot\..\felix-cli.ps1" -ProjectPath $RepoRoot -RequirementId $requirementId -Format $formatValue -VerboseMode:$VerboseMode -Sync:$syncEnabled
    }

    exit $LASTEXITCODE
}
