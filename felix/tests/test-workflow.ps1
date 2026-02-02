. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/workflow.ps1"

Describe "Set-WorkflowStage" {
    It "should silently skip when helper script doesn't exist" {
        $testPath = Join-Path $env:TEMP "test-workflow-$(Get-Random)"
        New-Item -ItemType Directory -Path $testPath -Force | Out-Null
        
        try {
            # Should not throw when helper script is missing
            Set-WorkflowStage -Stage "test_stage" -ProjectPath $testPath
            Assert-True $true "Function completed without error"
        }
        finally {
            Remove-Item $testPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    It "should call helper script with Stage parameter" {
        $testPath = Join-Path $env:TEMP "test-workflow-$(Get-Random)"
        New-Item -ItemType Directory -Path (Join-Path $testPath "felix\scripts") -Force | Out-Null
        
        try {
            # Create a mock helper script that writes to a file
            $helperScript = Join-Path $testPath "felix\scripts\set-workflow-stage.ps1"
            $outputFile = Join-Path $testPath "output.txt"
            
            @"
param([string]`$Stage, [string]`$ProjectPath, [switch]`$Clear)
"Stage: `$Stage" | Out-File "$outputFile" -Encoding UTF8
"@ | Set-Content $helperScript
            
            Set-WorkflowStage -Stage "execute_llm" -ProjectPath $testPath
            
            # Verify helper was called with correct stage
            Assert-True (Test-Path $outputFile) "Output file should exist"
            $content = Get-Content $outputFile -Raw
            Assert-True ($content -match "Stage: execute_llm") "Stage parameter should be passed"
        }
        finally {
            Remove-Item $testPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    It "should call helper script with Clear switch" {
        $testPath = Join-Path $env:TEMP "test-workflow-$(Get-Random)"
        New-Item -ItemType Directory -Path (Join-Path $testPath "felix\scripts") -Force | Out-Null
        
        try {
            # Create a mock helper script
            $helperScript = Join-Path $testPath "felix\scripts\set-workflow-stage.ps1"
            $outputFile = Join-Path $testPath "output.txt"
            
            @"
param([string]`$Stage, [string]`$ProjectPath, [switch]`$Clear)
if (`$Clear) {
    "Clear: True" | Out-File "$outputFile" -Encoding UTF8
}
"@ | Set-Content $helperScript
            
            Set-WorkflowStage -Clear -ProjectPath $testPath
            
            # Verify helper was called with Clear switch
            Assert-True (Test-Path $outputFile) "Output file should exist"
            $content = Get-Content $outputFile -Raw
            Assert-True ($content -match "Clear: True") "Clear switch should be passed"
        }
        finally {
            Remove-Item $testPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    It "should silently handle errors from helper script" {
        $testPath = Join-Path $env:TEMP "test-workflow-$(Get-Random)"
        New-Item -ItemType Directory -Path (Join-Path $testPath "felix\scripts") -Force | Out-Null
        
        try {
            # Create a helper script that throws an error
            $helperScript = Join-Path $testPath "felix\scripts\set-workflow-stage.ps1"
            @"
throw "Intentional error for testing"
"@ | Set-Content $helperScript
            
            # Should not throw - errors are silently ignored
            Set-WorkflowStage -Stage "test_stage" -ProjectPath $testPath
            Assert-True $true "Function completed without throwing error"
        }
        finally {
            Remove-Item $testPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults
