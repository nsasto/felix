. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../commands/spec-fix.ps1"

Describe "Get-SpecTitle" {

    It "should extract title from a plain H1" {
        $specPath = Join-Path $env:TEMP "felix-spec-fix-title-$(Get-Random).md"
        try {
            Set-Content -Path $specPath -Value @(
                "# Add API Health Endpoint",
                "",
                "Details"
            ) -Encoding UTF8

            $title = Get-SpecTitle -SpecPath $specPath -RequirementId "S-0001"
            Assert-Equal "Add API Health Endpoint" $title
        }
        finally {
            Remove-Item $specPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "should strip requirement id prefix from the H1" {
        $specPath = Join-Path $env:TEMP "felix-spec-fix-title-$(Get-Random).md"
        try {
            Set-Content -Path $specPath -Value @(
                "# S-0001: Add API Health Endpoint",
                "",
                "Details"
            ) -Encoding UTF8

            $title = Get-SpecTitle -SpecPath $specPath -RequirementId "S-0001"
            Assert-Equal "Add API Health Endpoint" $title
        }
        finally {
            Remove-Item $specPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "should fall back to the existing title when no H1 is present" {
        $specPath = Join-Path $env:TEMP "felix-spec-fix-title-$(Get-Random).md"
        try {
            Set-Content -Path $specPath -Value @(
                "No header here",
                "",
                "Details"
            ) -Encoding UTF8

            $title = Get-SpecTitle -SpecPath $specPath -RequirementId "S-0001" -ExistingTitle "Keep Existing Title"
            Assert-Equal "Keep Existing Title" $title
        }
        finally {
            Remove-Item $specPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Invoke-SpecFix" {

    It "should keep requirements as an array when only one spec exists" {
        $repoPath = Join-Path $env:TEMP "felix-spec-fix-single-$(Get-Random)"
        $originalRepoRoot = $script:RepoRoot

        try {
            $felixDir = Join-Path $repoPath ".felix"
            $specsDir = Join-Path $repoPath "specs"
            New-Item -ItemType Directory -Path $felixDir -Force | Out-Null
            New-Item -ItemType Directory -Path $specsDir -Force | Out-Null

            Set-Content -Path (Join-Path $specsDir "S-0000-test-dummy.md") -Value @(
                "# Test Dummy Spec",
                "",
                "Single requirement repo"
            ) -Encoding UTF8

            $initialRequirements = @{
                requirements = @(
                    @{
                        id        = "S-0000"
                        spec_path = "specs/S-0000-test-dummy.md"
                        status    = "complete"
                        title     = "Existing Title"
                    }
                )
            } | ConvertTo-Json -Depth 10
            Set-Content -Path (Join-Path $felixDir "requirements.json") -Value $initialRequirements -Encoding UTF8

            $script:RepoRoot = $repoPath
            Invoke-SpecFix

            $saved = Get-Content -Path (Join-Path $felixDir "requirements.json") -Raw | ConvertFrom-Json
            Assert-True ($saved.requirements -is [System.Array]) "requirements should remain an array for single-spec repos"
            Assert-Equal 1 $saved.requirements.Count
            Assert-Equal "S-0000" $saved.requirements[0].id
            Assert-Equal "Test Dummy Spec" $saved.requirements[0].title
        }
        finally {
            $script:RepoRoot = $originalRepoRoot
            Remove-Item -Path $repoPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults