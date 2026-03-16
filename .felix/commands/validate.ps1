
function Invoke-Validate {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    $jsonOutput = $false
    $requirementId = $null

    foreach ($arg in $Args) {
        if ($arg -eq "--json") {
            $jsonOutput = $true
            continue
        }

        if (-not $requirementId -and -not $arg.StartsWith("--")) {
            $requirementId = $arg
        }
    }

    if (-not $requirementId) {
        if ($jsonOutput) {
            [PSCustomObject]@{
                success       = $false
                requirementId = $null
                exitCode      = 2
                reason        = "Usage: felix validate <requirement-id> [--json]"
                output        = @()
            } | ConvertTo-Json -Depth 4
            exit 2
        }

        Write-Error "Usage: felix validate <requirement-id> [--json]"
        exit 1
    }

    if (-not $jsonOutput) {
        Write-Host "Validating requirement: $requirementId" -ForegroundColor Cyan
        Write-Host ""
    }

    # Call validation script
    $validatorScript = "$RepoRoot\scripts\validate-requirement.py"
    if (-not (Test-Path $validatorScript)) {
        $reason = "Validator script not found: $validatorScript"
        if ($jsonOutput) {
            [PSCustomObject]@{
                success       = $false
                requirementId = $requirementId
                exitCode      = 2
                reason        = $reason
                output        = @()
            } | ConvertTo-Json -Depth 4
            exit 2
        }

        Write-Error $reason
        exit 1
    }

    # Run Python validator with launcher fallback order.
    $pythonCmd = $null
    $pythonArgs = @()

    if (Get-Command "py" -ErrorAction SilentlyContinue) {
        $pythonCmd = "py"
        $pythonArgs = @("-3")
    }
    elseif (Get-Command "python" -ErrorAction SilentlyContinue) {
        $pythonCmd = "python"
    }
    elseif (Get-Command "python3" -ErrorAction SilentlyContinue) {
        $pythonCmd = "python3"
    }
    else {
        $reason = "Python executable not found. Install Python or set .felix/config.json -> python.executable."
        if ($jsonOutput) {
            [PSCustomObject]@{
                success       = $false
                requirementId = $requirementId
                exitCode      = 2
                reason        = $reason
                output        = @()
            } | ConvertTo-Json -Depth 4
            exit 2
        }

        Write-Error $reason
        exit 1
    }

    $result = & $pythonCmd @pythonArgs $validatorScript $requirementId
    $exitCode = $LASTEXITCODE

    $resultLines = @()
    if ($null -ne $result) {
        $resultLines = @($result | ForEach-Object { "$_" })
    }

    $reason = if ($exitCode -eq 0) {
        "Validation passed"
    }
    elseif ($exitCode -eq 2) {
        "Validation could not run due to configuration, environment, or requirement lookup error"
    }
    else {
        "One or more validation checks failed"
    }

    if ($jsonOutput) {
        [PSCustomObject]@{
            success       = ($exitCode -eq 0)
            requirementId = $requirementId
            exitCode      = $exitCode
            reason        = $reason
            output        = $resultLines
        } | ConvertTo-Json -Depth 4
        exit $exitCode
    }

    if ($exitCode -eq 0) {
        Write-Host " Validation PASSED" -ForegroundColor Green
    }
    else {
        Write-Host " Validation FAILED" -ForegroundColor Red

        if ($resultLines.Count -gt 0) {
            Write-Host ""
            Write-Host "Failure details:" -ForegroundColor Yellow
            $resultLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        }

        if ($exitCode -eq 2) {
            Write-Host "" 
            Write-Host "Hint: check requirement ID, spec path, and Python/PowerShell availability." -ForegroundColor Yellow
        }
    }

    exit $exitCode
}
