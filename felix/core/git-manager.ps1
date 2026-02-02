<#
.SYNOPSIS
Git operations for Felix agent
#>

function Initialize-FeatureBranch {
    <#
    .SYNOPSIS
    Creates or switches to feature branch for requirement
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementId,

        [string]$BaseBranch = "main"
    )

    $branchName = "feature/$RequirementId"

    # Check if branch exists locally
    $existingBranch = git branch --list $branchName 2>&1
    if ($LASTEXITCODE -eq 0 -and $existingBranch) {
        Write-Verbose "Switching to existing branch: $branchName"
        git checkout $branchName 2>&1 | Out-Null
        return $branchName
    }

    # Check if branch exists remotely
    $remoteBranch = git ls-remote --heads origin $branchName 2>&1
    if ($LASTEXITCODE -eq 0 -and $remoteBranch) {
        Write-Verbose "Checking out remote branch: $branchName"
        git fetch origin $branchName 2>&1 | Out-Null
        git checkout -b $branchName "origin/$branchName" 2>&1 | Out-Null
        return $branchName
    }

    # Create new branch from base
    Write-Verbose "Creating new branch: $branchName from $BaseBranch"
    git checkout $BaseBranch 2>&1 | Out-Null
    git pull origin $BaseBranch 2>&1 | Out-Null
    git checkout -b $branchName 2>&1 | Out-Null

    return $branchName
}

function Get-GitState {
    <#
    .SYNOPSIS
    Captures current git state for guardrail checking
    #>
    param([string]$WorkingDir)

    if ($WorkingDir) {
        Push-Location $WorkingDir
    }
    
    try {
        return @{
            commitHash     = git rev-parse HEAD 2>&1
            branch         = git rev-parse --abbrev-ref HEAD 2>&1
            modifiedFiles  = @(git diff --name-only HEAD 2>&1)
            untrackedFiles = @(git ls-files --others --exclude-standard 2>&1)
            stagedFiles    = @(git diff --cached --name-only 2>&1)
        }
    }
    finally {
        if ($WorkingDir) {
            Pop-Location
        }
    }
}

function Test-GitChanges {
    <#
    .SYNOPSIS
    Checks if there are uncommitted changes
    #>
    param()

    $status = git status --porcelain 2>&1
    return ($null -ne $status -and $status.Length -gt 0)
}

function Invoke-GitCommit {
    <#
    .SYNOPSIS
    Commits changes with proper error handling
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [switch]$Push
    )

    if (-not (Test-GitChanges)) {
        Write-Warning "No changes to commit"
        return $false
    }

    git add . 2>&1 | Out-Null
    git commit -m $Message 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Git commit failed"
    }

    if ($Push) {
        $branch = git rev-parse --abbrev-ref HEAD 2>&1
        git push origin $branch 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Git push failed"
        }
    }

    return $true
}

function Invoke-GitRevert {
    <#
    .SYNOPSIS
    Reverts unauthorized changes (for planning mode guardrails)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$BeforeState,

        [string[]]$AllowedPatterns = @('runs/*', 'felix/state.json', 'felix/requirements.json')
    )

    $afterState = Get-GitState

    # Check for new commits
    if ($afterState.commitHash -ne $BeforeState.commitHash) {
        Write-Warning "Unauthorized commit detected - reverting"
        git reset --soft "$($BeforeState.commitHash)" 2>&1 | Out-Null
    }

    # Check for unauthorized file changes
    $allChanges = $afterState.modifiedFiles + $afterState.untrackedFiles
    foreach ($file in $allChanges) {
        $allowed = $false
        foreach ($pattern in $AllowedPatterns) {
            if ($file -like $pattern) {
                $allowed = $true
                break
            }
        }

        if (-not $allowed) {
            Write-Warning "Unauthorized change detected: $file - reverting"
            if (Test-Path $file) {
                # For tracked files, restore from HEAD
                if ($file -in $afterState.modifiedFiles) {
                    git checkout HEAD -- $file 2>&1 | Out-Null
                }
                # For untracked files, delete them
                else {
                    Remove-Item $file -Force 2>&1 | Out-Null
                }
            }
        }
    }
}

Export-ModuleMember -Function Initialize-FeatureBranch, Get-GitState, Test-GitChanges, Invoke-GitCommit, Invoke-GitRevert
