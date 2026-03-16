<#
.SYNOPSIS
Tests for work-selector.ps1 - Get-NextRequirementLocal
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/work-selector.ps1"

Describe "Get-NextRequirementLocal" {

    It "should return in_progress item" {
        $tempFile = Join-Path $env:TEMP "test-req-$(Get-Random).json"
        try {
            @{ requirements = @(
                @{ id = "S-0001"; status = "planned"; title = "First" }
                @{ id = "S-0002"; status = "in_progress"; title = "Second" }
            ) } | ConvertTo-Json -Depth 5 | Set-Content $tempFile -Encoding UTF8

            $result = Get-NextRequirementLocal -RequirementsFilePath $tempFile
            Assert-Equal "S-0002" $result.id
        }
        finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    It "should return planned when no in_progress" {
        $tempFile = Join-Path $env:TEMP "test-req-$(Get-Random).json"
        try {
            @{ requirements = @(
                @{ id = "S-0003"; status = "planned"; title = "Third" }
                @{ id = "S-0001"; status = "planned"; title = "First" }
            ) } | ConvertTo-Json -Depth 5 | Set-Content $tempFile -Encoding UTF8

            $result = Get-NextRequirementLocal -RequirementsFilePath $tempFile
            Assert-Equal "S-0001" $result.id "Should return lowest sorted ID"
        }
        finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    It "should prioritize in_progress over planned" {
        $tempFile = Join-Path $env:TEMP "test-req-$(Get-Random).json"
        try {
            @{ requirements = @(
                @{ id = "S-0001"; status = "planned"; title = "Planned" }
                @{ id = "S-0005"; status = "in_progress"; title = "In Progress" }
            ) } | ConvertTo-Json -Depth 5 | Set-Content $tempFile -Encoding UTF8

            $result = Get-NextRequirementLocal -RequirementsFilePath $tempFile
            Assert-Equal "S-0005" $result.id "Should pick in_progress over lower-ID planned"
        }
        finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    It "should return null when all complete" {
        $tempFile = Join-Path $env:TEMP "test-req-$(Get-Random).json"
        try {
            @{ requirements = @(
                @{ id = "S-0001"; status = "complete"; title = "Done" }
                @{ id = "S-0002"; status = "complete"; title = "Also Done" }
            ) } | ConvertTo-Json -Depth 5 | Set-Content $tempFile -Encoding UTF8

            $result = Get-NextRequirementLocal -RequirementsFilePath $tempFile
            Assert-Null $result
        }
        finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    It "should return null when empty requirements" {
        $tempFile = Join-Path $env:TEMP "test-req-$(Get-Random).json"
        try {
            @{ requirements = @() } | ConvertTo-Json -Depth 5 | Set-Content $tempFile -Encoding UTF8

            $result = Get-NextRequirementLocal -RequirementsFilePath $tempFile
            Assert-Null $result
        }
        finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    It "should return null when file not found" {
        $result = Get-NextRequirementLocal -RequirementsFilePath "C:\nonexistent\requirements.json"
        Assert-Null $result
    }

    It "should handle legacy bare array format" {
        $tempFile = Join-Path $env:TEMP "test-req-$(Get-Random).json"
        try {
            # Legacy format: bare JSON array (not wrapped in { requirements: [] })
            # Must manually write JSON to avoid PS wrapping
            '[{"id": "S-0001", "status": "planned", "title": "Legacy"}]' | Set-Content $tempFile -Encoding UTF8

            $result = Get-NextRequirementLocal -RequirementsFilePath $tempFile
            Assert-Equal "S-0001" $result.id
        }
        finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults
