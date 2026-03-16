<#
.SYNOPSIS
Tests for spec-builder.ps1 - Parse-SpecBuilderResponse and Get-SpecBuilderContext
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/emit-event.ps1"
. "$PSScriptRoot/../core/spec-builder.ps1"

Describe "Parse-SpecBuilderResponse" {

    It "should parse filename tag" {
        $events = Parse-SpecBuilderResponse '<filename>my-feature-slug</filename>'
        $filenameEvent = $events | Where-Object { $_.type -eq "filename" }
        Assert-NotNull $filenameEvent
        Assert-Equal "my-feature-slug" $filenameEvent.content
    }

    It "should parse question tag" {
        $events = Parse-SpecBuilderResponse '<question>What framework are you using?</question>'
        $questionEvent = $events | Where-Object { $_.type -eq "question" }
        Assert-NotNull $questionEvent
        Assert-Equal "What framework are you using?" $questionEvent.content
    }

    It "should parse spec tag as complete" {
        $events = Parse-SpecBuilderResponse '<spec># S-0001: My Feature

## Description
A great feature</spec>'
        $completeEvent = $events | Where-Object { $_.type -eq "complete" }
        Assert-NotNull $completeEvent
        Assert-True ($completeEvent.content -match "S-0001")
    }

    It "should parse draft tag" {
        $events = Parse-SpecBuilderResponse '<draft>## Draft Spec Content</draft>'
        $draftEvent = $events | Where-Object { $_.type -eq "draft" }
        Assert-NotNull $draftEvent
        Assert-True ($draftEvent.content -match "Draft Spec")
    }

    It "should parse multiple tags in one response" {
        $response = '<filename>my-slug</filename>
Some text here
<spec># S-0001: Title</spec>'
        $events = Parse-SpecBuilderResponse $response
        $filenameEvent = $events | Where-Object { $_.type -eq "filename" }
        $specEvent = $events | Where-Object { $_.type -eq "complete" }
        Assert-NotNull $filenameEvent
        Assert-NotNull $specEvent
    }

    It "should treat plain text as question" {
        $events = @(Parse-SpecBuilderResponse "Just a regular response with no tags")
        Assert-Equal 1 $events.Count
        Assert-Equal "question" $events[0].type
        Assert-True ($events[0].content -match "regular response")
    }

    It "should handle multiline content in tags" {
        $response = @"
<spec>
# S-0001: Multi-line

## Description
Line 1
Line 2
Line 3
</spec>
"@
        $events = Parse-SpecBuilderResponse $response
        $specEvent = $events | Where-Object { $_.type -eq "complete" }
        Assert-NotNull $specEvent
        Assert-True ($specEvent.content -match "Line 1")
        Assert-True ($specEvent.content -match "Line 3")
    }
}

Describe "Get-SpecBuilderContext" {

    It "should include README when present" {
        $tempDir = Join-Path $env:TEMP "test-specctx-$(Get-Random)"
        $specsDir = Join-Path $tempDir ".felix\specs"
        New-Item -ItemType Directory -Path $specsDir -Force | Out-Null
        Set-Content (Join-Path $tempDir "README.md") "# My Project" -Encoding UTF8

        try {
            $context = Get-SpecBuilderContext -ProjectPath $tempDir -SpecsDir $specsDir
            Assert-True ($context -match "README.md")
            Assert-True ($context -match "My Project")
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should include AGENTS.md when present" {
        $tempDir = Join-Path $env:TEMP "test-specctx-$(Get-Random)"
        $specsDir = Join-Path $tempDir ".felix\specs"
        New-Item -ItemType Directory -Path $specsDir -Force | Out-Null
        Set-Content (Join-Path $tempDir "AGENTS.md") "# How to Run" -Encoding UTF8

        try {
            $context = Get-SpecBuilderContext -ProjectPath $tempDir -SpecsDir $specsDir
            Assert-True ($context -match "AGENTS.md")
            Assert-True ($context -match "How to Run")
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should show no-specs message when no specs exist" {
        $tempDir = Join-Path $env:TEMP "test-specctx-$(Get-Random)"
        $specsDir = Join-Path $tempDir ".felix\specs"
        New-Item -ItemType Directory -Path $specsDir -Force | Out-Null

        try {
            $context = Get-SpecBuilderContext -ProjectPath $tempDir -SpecsDir $specsDir
            Assert-True ($context -match "No existing specs")
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "should include example specs when available" {
        $tempDir = Join-Path $env:TEMP "test-specctx-$(Get-Random)"
        $specsDir = Join-Path $tempDir ".felix\specs"
        New-Item -ItemType Directory -Path $specsDir -Force | Out-Null
        Set-Content (Join-Path $specsDir "S-0001-example.md") "# S-0001: Example Spec" -Encoding UTF8

        try {
            $context = Get-SpecBuilderContext -ProjectPath $tempDir -SpecsDir $specsDir
            Assert-True ($context -match "S-0001-example.md")
        }
        finally {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Get-TestResults
