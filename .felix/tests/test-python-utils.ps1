. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/python-utils.ps1"

Describe "Resolve-PythonCommand" {
    It "should find py launcher if available" {
        $pyCmd = Get-Command py -ErrorAction SilentlyContinue
        if ($pyCmd) {
            $result = Resolve-PythonCommand
            
            Assert-NotNull $result "Should return a result"
            Assert-NotNull $result.cmd "Should have cmd property"
            Assert-NotNull $result.args "Should have args property"
            Assert-True ($result.cmd -like "*py.exe*" -or $result.cmd -like "*python*.exe*") "Should find Python executable"
        }
        else {
            # Skip test if py not available
            Assert-True $true "Skipping test - py launcher not installed"
        }
    }
    
    It "should use configured Python executable when provided" {
        # Create mock config with explicit Python path
        $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
        if (-not $pythonPath) {
            $pythonPath = (Get-Command py -ErrorAction SilentlyContinue).Source
        }
        
        if ($pythonPath) {
            $config = [PSCustomObject]@{
                python = [PSCustomObject]@{
                    executable = $pythonPath
                    args       = @("--version")
                }
            }
            
            $result = Resolve-PythonCommand -Config $config
            
            Assert-NotNull $result "Should return a result"
            Assert-True ($result.cmd -eq $pythonPath) "Should use configured executable"
            Assert-Equal 1 $result.args.Count "Should have args from config"
        }
        else {
            Assert-True $true "Skipping test - no Python available"
        }
    }
    
    It "should throw when Python not found and no config" {
        # Mock scenario where no Python is available
        # We can't really test this without removing Python from the system
        # So we test with invalid config instead
        
        $config = [PSCustomObject]@{
            python = [PSCustomObject]@{
                executable = "nonexistent-python.exe"
            }
        }
        
        $threw = $false
        try {
            Resolve-PythonCommand -Config $config
        }
        catch {
            $threw = $true
        }
        
        Assert-True $threw "Should throw when Python executable not found"
    }
    
    It "should return py with -3 arg when no config provided" {
        $pyCmd = Get-Command py -ErrorAction SilentlyContinue
        if ($pyCmd) {
            $result = Resolve-PythonCommand
            
            # Should prefer py launcher and include -3 arg
            if ($result.cmd -like "*py.exe*") {
                Assert-Contains $result.args "-3" "Should include -3 arg for py launcher"
            }
        }
        else {
            Assert-True $true "Skipping test - py launcher not available"
        }
    }
}

Get-TestResults

