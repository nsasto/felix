param(
    [Parameter(Mandatory = $true)]
    [hashtable]$HookData,
    
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    
    [Parameter(Mandatory = $true)]
    $PluginConfig
)

# Add git statistics if enabled
$additionalContext = ""

if ($PluginConfig.config.add_git_stats) {
    try {
        # Get recent commit count
        $commitCount = (git log --oneline --since="7 days ago" 2>$null | Measure-Object -Line).Lines
        
        # Get files changed recently
        $recentFiles = git diff --name-only HEAD~5..HEAD 2>$null | Select-Object -Unique
        
        if ($commitCount -gt 0) {
            $additionalContext += "## Recent Repository Activity`n`n"
            $additionalContext += "- Commits in last 7 days: $commitCount`n"
            
            if ($recentFiles) {
                $additionalContext += "- Recently modified files:`n"
                foreach ($file in $recentFiles) {
                    $additionalContext += "  - $file`n"
                }
            }
            
            $additionalContext += "`n"
        }
    }
    catch {
        Write-Verbose "[prompt-enhancer] Failed to get git stats: $_"
    }
}

# Store additional context for OnPreLLM hook
if ($additionalContext) {
    Set-PluginTransientState -PluginName "prompt-enhancer" -RunId $RunId -Key "additional_context" -Value $additionalContext
}

return @{ AdditionalContext = $additionalContext }
