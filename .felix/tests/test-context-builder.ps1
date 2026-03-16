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

Get-TestResults
