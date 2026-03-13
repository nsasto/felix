
function Invoke-Validate {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    if ($Args.Count -eq 0) {
        Write-Error "Usage: felix validate <requirement-id>"
        exit 1
    }

    $requirementId = $Args[0]

    Write-Host "Validating requirement: $requirementId" -ForegroundColor Cyan
    Write-Host ""

    # Call validation script
    $validatorScript = "$RepoRoot\scripts\validate-requirement.py"
    if (-not (Test-Path $validatorScript)) {
        Write-Error "Validator script not found: $validatorScript"
        exit 1
    }

    # Run Python validator
    $pythonCmd = "python"
    if (Get-Command "py" -ErrorAction SilentlyContinue) {
        $pythonCmd = "py -3"
    }

    $result = & $pythonCmd $validatorScript $requirementId
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host " Validation PASSED" -ForegroundColor Green
    }
    else {
        Write-Host " Validation FAILED" -ForegroundColor Red
    }

    exit $exitCode
}
