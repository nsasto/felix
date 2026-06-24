. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/agent-setup.ps1"

Describe "Get-ModelsForProvider" {

    It "should include current recommended Codex models" {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $models = @(Get-ModelsForProvider -Provider "codex" -FelixRoot (Join-Path $repoRoot ".felix"))

        Assert-Equal "gpt-5.5" $models[0] "Expected first Codex model to be gpt-5.5"
        Assert-Contains $models "gpt-5.4-mini" "Expected codex model catalog to include gpt-5.4-mini"
        Assert-Contains $models "gpt-5.3-codex-spark" "Expected codex model catalog to include gpt-5.3-codex-spark"
    }

    It "should include current Factory Droid models" {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $models = @(Get-ModelsForProvider -Provider "droid" -FelixRoot (Join-Path $repoRoot ".felix"))

        Assert-Equal "claude-opus-4-6" $models[0] "Expected first Factory Droid model to match the Droid CLI default"
        Assert-Contains $models "gpt-5.4-fast" "Expected droid model catalog to include gpt-5.4-fast"
        Assert-Contains $models "gpt-5.4-mini" "Expected droid model catalog to include gpt-5.4-mini"
        Assert-Contains $models "minimax-m2.7" "Expected droid model catalog to include minimax-m2.7"
    }

    It "should include current Claude Code aliases and pinned models" {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $models = @(Get-ModelsForProvider -Provider "claude" -FelixRoot (Join-Path $repoRoot ".felix"))

        Assert-Contains $models "fable" "Expected claude model catalog to include the fable alias"
        Assert-Contains $models "haiku" "Expected claude model catalog to include the haiku alias"
        Assert-Contains $models "claude-fable-5" "Expected claude model catalog to include claude-fable-5"
        Assert-Contains $models "claude-opus-4-8" "Expected claude model catalog to include claude-opus-4-8"
        Assert-Contains $models "claude-sonnet-4-6" "Expected claude model catalog to include claude-sonnet-4-6"
    }

    It "should include curated Claude and Gemini options for copilot" {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $models = @(Get-ModelsForProvider -Provider "copilot" -FelixRoot (Join-Path $repoRoot ".felix"))

        Assert-Contains $models "claude-opus-4.6" "Expected copilot model catalog to include claude-opus-4.6"
        Assert-Contains $models "claude-sonnet-4.6" "Expected copilot model catalog to include claude-sonnet-4.6"
        Assert-Contains $models "gemini-3-pro" "Expected copilot model catalog to include gemini-3-pro"
    }

    It "should put gpt-5.4 first for copilot" {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
        $models = @(Get-ModelsForProvider -Provider "copilot" -FelixRoot (Join-Path $repoRoot ".felix"))

        Assert-Equal "gpt-5.4" $models[0] "Expected first curated copilot model to be gpt-5.4"
    }
}

Get-TestResults
