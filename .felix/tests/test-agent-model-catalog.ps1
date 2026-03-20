. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/agent-setup.ps1"

Describe "Get-ModelsForProvider" {

    It "should include gpt-5.4-codex for codex" {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $models = @(Get-ModelsForProvider -Provider "codex" -FelixRoot (Join-Path $repoRoot ".felix"))

        Assert-Contains $models "gpt-5.4-codex" "Expected codex model catalog to include gpt-5.4-codex"
    }

    It "should include auto and gpt-5.4 for copilot" {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $models = @(Get-ModelsForProvider -Provider "copilot" -FelixRoot (Join-Path $repoRoot ".felix"))

        Assert-Contains $models "auto" "Expected copilot model catalog to include auto"
        Assert-Contains $models "gpt-5.4" "Expected copilot model catalog to include gpt-5.4"
    }

    It "should include curated Claude, Gemini, and Auto options for copilot" {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $models = @(Get-ModelsForProvider -Provider "copilot" -FelixRoot (Join-Path $repoRoot ".felix"))

        Assert-Contains $models "auto" "Expected copilot model catalog to include auto"
        Assert-Contains $models "claude-opus-4.6" "Expected copilot model catalog to include claude-opus-4.6"
        Assert-Contains $models "claude-sonnet-4.6" "Expected copilot model catalog to include claude-sonnet-4.6"
        Assert-Contains $models "gemini-3-pro" "Expected copilot model catalog to include gemini-3-pro"
    }

    It "should put auto first for copilot" {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $models = @(Get-ModelsForProvider -Provider "copilot" -FelixRoot (Join-Path $repoRoot ".felix"))

        Assert-Equal "auto" $models[0] "Expected copilot default model to be auto"
    }
}

Get-TestResults