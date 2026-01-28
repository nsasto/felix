#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates requirement acceptance criteria from spec files

.DESCRIPTION
    Reads acceptance criteria from spec markdown files and executes
    validation commands to verify requirements are complete and working.

.PARAMETER RequirementId
    The requirement ID to validate (e.g., S-0001, S-0002)

.EXAMPLE
    .\validate-requirement.ps1 S-0002

.NOTES
    Exit Codes:
      0 - All acceptance criteria passed
      1 - One or more acceptance criteria failed
      2 - Invalid arguments or requirement not found
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$RequirementId
)

$ErrorActionPreference = "Stop"

# Enable UTF-8 output for emoji support
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Exit code constants
$EXIT_SUCCESS = 0
$EXIT_FAILURE = 1
$EXIT_ERROR = 2

# Track background server processes for cleanup
$script:ServerProcesses = @()

# ============================================================================
# Helper Functions
# ============================================================================

function Find-ProjectRoot {
    <#
    .SYNOPSIS
    Locates the project root by searching for felix/ and specs/ directories
    #>
    $currentPath = Get-Location
    $maxDepth = 10
    $depth = 0
    
    while ($depth -lt $maxDepth) {
        $felixPath = Join-Path $currentPath "felix"
        $specsPath = Join-Path $currentPath "specs"
        
        if ((Test-Path $felixPath -PathType Container) -and 
            (Test-Path $specsPath -PathType Container)) {
            return $currentPath
        }
        
        $parent = Split-Path $currentPath -Parent
        if (-not $parent -or $parent -eq $currentPath) {
            break
        }
        $currentPath = $parent
        $depth++
    }
    
    throw "Could not find project root (no felix/ and specs/ directories found)"
}

function Load-JsonFile {
    <#
    .SYNOPSIS
    Loads and parses a JSON file
    #>
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        return $null
    }
    
    $content = Get-Content $Path -Raw -Encoding UTF8
    return $content | ConvertFrom-Json
}

function Write-ColorOutput {
    <#
    .SYNOPSIS
    Writes colored output with emoji symbols
    #>
    param(
        [string]$Message,
        [ValidateSet("Success", "Failure", "Warning", "Info")]
        [string]$Type = "Info"
    )
    
    $symbol = switch ($Type) {
        "Success" { "[OK]" }
        "Failure" { "[FAIL]" }
        "Warning" { "[WARN]" }
        "Info" { "[INFO]" }
    }
    
    $color = switch ($Type) {
        "Success" { "Green" }
        "Failure" { "Red" }
        "Warning" { "Yellow" }
        "Info" { "Cyan" }
    }
    
    Write-Host "$symbol $Message" -ForegroundColor $color
}

function Find-SpecFile {
    <#
    .SYNOPSIS
    Finds the spec file for a given requirement ID
    #>
    param(
        [string]$ProjectRoot,
        [string]$RequirementId
    )
    
    # Try to get from requirements.json first
    $reqPath = Join-Path $ProjectRoot "felix/requirements.json"
    if (Test-Path $reqPath) {
        $reqData = Load-JsonFile $reqPath
        $requirement = $reqData.requirements | Where-Object { $_.id -eq $RequirementId }
        
        if ($requirement -and $requirement.spec_path) {
            $specPath = Join-Path $ProjectRoot $requirement.spec_path
            if (Test-Path $specPath) {
                return $specPath
            }
        }
    }
    
    # Fallback: search specs/ directory
    $specsDir = Join-Path $ProjectRoot "specs"
    $pattern = "$RequirementId-*.md"
    $matches = Get-ChildItem -Path $specsDir -Filter $pattern -File
    
    if ($matches -and $matches.Count -gt 0) {
        return $matches[0].FullName
    }
    
    return $null
}

function Get-RequirementLabels {
    <#
    .SYNOPSIS
    Gets labels for a requirement from requirements.json
    #>
    param(
        [string]$ProjectRoot,
        [string]$RequirementId
    )
    
    $reqPath = Join-Path $ProjectRoot "felix/requirements.json"
    if (-not (Test-Path $reqPath)) {
        return @()
    }
    
    $reqData = Load-JsonFile $reqPath
    $requirement = $reqData.requirements | Where-Object { $_.id -eq $RequirementId }
    
    if ($requirement -and $requirement.labels) {
        return $requirement.labels
    }
    
    return @()
}

function Parse-AcceptanceCriteria {
    <#
    .SYNOPSIS
    Parses markdown spec to extract acceptance criteria with commands and expected outcomes
    #>
    param([string]$SpecContent)
    
    $criteria = @()
    
    # Look for "## Validation Criteria" first, fallback to "## Acceptance Criteria"
    $validationMatch = [regex]::Match($SpecContent, '(?m)^##\s*Validation\s+Criteria\s*$')
    $acceptanceMatch = [regex]::Match($SpecContent, '(?m)^##\s*Acceptance\s+Criteria\s*$')
    
    $sectionMatch = if ($validationMatch.Success) { $validationMatch } else { $acceptanceMatch }
    
    if (-not $sectionMatch.Success) {
        return $criteria
    }
    
    # Extract section content until next ## header
    $sectionStart = $sectionMatch.Index + $sectionMatch.Length
    $nextHeaderMatch = [regex]::Match($SpecContent.Substring($sectionStart), '(?m)^##\s+')
    
    $sectionContent = if ($nextHeaderMatch.Success) {
        $SpecContent.Substring($sectionStart, $nextHeaderMatch.Index)
    }
    else {
        $SpecContent.Substring($sectionStart)
    }
    
    # Parse checklist items
    $itemPattern = '(?m)^[\s]*-\s*\[([ xX])\]\s*(.+)$'
    $items = [regex]::Matches($sectionContent, $itemPattern)
    
    foreach ($item in $items) {
        $checked = $item.Groups[1].Value -match '[xX]'
        $text = $item.Groups[2].Value.Trim()
        
        $criterion = @{
            Text     = $text
            Command  = $null
            Expected = $null
            Checked  = $checked
        }
        
        # Extract command from backticks
        if ($text -match '`([^`]+)`') {
            $criterion.Command = $Matches[1]
        }
        
        # Extract expected outcome from parentheses at end
        if ($text -match '\(([^)]+)\)\s*$') {
            $criterion.Expected = $Matches[1]
        }
        
        $criteria += $criterion
    }
    
    return $criteria
}

function ConvertTo-PlatformCommand {
    <#
    .SYNOPSIS
    Converts Unix-style commands to platform-appropriate equivalents
    #>
    param(
        [string]$Command
    )
    
    $isWindows = $IsWindows -or $PSVersionTable.PSVersion.Major -lt 6
    
    if (-not $isWindows) {
        # Unix/Mac - return as-is
        return $Command
    }
    
    # Windows platform mappings
    $cmd = $Command.Trim()
    
    # WebSocket testing: wscat -> PowerShell Test-WebSocket or skip
    if ($cmd -like "*wscat*") {
        # Check if wscat is available
        $wscatAvailable = $null -ne (Get-Command wscat -ErrorAction SilentlyContinue)
        if (-not $wscatAvailable) {
            # Check if npm is available to install it
            $npmAvailable = $null -ne (Get-Command npm -ErrorAction SilentlyContinue)
            if ($npmAvailable) {
                Write-Host "  [INFO] Installing wscat globally via npm..." -ForegroundColor Cyan
                try {
                    $null = npm install -g wscat 2>&1
                    # Verify installation
                    $wscatAvailable = $null -ne (Get-Command wscat -ErrorAction SilentlyContinue)
                    if ($wscatAvailable) {
                        Write-Host "  [OK] wscat installed successfully" -ForegroundColor Green
                        return $cmd
                    }
                }
                catch {
                    Write-Host "  [WARN] Failed to install wscat: $_" -ForegroundColor Yellow
                }
            }
            
            if (-not $wscatAvailable) {
                Write-Host "  [SKIP] wscat not available (install Node.js and npm, then run 'npm install -g wscat')" -ForegroundColor Yellow
                return $null  # Skip this test
            }
        }
    }
    
    # curl is available on Windows 10+ but might need different syntax
    # Keep curl as-is since it works on modern Windows
    
    return $cmd
}

function Test-ServerCommand {
    <#
    .SYNOPSIS
    Heuristic to detect commands that start long-running servers
    #>
    param(
        [string]$Command,
        [string]$WorkingDir
    )
    
    $cmd = $Command.ToLower()
    
    # Exclude test commands first
    if ($cmd -like "*pytest*" -or $cmd -like "*test*") {
        return $false
    }
    
    $serverKeywords = @('uvicorn', 'flask', 'fastapi', 'gunicorn', 'hypercorn', 'npm run dev', 'vite')
    
    foreach ($keyword in $serverKeywords) {
        if ($cmd -like "*$keyword*") {
            return $true
        }
    }
    
    # Check for python main.py or app/backend patterns
    if ($cmd -like "*python*" -and $cmd -like "*main.py*") {
        return $true
    }
    
    if ($cmd -like "*python*" -and $cmd -like "*app/backend*" -and $cmd -notlike "*test*") {
        return $true
    }
    
    # Check if working directory is 'backend' and command contains python
    if ($WorkingDir -and (Split-Path $WorkingDir -Leaf) -eq "backend" -and $cmd -like "*python*" -and $cmd -notlike "*test*") {
        return $true
    }
    
    return $false
}

function Invoke-ValidationCommand {
    <#
    .SYNOPSIS
    Executes a validation command with timeout support and server detection
    #>
    param(
        [string]$Command,
        [string]$WorkingDir,
        [int]$TimeoutSeconds = 120
    )
    
    $originalDir = $WorkingDir
    
    # Handle 'cd' prefix in command
    if ($Command -match '^cd\s+([^&|]+)\s*(?:&&)\s*(.+)$') {
        $cdPath = $Matches[1].Trim()
        $remainingCommand = $Matches[2].Trim()
        
        # Resolve path
        if ([System.IO.Path]::IsPathRooted($cdPath)) {
            $WorkingDir = $cdPath
        }
        else {
            $WorkingDir = Join-Path $WorkingDir $cdPath
        }
        
        $Command = $remainingCommand
        
        if (-not $Command) {
            # Just a cd command, nothing to execute
            return [PSCustomObject]@{
                Success  = $true
                Output   = ""
                ExitCode = 0
            }
        }
    }
    
    # Detect if this is a server command
    $isServer = Test-ServerCommand -Command $Command -WorkingDir $WorkingDir
    
    if ($isServer) {
        return Invoke-ServerCommand -Command $Command -WorkingDir $WorkingDir
    }
    else {
        return Invoke-NormalCommand -Command $Command -WorkingDir $WorkingDir -TimeoutSeconds $TimeoutSeconds
    }
}

function Invoke-ServerCommand {
    <#
    .SYNOPSIS
    Executes a server command in the background using .NET Process class
    #>
    param(
        [string]$Command,
        [string]$WorkingDir
    )
    
    Write-Host "  Starting server in background: $Command"
    
    # Use .NET Process class for full control
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    
    # Platform-specific shell
    if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
        $processInfo.FileName = "cmd.exe"
        $processInfo.Arguments = "/c $Command"
    }
    else {
        $processInfo.FileName = "/bin/sh"
        $processInfo.Arguments = "-c `"$Command`""
    }
    
    $processInfo.WorkingDirectory = $WorkingDir
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    
    try {
        [void]$process.Start()
        $script:ServerProcesses += $process
        
        # Wait briefly for startup
        Start-Sleep -Seconds 3
        
        if ($process.HasExited) {
            return [PSCustomObject]@{
                Success  = $false
                Output   = "Server process exited immediately"
                ExitCode = $process.ExitCode
            }
        }
        
        Write-Host "  Server started (PID: $($process.Id))"
        return [PSCustomObject]@{
            Success  = $true
            Output   = "Server running in background"
            ExitCode = 0
        }
    }
    catch {
        return [PSCustomObject]@{
            Success  = $false
            Output   = "Failed to start server: $_"
            ExitCode = 1
        }
    }
}

function Invoke-NormalCommand {
    <#
    .SYNOPSIS
    Executes a normal command with robust timeout using Start-Job
    #>
    param(
        [string]$Command,
        [string]$WorkingDir,
        [int]$TimeoutSeconds
    )
    
    Write-Host "  Running: $Command"
    
    # Use Start-Job for robust timeout handling
    $job = Start-Job -ScriptBlock {
        param($cmd, $wd, $isWindows)
        
        Set-Location $wd
        
        # Platform-specific execution - suppress stderr noise
        $ErrorActionPreference = 'Continue'
        if ($isWindows) {
            $output = cmd /c $cmd 2>&1 | Out-String
        }
        else {
            $output = /bin/sh -c $cmd 2>&1 | Out-String
        }
        
        return @{
            Output   = $output
            ExitCode = $LASTEXITCODE
        }
    } -ArgumentList $Command, $WorkingDir, ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6)
    
    # Wait with timeout
    $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
    
    if ($completed) {
        $result = Receive-Job -Job $job
        Remove-Job -Job $job -Force
        
        return [PSCustomObject]@{
            Success  = ($result.ExitCode -eq 0)
            Output   = $result.Output
            ExitCode = $result.ExitCode
        }
    }
    else {
        # Timeout occurred
        Stop-Job -Job $job
        Remove-Job -Job $job -Force
        
        return [PSCustomObject]@{
            Success  = $false
            Output   = "Command timed out after $TimeoutSeconds seconds"
            ExitCode = 1
        }
    }
}

function Test-ExpectedOutcome {
    <#
    .SYNOPSIS
    Validates command result against expected outcome
    #>
    param(
        [PSCustomObject]$Result,
        [string]$Expected
    )
    
    if (-not $Expected) {
        # No expectation specified, just check success
        return $Result.Success
    }
    
    $expectedLower = $Expected.ToLower()
    
    # Check for exit code expectations
    if ($expectedLower -match 'exit code\s*(\d+)') {
        $expectedCode = [int]$Matches[1]
        return ($Result.ExitCode -eq $expectedCode)
    }
    
    # Check for HTTP status expectations
    if ($expectedLower -match 'status') {
        # Look for HTTP status code in output (curl shows it, or JSON response indicates success)
        if ($Result.Output -match 'status.*?(\d{3})' -or $Result.Output -match '"status"\s*:\s*"\w+"') {
            return $true
        }
        # If exit code is 0 and we got output, consider it success
        if ($Result.ExitCode -eq 0 -and $Result.Output) {
            return $true
        }
        return $false
    }
    
    # Default: check exit code is 0
    return ($Result.ExitCode -eq 0)
}

function Get-LabelBasedCommands {
    <#
    .SYNOPSIS
    Maps requirement labels to test commands
    #>
    param(
        [array]$Labels,
        [string]$ProjectRoot
    )
    
    $commands = @()
    
    if ($Labels -contains "backend") {
        $backendPath = Join-Path $ProjectRoot "app/backend"
        if (Test-Path $backendPath) {
            # Check if pytest is available
            $testPath = Join-Path $backendPath "tests"
            if (Test-Path $testPath) {
                $commands += @{
                    Name       = "backend pytest"
                    Command    = "python -m pytest"
                    WorkingDir = $backendPath
                }
            }
        }
    }
    
    if ($Labels -contains "frontend") {
        $frontendPath = Join-Path $ProjectRoot "app/frontend"
        if (Test-Path $frontendPath) {
            # Check if package.json has a test script
            $packageJsonPath = Join-Path $frontendPath "package.json"
            if (Test-Path $packageJsonPath) {
                $packageJson = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
                if ($packageJson.scripts.test) {
                    $commands += @{
                        Name       = "frontend tests"
                        Command    = "npm test"
                        WorkingDir = $frontendPath
                    }
                }
            }
        }
    }
    
    return $commands
}

function Invoke-RequirementValidation {
    <#
    .SYNOPSIS
    Main validation orchestrator
    #>
    param(
        [string]$RequirementId
    )
    
    Write-Host ""
    Write-Host ("=" * 60)
    Write-Host "  Validating Requirement: $RequirementId"
    Write-Host ("=" * 60)
    Write-Host ""
    
    try {
        # Find project root
        $projectRoot = Find-ProjectRoot
        Write-Host "Project root: $projectRoot"
        
        # Find spec file
        $specFile = Find-SpecFile -ProjectRoot $projectRoot -RequirementId $RequirementId
        if (-not $specFile) {
            Write-Host "Error: Could not find spec file for $RequirementId" -ForegroundColor Red
            return $EXIT_ERROR
        }
        
        Write-Host "Spec file: $specFile"
        
        # Load spec content
        $specContent = Get-Content $specFile -Raw -Encoding UTF8
        
        # Parse acceptance criteria
        $criteria = Parse-AcceptanceCriteria -SpecContent $specContent
        
        if ($criteria.Count -eq 0) {
            Write-Host ""
            Write-ColorOutput "No acceptance criteria found in spec" "Warning"
            Write-Host "Add '## Acceptance Criteria' section with checklist items"
            return $EXIT_SUCCESS
        }
        
        Write-Host ""
        Write-Host "Found $($criteria.Count) acceptance criteria"
        Write-Host ""
        
        # Get labels
        $labels = Get-RequirementLabels -ProjectRoot $projectRoot -RequirementId $RequirementId
        Write-Host "Requirement labels: $($labels -join ', ')"
        Write-Host ""
        
        # Validate each criterion
        $allPassed = $true
        $results = @()
        
        Write-Host "Checking acceptance criteria:"
        Write-Host ("-" * 40)
        
        foreach ($criterion in $criteria) {
            if ($criterion.Checked) {
                # Already marked complete
                $results += $true
                Write-ColorOutput "[Already checked] $($criterion.Text)" "Success"
                continue
            }
            
            if (-not $criterion.Command) {
                # Manual verification required
                $results += $true
                Write-ColorOutput "Manual verification required: $($criterion.Text)" "Warning"
                continue
            }
            
            # Convert command to platform-specific equivalent
            $platformCommand = ConvertTo-PlatformCommand -Command $criterion.Command
            if ($null -eq $platformCommand) {
                # Command was skipped (tool not available)
                $results += $true
                continue
            }
            
            # Execute command
            $result = Invoke-ValidationCommand -Command $platformCommand -WorkingDir $projectRoot
            
            # Check expected outcome
            $passed = Test-ExpectedOutcome -Result $result -Expected $criterion.Expected
            $results += $passed
            
            if ($passed) {
                Write-ColorOutput "$($criterion.Text)" "Success"
            }
            else {
                Write-ColorOutput "$($criterion.Text)" "Failure"
                Write-Host "  Output: $($result.Output)"
                $allPassed = $false
            }
        }
        
        # Run label-based commands
        $labelCommands = Get-LabelBasedCommands -Labels $labels -ProjectRoot $projectRoot
        
        if ($labelCommands.Count -gt 0) {
            Write-Host ""
            Write-Host "Running label-based validation:"
            Write-Host ("-" * 40)
            
            foreach ($cmdInfo in $labelCommands) {
                Write-Host "  Running: $($cmdInfo.Name) ($($cmdInfo.Command))"
                $result = Invoke-ValidationCommand -Command $cmdInfo.Command -WorkingDir $cmdInfo.WorkingDir
                
                if ($result.Success) {
                    Write-ColorOutput "$($cmdInfo.Name)" "Success"
                }
                else {
                    Write-ColorOutput "$($cmdInfo.Name)" "Failure"
                    Write-Host "  Output: $($result.Output)"
                    $allPassed = $false
                }
            }
        }
        
        # Summary
        Write-Host ""
        Write-Host ("=" * 60)
        if ($allPassed) {
            Write-ColorOutput "VALIDATION PASSED for $RequirementId" "Success"
        }
        else {
            Write-ColorOutput "VALIDATION FAILED for $RequirementId" "Failure"
        }
        Write-Host ("=" * 60)
        Write-Host ""
        
        if ($allPassed) {
            return $EXIT_SUCCESS
        }
        else {
            return $EXIT_FAILURE
        }
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor Red
        return $EXIT_ERROR
    }
    finally {
        # Cleanup server processes
        if ($script:ServerProcesses.Count -gt 0) {
            Write-Host ""
            Write-Host "Cleaning up server processes..."
            
            foreach ($process in $script:ServerProcesses) {
                try {
                    if (-not $process.HasExited) {
                        Write-Host "  Terminating PID $($process.Id)..."
                        $process.Kill()
                        $process.WaitForExit(5000) | Out-Null
                    }
                }
                catch {
                    # Swallow cleanup errors
                }
            }
            
            $script:ServerProcesses = @()
        }
    }
}

# ============================================================================
# Main Entry Point
# ============================================================================

# Validate requirement ID format (warning only)
if ($RequirementId -notmatch '^S-\d{4}$') {
    Write-Host "Warning: Requirement ID '$RequirementId' doesn't match expected format (S-####)" -ForegroundColor Yellow
}

# Run validation
$exitCode = Invoke-RequirementValidation -RequirementId $RequirementId

exit $exitCode
