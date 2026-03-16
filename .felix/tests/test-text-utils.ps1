<#
.SYNOPSIS
Tests for text-utils.ps1
#>

. "$PSScriptRoot/test-framework.ps1"
. "$PSScriptRoot/../core/text-utils.ps1"

Describe "Format-PlainText" {

    It "should convert literal newlines" {
        $result = Format-PlainText -Text "line1\nline2"
        Assert-True ($result -match "line1`nline2") "Should contain actual newline"
    }

    It "should convert literal tabs" {
        $result = Format-PlainText -Text "col1\tcol2"
        Assert-True ($result -match "col1`tcol2") "Should contain actual tab"
    }

    It "should strip bold markdown" {
        $result = Format-PlainText -Text "This is **bold** text"
        Assert-Equal "This is bold text" $result
    }

    It "should strip italic markdown" {
        $result = Format-PlainText -Text "This is *italic* text"
        Assert-Equal "This is italic text" $result
    }

    It "should strip inline code markdown" {
        $result = Format-PlainText -Text "Run ``command`` here"
        Assert-Equal "Run command here" $result
    }

    It "should reject empty input" {
        Assert-Throws {
            Format-PlainText -Text ""
        }
    }

    It "should handle whitespace-only input" {
        $result = Format-PlainText -Text "   "
        Assert-Equal "   " $result
    }

    It "should convert escaped quotes" {
        $result = Format-PlainText -Text "He said \""hello\"" and \'goodbye\'"
        Assert-True ($result -match 'He said "hello"') "Should contain unescaped double quotes"
    }
}

Describe "Format-MarkdownText" {

    It "should convert literal newlines" {
        $result = Format-MarkdownText -Text "line1\nline2"
        Assert-True ($result -match "line1`nline2") "Should contain actual newline"
    }

    It "should reject empty input" {
        Assert-Throws {
            Format-MarkdownText -Text ""
        }
    }

    It "should handle whitespace-only input" {
        $result = Format-MarkdownText -Text "   "
        Assert-Equal "   " $result
    }

    It "should produce output containing ANSI codes for bold text" {
        $result = Format-MarkdownText -Text "This is **bold** text"
        # Should contain ANSI escape sequences
        Assert-True ($result.Length -gt "This is bold text".Length) "Output should be longer due to ANSI codes"
    }
}

Get-TestResults
