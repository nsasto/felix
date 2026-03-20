<#
.SYNOPSIS
Helper functions for testing
#>

function New-TestRepository {
    <#
    .SYNOPSIS
    Creates temporary git repository for testing
    #>
    param([string]$Name = "test-repo-$(Get-Random)")

    $repoPath = Join-Path $env:TEMP $Name

    if (Test-Path $repoPath) {
        Remove-Item $repoPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $repoPath -Force | Out-Null

    Push-Location $repoPath
    $env:GIT_TERMINAL_PROMPT = "0"
    git init | Out-Null
    git config user.email "test@felix.dev" | Out-Null
    git config user.name "Felix Test" | Out-Null
    # Rename default branch to main for consistency
    git branch -M main 2>$null

    # Create initial structure
    New-Item -ItemType Directory -Path ".felix" -Force | Out-Null
    New-Item -ItemType Directory -Path "specs" -Force | Out-Null
    New-Item -ItemType Directory -Path "runs" -Force | Out-Null

    # Create minimal config
    @{
        executor = @{
            commit_on_complete = $true
        }
        plugins  = @{
            disabled = @()
        }
    } | ConvertTo-Json -Depth 10 | Set-Content ".felix/config.json"

    # Create minimal requirements
    @{
        requirements = @()
    } | ConvertTo-Json -Depth 10 | Set-Content ".felix/requirements.json"

    # Initial commit
    git add . | Out-Null
    git commit -m "Initial commit" | Out-Null

    # Set this repo as its own origin so git remote commands don't hang
    git remote add origin $repoPath 2>$null

    Pop-Location

    return $repoPath
}

function Remove-TestRepository {
    param([string]$Path)

    if (Test-Path $Path) {
        # Force remove even if files are in use
        Get-ChildItem -Path $Path -Recurse -Force | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-TestRequirement {
    param(
        [string]$Id,
        [string]$Title,
        [string]$Status = "planned",
        [string[]]$DependsOn = @()
    )

    return @{
        id         = $Id
        title      = $Title
        status     = $Status
        depends_on = $DependsOn
        branch     = $null
    }
}

function Set-TestRequirements {
    param(
        [string]$RepoPath,
        [array]$Requirements
    )

    $requirementsFile = Join-Path $RepoPath ".felix/requirements.json"
    @{
        requirements = $Requirements
    } | ConvertTo-Json -Depth 10 | Set-Content $requirementsFile
}

try {
    Export-ModuleMember -Function New-TestRepository, Remove-TestRepository, New-TestRequirement, Set-TestRequirements
}
catch {
    # Allow dot-sourcing this helper from standalone test scripts.
}

