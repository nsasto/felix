param(
    [Parameter(Mandatory = $true)]
    [hashtable]$HookData,
    
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    
    [Parameter(Mandatory = $true)]
    $PluginConfig
)

$modifiedPrompt = $HookData.FullPrompt

# Add recent errors if enabled
if ($PluginConfig.config.add_recent_errors) {
    # Look for error logs in recent runs
    $runsDir = "runs"
    if (Test-Path $runsDir) {
        $recentRuns = Get-ChildItem $runsDir -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 3
        
        $errors = @()
        foreach ($run in $recentRuns) {
            $reportPath = Join-Path $run.FullName "report.md"
            if (Test-Path $reportPath) {
                $report = Get-Content $reportPath -Raw
                if ($report -match '\*\*Success:\*\*\s*false') {
                    $errors += "Run $($run.Name): Failed"
                }
            }
        }
        
        if ($errors.Count -gt 0) {
            $errorSection = "`n`n---`n`n# Recent Errors to Avoid`n`n"
            $errorSection += "The following recent iterations encountered errors:`n`n"
            foreach ($error in $errors) {
                $errorSection += "- $error`n"
            }
            $errorSection += "`nPlease learn from these failures and avoid repeating the same mistakes.`n"
            
            $modifiedPrompt += $errorSection
        }
    }
}

# Add coding standards if enabled
if ($PluginConfig.config.add_coding_standards) {
    $standardsPath = "docs/CODING_STANDARDS.md"
    if (Test-Path $standardsPath) {
        $standards = Get-Content $standardsPath -Raw
        $modifiedPrompt += "`n`n---`n`n# Coding Standards`n`n$standards`n"
    }
}

# Add best practices reminder
$bestPractices = @"

---

# Best Practices Reminder

- Always run tests before marking a task complete
- Write clear, self-documenting code
- Follow existing code patterns in the repository
- Update documentation when changing functionality
- Use meaningful commit messages

"@

$modifiedPrompt += $bestPractices

return @{ ModifiedPrompt = $modifiedPrompt; SkipLLM = $false }
