<#
.SYNOPSIS
Tests for git operations
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/test-helpers.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/git-manager.ps1"

# Prevent git from prompting for credentials (causes test hangs)
$env:GIT_TERMINAL_PROMPT = "0"

Describe "Feature Branch Initialization" {

    It "should create new feature branch" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        $branch = Initialize-FeatureBranch -RequirementId "S-0001" -BaseBranch "main"

        Assert-Equal "feature/S-0001" $branch

        $currentBranch = git rev-parse --abbrev-ref HEAD
        Assert-Equal "feature/S-0001" $currentBranch

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should switch to existing branch" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        # Create branch first time
        Initialize-FeatureBranch -RequirementId "S-0001" | Out-Null

        # Switch back to main
        git checkout main | Out-Null

        # Initialize again - should switch, not create
        $branch = Initialize-FeatureBranch -RequirementId "S-0001"

        Assert-Equal "feature/S-0001" $branch
        $currentBranch = git rev-parse --abbrev-ref HEAD
        Assert-Equal "feature/S-0001" $currentBranch

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should use custom base branch" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        # Create develop branch
        git checkout -b develop | Out-Null
        "test" | Out-File "dev.txt"
        git add . | Out-Null
        git commit -m "Dev commit" | Out-Null

        $branch = Initialize-FeatureBranch -RequirementId "S-0001" -BaseBranch "develop"

        Assert-Equal "feature/S-0001" $branch

        Pop-Location
        Remove-TestRepository $repoPath
    }
}

Describe "Git State Capture" {

    It "should report no repository when .git is missing" {
        $projectRoot = Join-Path $env:TEMP "git-state-$(Get-Random)"
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Push-Location $projectRoot

        try {
            Assert-False (Test-GitRepository -WorkingDir $projectRoot)

            $state = Get-GitState

            Assert-Null $state.commitHash
            Assert-Null $state.branch
            Assert-Equal 0 $state.modifiedFiles.Count
            Assert-Equal 0 $state.untrackedFiles.Count
            Assert-Equal 0 $state.stagedFiles.Count
            Assert-False (Test-GitChanges)
        }
        finally {
            Pop-Location
            Remove-Item $projectRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should capture clean state" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        $state = Get-GitState

        Assert-NotNull $state.commitHash
        $currentBranch = git rev-parse --abbrev-ref HEAD
        Assert-Equal $currentBranch $state.branch
        Assert-Equal 0 $state.modifiedFiles.Count
        Assert-Equal 0 $state.untrackedFiles.Count

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should detect modified files" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        # Modify a file
        "changed" | Out-File ".felix/config.json"

        $state = Get-GitState

        Assert-True ($state.modifiedFiles.Count -gt 0)
        Assert-Contains $state.modifiedFiles ".felix/config.json"

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should detect untracked files" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        # Create new file
        "new" | Out-File "newfile.txt"

        $state = Get-GitState

        Assert-True ($state.untrackedFiles.Count -gt 0)
        Assert-Contains $state.untrackedFiles "newfile.txt"

        Pop-Location
        Remove-TestRepository $repoPath
    }
}

Describe "Git Change Detection" {

    It "should return false for clean working directory" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        $hasChanges = Test-GitChanges

        Assert-False $hasChanges

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should return true when files are modified" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        "changed" | Out-File ".felix/config.json"

        $hasChanges = Test-GitChanges

        Assert-True $hasChanges

        Pop-Location
        Remove-TestRepository $repoPath
    }
}

Describe "Git Commit Operations" {

    It "should commit changes successfully" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        # Make a change
        "changed" | Out-File ".felix/config.json"

        $result = Invoke-GitCommit -Message "Test commit"

        Assert-True $result

        # Verify commit exists
        $log = git log --oneline -1
        Assert-True ($log -match "Test commit")

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should not commit when no changes" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        $result = Invoke-GitCommit -Message "Test commit"

        Assert-False $result

        Pop-Location
        Remove-TestRepository $repoPath
    }
}

Describe "Git Revert Operations" {

    It "should revert unauthorized file changes" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        $beforeState = Get-GitState

        # Modify unauthorized file
        "changed" | Out-File "unauthorized.txt"

        # Revert with allowed patterns
        Invoke-GitRevert -BeforeState $beforeState -AllowedPatterns @('runs/*', '.felix/state.json')

        # File should not exist
        Assert-False (Test-Path "unauthorized.txt")

        Pop-Location
        Remove-TestRepository $repoPath
    }

    It "should preserve allowed file changes" {
        $repoPath = New-TestRepository
        Push-Location $repoPath

        $beforeState = Get-GitState

        # Create allowed directory
        New-Item -ItemType Directory -Path "runs/test" -Force | Out-Null

        # Modify allowed file
        "changed" | Out-File "runs/test/output.log"

        # Revert with allowed patterns
        Invoke-GitRevert -BeforeState $beforeState -AllowedPatterns @('runs/*')

        # File should still exist
        Assert-True (Test-Path "runs/test/output.log")

        Pop-Location
        Remove-TestRepository $repoPath
    }
}

Get-TestResults

