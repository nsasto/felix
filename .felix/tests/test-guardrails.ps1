. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/git-manager.ps1"
. "$PSScriptRoot/../core/guardrails.ps1"
. "$PSScriptRoot/test-helpers.ps1"

Describe "Test-PlanningModeGuardrails" {
    It "should detect no violations in clean state" {
        $repo = New-TestRepository
        Push-Location $repo
        
        try {
            $beforeState = Get-GitState -WorkingDir $repo
            $violations = Test-PlanningModeGuardrails -WorkingDir $repo -BeforeState $beforeState -RunId "test"
            
            Assert-False $violations.HasViolations "Should have no violations"
            Assert-False $violations.CommitMade "Should not detect commit"
            Assert-Equal 0 $violations.UnauthorizedFiles.Count "Should have no unauthorized files"
        }
        finally {
            Pop-Location
            Remove-TestRepository $repo
        }
    }
    
    It "should allow changes to runs directory" {
        $repo = New-TestRepository
        Push-Location $repo
        
        try {
            $beforeState = Get-GitState -WorkingDir $repo
            
            # Create a file in runs directory
            $runDir = Join-Path $repo "runs\test-run"
            New-Item -ItemType Directory -Path $runDir -Force | Out-Null
            "test content" | Set-Content (Join-Path $runDir "output.txt")
            
            $violations = Test-PlanningModeGuardrails -WorkingDir $repo -BeforeState $beforeState
            
            Assert-False $violations.HasViolations "Runs directory changes should be allowed"
        }
        finally {
            Pop-Location
            Remove-TestRepository $repo
        }
    }
    
    It "should allow changes to .felix/state.json" {
        $repo = New-TestRepository
        Push-Location $repo
        
        try {
            $beforeState = Get-GitState -WorkingDir $repo
            
            # Modify state.json
            @{ test = "data" } | ConvertTo-Json | Set-Content (Join-Path $repo "felix\state.json")
            
            $violations = Test-PlanningModeGuardrails -WorkingDir $repo -BeforeState $beforeState
            
            Assert-False $violations.HasViolations "State file changes should be allowed"
        }
        finally {
            Pop-Location
            Remove-TestRepository $repo
        }
    }
    
    It "should detect unauthorized file modifications" {
        $repo = New-TestRepository
        Push-Location $repo
        
        try {
            $beforeState = Get-GitState -WorkingDir $repo
            
            # Create unauthorized file
            "unauthorized" | Set-Content (Join-Path $repo "app.py")
            
            $violations = Test-PlanningModeGuardrails -WorkingDir $repo -BeforeState $beforeState
            
            Assert-True $violations.HasViolations "Should detect violation"
            Assert-True ($violations.UnauthorizedFiles -contains "app.py") "Should list unauthorized file"
        }
        finally {
            Pop-Location
            Remove-TestRepository $repo
        }
    }
    
    It "should detect unauthorized commit" {
        $repo = New-TestRepository
        Push-Location $repo
        
        try {
            $beforeState = Get-GitState -WorkingDir $repo
            
            # Make unauthorized commit
            "test" | Set-Content (Join-Path $repo "test.txt")
            git add test.txt | Out-Null
            git commit -m "unauthorized" | Out-Null
            
            $violations = Test-PlanningModeGuardrails -WorkingDir $repo -BeforeState $beforeState
            
            Assert-True $violations.HasViolations "Should detect violation"
            Assert-True $violations.CommitMade "Should detect commit"
        }
        finally {
            Pop-Location
            Remove-TestRepository $repo
        }
    }
}

Describe "Undo-PlanningViolations" {
    It "should revert unauthorized commit" {
        $repo = New-TestRepository
        Push-Location $repo
        
        try {
            $beforeState = Get-GitState -WorkingDir $repo
            $beforeCommit = $beforeState.commitHash
            
            # Make unauthorized commit
            "test" | Set-Content (Join-Path $repo "test.txt")
            git add test.txt | Out-Null
            git commit -m "unauthorized" | Out-Null
            
            $violations = @{ CommitMade = $true; UnauthorizedFiles = @(); HasViolations = $true }
            Undo-PlanningViolations -WorkingDir $repo -BeforeState $beforeState -Violations $violations
            
            $afterState = Get-GitState -WorkingDir $repo
            Assert-Equal $beforeCommit $afterState.commitHash "Should revert to before commit"
        }
        finally {
            Pop-Location
            Remove-TestRepository $repo
        }
    }
    
    It "should remove unauthorized new files" {
        $repo = New-TestRepository
        Push-Location $repo
        
        try {
            $beforeState = Get-GitState -WorkingDir $repo
            
            # Create unauthorized file
            $unauthorizedFile = Join-Path $repo "unauthorized.txt"
            "test" | Set-Content $unauthorizedFile
            
            $violations = @{ CommitMade = $false; UnauthorizedFiles = @("unauthorized.txt"); HasViolations = $true }
            Undo-PlanningViolations -WorkingDir $repo -BeforeState $beforeState -Violations $violations
            
            Assert-False (Test-Path $unauthorizedFile) "Should remove unauthorized file"
        }
        finally {
            Pop-Location
            Remove-TestRepository $repo
        }
    }
}

Get-TestResults

