
function Show-Version {
    Write-Host ""
    Write-Host "Felix CLI v0.3.0-alpha (Phase 1: PowerShell)" -ForegroundColor Cyan
    Write-Host "Repository: $RepoRoot" -ForegroundColor Gray
    
    # Try to get git info
    try {
        $gitBranch = git rev-parse --abbrev-ref HEAD 2>$null
        $gitCommit = git rev-parse --short HEAD 2>$null
        if ($gitBranch) {
            Write-Host "Branch: $gitBranch" -ForegroundColor Gray
            Write-Host "Commit: $gitCommit" -ForegroundColor Gray
        }
    }
    catch {
        # Git not available or not a git repo
    }
    
    Write-Host ""
}
