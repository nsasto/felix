<#
.SYNOPSIS
Tests for context-builder.ps1 - Get-ProjectStructure
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/context-builder.ps1"

Describe "Get-ProjectStructure" {

    It "should count files and directories" {
        $tempDir = Join-Path $env:TEMP "test-projstruct-$(Get-Random)"
        New-Item -ItemType Directory -Path (Join-Path $tempDir "src") -Force | Out-Null
        Set-Content (Join-Path $tempDir "file1.txt") "hello" -Encoding UTF8
        Set-Content (Join-Path $tempDir "src\file2.ps1") "code" -Encoding UTF8

        try {
            $result = Get-ProjectStructure -ProjectPath $tempDir
            Assert-True ($result.Tree.Files.Count -ge 2) "Should have at least 2 files"
            Assert-True ($result.Tree.Directories.Count -ge 1) "Should have at least 1 directory"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should exclude node_modules" {
        $tempDir = Join-Path $env:TEMP "test-projstruct-$(Get-Random)"
        New-Item -ItemType Directory -Path (Join-Path $tempDir "node_modules\pkg") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempDir "src") -Force | Out-Null
        Set-Content (Join-Path $tempDir "src\app.js") "code" -Encoding UTF8
        Set-Content (Join-Path $tempDir "node_modules\pkg\index.js") "module" -Encoding UTF8

        try {
            $result = Get-ProjectStructure -ProjectPath $tempDir
            $nmFiles = $result.Tree.Files | Where-Object { $_ -match "node_modules" }
            Assert-Equal 0 @($nmFiles).Count "node_modules files should be excluded"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should exclude hidden directories by default" {
        $tempDir = Join-Path $env:TEMP "test-projstruct-$(Get-Random)"
        New-Item -ItemType Directory -Path (Join-Path $tempDir ".hidden") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tempDir "visible") -Force | Out-Null
        Set-Content (Join-Path $tempDir ".hidden\secret.txt") "hidden" -Encoding UTF8
        Set-Content (Join-Path $tempDir "visible\public.txt") "visible" -Encoding UTF8

        try {
            $result = Get-ProjectStructure -ProjectPath $tempDir -ExcludeHidden $true
            $hiddenFiles = $result.Tree.Files | Where-Object { $_ -match "\.hidden" }
            Assert-Equal 0 @($hiddenFiles).Count "Hidden dir files should be excluded"
            $visibleFiles = $result.Tree.Files | Where-Object { $_ -match "public.txt" }
            Assert-True (@($visibleFiles).Count -gt 0) "Visible files should be included"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should count file extensions" {
        $tempDir = Join-Path $env:TEMP "test-projstruct-$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        Set-Content (Join-Path $tempDir "a.ps1") "1" -Encoding UTF8
        Set-Content (Join-Path $tempDir "b.ps1") "2" -Encoding UTF8
        Set-Content (Join-Path $tempDir "c.md") "3" -Encoding UTF8

        try {
            $result = Get-ProjectStructure -ProjectPath $tempDir
            Assert-Equal 2 $result.Tree.Extensions[".ps1"]
            Assert-Equal 1 $result.Tree.Extensions[".md"]
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should generate summary with file count" {
        $tempDir = Join-Path $env:TEMP "test-projstruct-$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        Set-Content (Join-Path $tempDir "file.txt") "content" -Encoding UTF8

        try {
            $result = Get-ProjectStructure -ProjectPath $tempDir
            Assert-True ($result.Summary -match "Total Files:") "Summary should contain Total Files"
            Assert-True ($result.Summary -match "Total Directories:") "Summary should contain Total Directories"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should handle empty directory" {
        $tempDir = Join-Path $env:TEMP "test-projstruct-$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        try {
            $result = Get-ProjectStructure -ProjectPath $tempDir
            Assert-Equal 0 $result.Tree.Files.Count
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Invoke-ContextBuilder" {

    It "should support learnings README path generation on Windows PowerShell" {
        $tempDir = Join-Path $env:TEMP "test-contextbuilder-$(Get-Random)"
        $promptsDir = Join-Path $tempDir "prompts"
        $learningsDir = Join-Path $tempDir "learnings"
        $agentsPath = Join-Path $tempDir "AGENTS.md"
        $readmePath = Join-Path $tempDir "README.md"

        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        New-Item -ItemType Directory -Path $promptsDir -Force | Out-Null
        New-Item -ItemType Directory -Path $learningsDir -Force | Out-Null
        Set-Content (Join-Path $promptsDir "build_context.md") "Build context" -Encoding UTF8
        Set-Content $readmePath "# Repo" -Encoding UTF8
        Set-Content $agentsPath "# Agents" -Encoding UTF8
        Set-Content (Join-Path $learningsDir "README.md") "# Learnings" -Encoding UTF8

        function Emit-Log {
            param([string]$Level, [string]$Message, [string]$Component)
        }

        function Emit-Error {
            param([string]$ErrorType, [string]$Message, [string]$Severity)
            throw $Message
        }

        function Invoke-AgentForContextBuild {
            param([string]$Prompt, $Config, $AgentConfig, $Paths)
            Set-Content (Join-Path $Paths.ProjectPath "CONTEXT.md") "# Generated Context" -Encoding UTF8
            return "generated"
        }

        try {
            $result = Invoke-ContextBuilder `
                -ProjectPath $tempDir `
                -Config ([pscustomobject]@{ agent = [pscustomobject]@{ agent_id = 0 } }) `
                -AgentConfig ([pscustomobject]@{}) `
                -Paths ([pscustomobject]@{
                    ProjectPath = $tempDir
                    FelixDir    = Join-Path $tempDir ".felix"
                    SpecsDir    = Join-Path $tempDir "specs"
                    PromptsDir  = $promptsDir
                    AgentsFile  = $agentsPath
                })

            Assert-Equal 0 $result.ExitCode
            Assert-True (Test-Path (Join-Path $tempDir "CONTEXT.md")) "CONTEXT.md should be generated"
        }
        finally {
            Remove-Item Function:\Emit-Log -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-Error -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-AgentForContextBuild -ErrorAction SilentlyContinue
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Invoke-ContextBuilder verbose propagation" {

    It "should pass verbose mode to Invoke-AgentForContextBuild" {
        $tempDir = Join-Path $env:TEMP "test-contextverbose-$(Get-Random)"
        $promptsDir = Join-Path $tempDir "prompts"
        $global:ObservedContextVerbose = $null

        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        New-Item -ItemType Directory -Path $promptsDir -Force | Out-Null
        Set-Content (Join-Path $promptsDir "build_context.md") "Build context" -Encoding UTF8
        Set-Content (Join-Path $tempDir "README.md") "# Repo" -Encoding UTF8
        Set-Content (Join-Path $tempDir "AGENTS.md") "# Agents" -Encoding UTF8

        function Emit-Log {
            param([string]$Level, [string]$Message, [string]$Component)
        }

        function Emit-Error {
            param([string]$ErrorType, [string]$Message, [string]$Severity)
            throw $Message
        }

        function Invoke-AgentForContextBuild {
            param([string]$Prompt, $Config, $AgentConfig, $Paths, [bool]$VerboseMode)
            $global:ObservedContextVerbose = $VerboseMode
            Set-Content (Join-Path $Paths.ProjectPath "CONTEXT.md") "# Generated Context" -Encoding UTF8
            return "generated"
        }

        try {
            $result = Invoke-ContextBuilder `
                -ProjectPath $tempDir `
                -VerboseMode:$true `
                -Config ([pscustomobject]@{ agent = [pscustomobject]@{ agent_id = "ag_test" } }) `
                -AgentConfig ([pscustomobject]@{ key = "ag_test"; name = "droid"; executable = "droid" }) `
                -Paths ([pscustomobject]@{
                    ProjectPath = $tempDir
                    FelixDir    = Join-Path $tempDir ".felix"
                    SpecsDir    = Join-Path $tempDir "specs"
                    PromptsDir  = $promptsDir
                    AgentsFile  = Join-Path $tempDir "AGENTS.md"
                })

            Assert-Equal 0 $result.ExitCode
            Assert-Equal $true $global:ObservedContextVerbose "Expected verbose mode to be forwarded to Invoke-AgentForContextBuild"
        }
        finally {
            Remove-Item Function:\Emit-Log -ErrorAction SilentlyContinue
            Remove-Item Function:\Emit-Error -ErrorAction SilentlyContinue
            Remove-Item Function:\Invoke-AgentForContextBuild -ErrorAction SilentlyContinue
            Remove-Item Variable:\global:ObservedContextVerbose -ErrorAction SilentlyContinue
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults
