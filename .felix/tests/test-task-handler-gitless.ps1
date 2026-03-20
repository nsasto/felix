. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/git-manager.ps1"

function Set-WorkflowStage {
    param([string]$Stage, [string]$ProjectPath)
}

function Format-PlainText {
    param([string]$Text)
    return $Text
}

function Invoke-GitCommit {
    param([string]$Message)
    throw "Invoke-GitCommit should not be called for non-git projects"
}

. "$PSScriptRoot/../core/task-handler.ps1"

Describe "Save-TaskChanges without git repository" {

    It "should skip git diff and commit work outside a git repository" {
        $projectPath = Join-Path $env:TEMP "felix-task-handler-non-git-$(Get-Random)"
        $runDir = Join-Path $projectPath "runs\test"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null
        Set-Content (Join-Path $projectPath "file.txt") "content" -Encoding UTF8

        try {
            $config = [pscustomobject]@{
                executor = [pscustomobject]@{
                    commit_on_complete = $true
                }
            }
            $requirement = [pscustomobject]@{
                commit_on_complete = $true
            }

            Save-TaskChanges `
                -ProjectPath $projectPath `
                -TaskDesc "Completed local task" `
                -BeforeCommitHash "" `
                -Config $config `
                -CurrentRequirement $requirement `
                -RunDir $runDir

            Assert-False (Test-Path (Join-Path $runDir "diff.patch")) "diff.patch should not be created for non-git projects"
        }
        finally {
            Remove-Item $projectPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults