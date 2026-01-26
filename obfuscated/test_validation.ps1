# test-validation.ps1
# Use this to verify the Python parameter binding fix

$ErrorActionPreference = "Stop"

# 1. Mock the PythonInfo object (adjust 'args' to match your config.json)
$pythonInfo = @{
    cmd  = "py"      # Or the full path to your python.exe
    args = @("-3")   # Use @() for no args or @("-3") for the launcher
}

# 2. Define the script and requirement ID (adjust paths as needed)
$validationScript = Join-Path $PSScriptRoot "scripts\validate-requirement.py"
$requirementId = "S-0005"

function Test-InvokeValidation {
    param(
        [hashtable]$PythonInfo,
        [string]$ValidationScript,
        [string]$RequirementId
    )

    $pythonExe = $PythonInfo.cmd
    [array]$pythonArgs = $PythonInfo.args

    Write-Host "`n--- Testing Parameter Binding ---" -ForegroundColor Cyan
    Write-Host "Executable: $pythonExe"
    Write-Host "Args: $($pythonArgs -join ' ')"
    Write-Host "Script: $ValidationScript"
    
    # Temporarily allow stderr (Root Cause #4)
    $prevError = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        # Root Cause #3 Fix: Flatten all arguments into one array
        [array]$allArguments = @()
        if ($pythonArgs) { $allArguments += $pythonArgs }
        $allArguments += $ValidationScript
        $allArguments += $RequirementId

        Write-Host "Flattened Array Count: $($allArguments.Count)"
        
        # USE THE @ OPERATOR TO SPLAT
        $output = & $pythonExe @allArguments 2>&1
        $exitCode = $LASTEXITCODE
        
        return @{ output = $output; exitCode = $exitCode }
    }
    catch {
        return @{ output = $_.Exception.Message; exitCode = 1 }
    }
    finally {
        $ErrorActionPreference = $prevError
    }
}

# Run the test
if (-not (Test-Path $validationScript)) {
    Write-Host "ERROR: Could not find $validationScript. Please check the path." -ForegroundColor Red
} else {
    $result = Test-InvokeValidation -PythonInfo $pythonInfo -ValidationScript $validationScript -RequirementId $requirementId
    
    Write-Host "`n--- Execution Result ---" -ForegroundColor Cyan
    Write-Host "Exit Code: $($result.exitCode)"
    Write-Host "Output:"
    Write-Host $result.output
}