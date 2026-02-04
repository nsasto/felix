<#
.SYNOPSIS
Backpressure validation for Felix agent
#>

function Get-BackpressureCommands {
    <#
    .SYNOPSIS
    Parses test/build/lint commands from AGENTS.md
    
    .DESCRIPTION
    Looks for these sections in AGENTS.md:
    - "## Run Tests" - test commands
    - "## Build the Project" - build commands
    - "## Lint" - lint commands
    
    Commands are extracted from bash/sh code blocks within these sections.
    
    .PARAMETER AgentsFilePath
    Path to the AGENTS.md file
    
    .PARAMETER ConfigCommands
    Optional array of commands from config.json backpressure.commands
    If provided and non-empty, these take precedence over parsing AGENTS.md
    
    .OUTPUTS
    Array of hashtables with keys: command, type, description
    #>
    param(
        [string]$AgentsFilePath,
        [array]$ConfigCommands = @()
    )
    
    $commands = @()
    
    # If config commands are explicitly provided, use those
    if ($ConfigCommands -and $ConfigCommands.Count -gt 0) {
        Emit-Log -Level "info" -Message "Using commands from config.json" -Component "backpressure"
        foreach ($cmd in $ConfigCommands) {
            $commands += @{
                command     = $cmd
                type        = "config"
                description = "Command from config.json"
            }
        }
        return $commands
    }
    
    # Parse commands from AGENTS.md
    if (-not (Test-Path $AgentsFilePath)) {
        Emit-Log -Level "warn" -Message "AGENTS.md not found at $AgentsFilePath" -Component "backpressure"
        return $commands
    }
    
    Emit-Log -Level "info" -Message "Parsing commands from AGENTS.md" -Component "backpressure"
    $content = Get-Content $AgentsFilePath -Raw
    
    # Define sections to parse and their types
    $sectionPatterns = @(
        @{ pattern = '##\s*Run\s+Tests'; type = 'test'; name = 'Run Tests' }
        @{ pattern = '##\s*Build(\s+the\s+Project)?'; type = 'build'; name = 'Build' }
        @{ pattern = '##\s*Lint'; type = 'lint'; name = 'Lint' }
    )
    
    foreach ($section in $sectionPatterns) {
        # Find section start
        $sectionMatch = [regex]::Match($content, $section.pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        if ($sectionMatch.Success) {
            # Get content from section start to next ## header or end of file
            $sectionStart = $sectionMatch.Index + $sectionMatch.Length
            $nextSectionMatch = [regex]::Match($content.Substring($sectionStart), '^##\s', [System.Text.RegularExpressions.RegexOptions]::Multiline)
            
            if ($nextSectionMatch.Success) {
                $sectionContent = $content.Substring($sectionStart, $nextSectionMatch.Index)
            }
            else {
                $sectionContent = $content.Substring($sectionStart)
            }
            
            # Extract code blocks (```bash, ```sh, or ```)
            $codeBlockPattern = '```(?:bash|sh|powershell|pwsh)?\s*\r?\n([\s\S]*?)```'
            $codeBlocks = [regex]::Matches($sectionContent, $codeBlockPattern)
            
            foreach ($block in $codeBlocks) {
                $blockContent = $block.Groups[1].Value
                
                # Parse individual commands from the code block
                $lines = $blockContent -split '\r?\n'
                
                foreach ($line in $lines) {
                    $trimmedLine = $line.Trim()
                    
                    # Skip empty lines, comments, and placeholder lines
                    if (-not $trimmedLine -or 
                        $trimmedLine.StartsWith('#') -or 
                        $trimmedLine -match '^TODO:' -or
                        $trimmedLine -match '^\s*#') {
                        continue
                    }
                    
                    # Skip lines that are clearly not commands (e.g., "Runs on http://...")
                    if ($trimmedLine -match '^(Runs\s+on|API\s+docs|Example)') {
                        continue
                    }
                    
                    # Add the command
                    $commands += @{
                        command     = $trimmedLine
                        type        = $section.type
                        description = "$($section.name): $trimmedLine"
                    }
                }
            }
        }
    }
    
    Emit-Log -Level "info" -Message "Found $($commands.Count) commands from AGENTS.md" -Component "backpressure"
    foreach ($cmd in $commands) {
        Emit-Log -Level "debug" -Message "[$($cmd.type)] $($cmd.command)" -Component "backpressure"
    }
    
    return $commands
}

function Invoke-BackpressureValidation {
    <#
    .SYNOPSIS
    Executes backpressure validation commands (tests, build, lint) after code changes
    
    .DESCRIPTION
    Runs all backpressure commands parsed from AGENTS.md or config.json.
    Returns a result object indicating success/failure and details.
    
    .PARAMETER WorkingDir
    The project working directory
    
    .PARAMETER AgentsFilePath
    Path to the AGENTS.md file
    
    .PARAMETER Config
    The felix config object (for backpressure settings)
    
    .PARAMETER RunDir
    Directory to write validation logs to
    
    .OUTPUTS
    Hashtable with keys: success (bool), failed_commands (array), output (string)
    #>
    param(
        [string]$WorkingDir,
        [string]$AgentsFilePath,
        [object]$Config,
        [string]$RunDir
    )
    
    $result = @{
        success         = $true
        failed_commands = @()
        output          = ""
        skipped         = $false
    }
    
    # Check if backpressure is enabled
    if (-not $Config.backpressure.enabled) {
        Emit-Log -Level "info" -Message "Backpressure validation is disabled in config" -Component "backpressure"
        $result.skipped = $true
        return $result
    }
    
    # Get backpressure commands
    $configCommands = @()
    if ($Config.backpressure.commands) {
        $configCommands = @($Config.backpressure.commands)
    }
    
    $commands = Get-BackpressureCommands -AgentsFilePath $AgentsFilePath -ConfigCommands $configCommands
    
    if ($commands.Count -eq 0) {
        Emit-Log -Level "warn" -Message "No validation commands found - skipping backpressure" -Component "backpressure"
        $result.skipped = $true
        return $result
    }
    
    Emit-ValidationStarted -CommandCount $commands.Count -ValidationType "backpressure"
    
    $allOutput = @()
    
    Push-Location $WorkingDir
    try {
        foreach ($cmd in $commands) {
            Emit-ValidationCommandStarted -Command $cmd.command -Type $cmd.type
            
            try {
                # Execute the command safely without Invoke-Expression
                $prevErrorAction = $ErrorActionPreference
                $ErrorActionPreference = "Continue"
                
                # Use PowerShell's call operator with scriptblock for safe execution
                $scriptBlock = [scriptblock]::Create($cmd.command)
                $cmdOutput = & $scriptBlock 2>&1
                $exitCode = $LASTEXITCODE
                $ErrorActionPreference = $prevErrorAction
                
                # Convert output to string
                $outputStr = ($cmdOutput | Out-String).Trim()
                $isNoisyTool = $cmd.command -match '\b(npm|vite|pnpm|yarn)\b'
                $hasRemoteException = $outputStr -match 'RemoteException'
                $allOutput += "=== $($cmd.type): $($cmd.command) ==="
                $allOutput += $outputStr
                $allOutput += "Exit code: $exitCode"
                if ($hasRemoteException -and $exitCode -eq 0) {
                    $allOutput += "Warning: stderr output detected (non-fatal)"
                }
                $allOutput += ""
                
                # Exit code 5 for backend tests means "no tests found" - treat as success
                $isBackendTest = $cmd.command -match 'test-backend'
                $isNoTestsFound = $exitCode -eq 5
                
                if ($exitCode -ne 0 -and -not ($isBackendTest -and $isNoTestsFound)) {
                    Emit-ValidationCommandCompleted -Command $cmd.command -Passed $false -ExitCode $exitCode
                    $result.success = $false
                    $result.failed_commands += @{
                        command   = $cmd.command
                        type      = $cmd.type
                        exit_code = $exitCode
                        output    = $outputStr
                    }
                }
                else {
                    Emit-ValidationCommandCompleted -Command $cmd.command -Passed $true -ExitCode $exitCode
                    if ($isBackendTest -and $isNoTestsFound) {
                        Emit-Log -Level "warn" -Message "Command passed (no tests found): $($cmd.command)" -Component "validation"
                    }
                    elseif ($hasRemoteException -and $isNoisyTool) {
                        Emit-Log -Level "warn" -Message "Command passed (stderr output ignored): $($cmd.command)" -Component "validation"
                    }
                }
            }
            catch {
                Emit-ValidationCommandCompleted -Command $cmd.command -Passed $false -ExitCode -1
                Emit-Log -Level "error" -Message "Validation command error: $_" -Component "validation"
                $result.success = $false
                $result.failed_commands += @{
                    command   = $cmd.command
                    type      = $cmd.type
                    exit_code = -1
                    output    = $_.ToString()
                }
                $allOutput += "=== $($cmd.type): $($cmd.command) ==="
                $allOutput += "ERROR: $_"
                $allOutput += ""
            }
        }
    }
    finally {
        Pop-Location
    }
    
    $result.output = $allOutput -join "`n"
    
    # Write validation log to run directory
    if ($RunDir -and (Test-Path $RunDir)) {
        $logPath = Join-Path $RunDir "backpressure.log"
        Set-Content $logPath $result.output -Encoding UTF8
        $projectPath = (Split-Path $RunDir -Parent) | Split-Path -Parent
        $relPath = $logPath.Replace($projectPath + "\", "")
        Emit-Artifact -Path $relPath -Type "log" -SizeBytes (Get-Item $logPath).Length
    }
    
    # Summary
    $passedCount = $commands.Count - $result.failed_commands.Count
    Emit-ValidationCompleted -Passed $result.success -PassedCount $passedCount -FailedCount $result.failed_commands.Count -TotalCount $commands.Count
    
    if ($result.success) {
        Emit-Log -Level "info" -Message "All validation commands passed!" -Component "backpressure"
    }
    else {
        Emit-Log -Level "error" -Message "Validation FAILED - $($result.failed_commands.Count) command(s) failed" -Component "backpressure"
        foreach ($failed in $result.failed_commands) {
            Emit-Log -Level "error" -Message "Failed: [$($failed.type)] $($failed.command)" -Component "backpressure"
        }
    }
    
    return $result
}

