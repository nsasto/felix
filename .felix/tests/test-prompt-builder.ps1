. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/prompt-builder.ps1"

function Set-WorkflowStage { param([string]$Stage, [string]$ProjectPath) }
function Emit-Error { param([string]$ErrorType, [string]$Message, [string]$Severity) throw $Message }
function Invoke-PluginHookSafely { param($HookName, $RunId, $HookData) return @{} }

Describe "New-IterationPrompt exact file references" {

    It "should inject exact required and optional file paths for planning" {
        $tempDir = Join-Path $env:TEMP "test-prompt-builder-$(Get-Random)"
        $felixDir = Join-Path $tempDir ".felix"
        $promptsDir = Join-Path $felixDir "prompts"
        $requirementsDir = Join-Path $tempDir "requirements"
        $runsDir = Join-Path $tempDir "work\runs"
        $planPath = Join-Path $tempDir "work\runs\run-1\plan-SPRINT-0003.md"
        $agentsPath = Join-Path $tempDir "docs\OPERATIONS.md"
        $context1 = Join-Path $tempDir "docs\ARCHITECTURE.md"

        New-Item -ItemType Directory -Path $felixDir, $promptsDir, $requirementsDir, $runsDir, (Split-Path $agentsPath -Parent) -Force | Out-Null
        Set-Content (Join-Path $promptsDir "planning.md") "# planning" -Encoding UTF8
        Set-Content $agentsPath "# Ops" -Encoding UTF8
        Set-Content $context1 "# Architecture" -Encoding UTF8
        Set-Content (Join-Path $requirementsDir "SPRINT-0003-sample.md") "# SPRINT-0003: Sample" -Encoding UTF8
        '{"requirements":[{"id":"SPRINT-0003","title":"Sample","status":"planned","spec_path":"requirements/SPRINT-0003-sample.md"}]}' | Set-Content (Join-Path $felixDir "requirements.json") -Encoding UTF8

        try {
            $prompt = New-IterationPrompt `
                -Mode "planning" `
                -CurrentRequirement ([pscustomobject]@{ id = "SPRINT-0003"; title = "Sample"; status = "planned"; spec_path = "requirements/SPRINT-0003-sample.md" }) `
                -State @{} `
                -Config ([pscustomobject]@{ executor = [pscustomobject]@{ commit_on_complete = $false } }) `
                -Paths @{
                    ProjectPath = $tempDir
                    RequirementsFile = (Join-Path $felixDir "requirements.json")
                    PromptsDir = $promptsDir
                    AgentsFile = $agentsPath
                    AgentsRelativePath = "docs/OPERATIONS.md"
                    ContextRelativePaths = @("docs/ARCHITECTURE.md", "docs/DOMAIN.md")
                    SpecsRelativePath = "requirements"
                    RunsRelativePath = "work/runs"
                } `
                -RunId "run-1" `
                -RunDir (Join-Path $runsDir "run-1")

            Assert-True ($prompt -match "Read These Exact Files First") "Prompt should include explicit file-reading block"
            Assert-True ($prompt -match [regex]::Escape("docs/OPERATIONS.md")) "Prompt should include configured agents path"
            Assert-True ($prompt -match [regex]::Escape("requirements/SPRINT-0003-sample.md")) "Prompt should include exact spec path"
            Assert-True ($prompt -match [regex]::Escape("docs/ARCHITECTURE.md")) "Prompt should include existing optional context path"
            Assert-True ($prompt -match "3\.\s+\*\*docs/ARCHITECTURE\.md\*\*") "Prompt should list existing context as required input"
            Assert-True ($prompt -match "Missing Required Context Files") "Prompt should call out missing required context"
            Assert-True ($prompt -match [regex]::Escape($planPath)) "Prompt should include exact plan output path"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should inject exact plan path for building mode" {
        $tempDir = Join-Path $env:TEMP "test-prompt-builder-$(Get-Random)"
        $felixDir = Join-Path $tempDir ".felix"
        $promptsDir = Join-Path $felixDir "prompts"
        $planPath = Join-Path $tempDir "work\runs\run-2\plan-SPRINT-0004.md"
        New-Item -ItemType Directory -Path $felixDir, $promptsDir -Force | Out-Null
        Set-Content (Join-Path $promptsDir "building.md") "# building" -Encoding UTF8
        '{"requirements":[]}' | Set-Content (Join-Path $felixDir "requirements.json") -Encoding UTF8

        try {
            $prompt = New-IterationPrompt `
                -Mode "building" `
                -CurrentRequirement ([pscustomobject]@{ id = "SPRINT-0004"; title = "Build"; status = "in_progress"; spec_path = "requirements/SPRINT-0004-build.md" }) `
                -State @{} `
                -Config ([pscustomobject]@{ executor = [pscustomobject]@{ commit_on_complete = $false } }) `
                -Paths @{
                    ProjectPath = $tempDir
                    RequirementsFile = (Join-Path $felixDir "requirements.json")
                    PromptsDir = $promptsDir
                    AgentsFile = (Join-Path $tempDir "docs\OPERATIONS.md")
                    AgentsRelativePath = "docs/OPERATIONS.md"
                    ContextRelativePaths = @("docs/ARCHITECTURE.md")
                    SpecsRelativePath = "requirements"
                    RunsRelativePath = "work/runs"
                } `
                -RunId "run-2" `
                -RunDir (Join-Path $tempDir "work\runs\run-2") `
                -PlanContent "# Plan`n- [ ] Task"

            Assert-True ($prompt -match [regex]::Escape($planPath)) "Building prompt should include exact plan update path"
            Assert-True ($prompt -match [regex]::Escape("requirements/SPRINT-0004-build.md")) "Building prompt should include exact spec path"
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults
