<#
.SYNOPSIS
felix memory  -  manage the .felix/memory/ durable memory tree (Phase E5).

.DESCRIPTION
Exposes Invoke-Memory for felix.ps1 dispatch.
Subcommands (parsed from $Args array):
  view [--scope global|repo|requirement] [--req <id>]
  add  --scope <scope> --title "<t>" --body "<b>" [--req <id>]
  edit <file>
  prune [--older-than <days>] [--dry-run]

Files in .felix/memory/ are NEVER auto-deleted.
Only runs/*/agents-md-suggestions.md is pruned.
#>

function Invoke-Memory {
    param(
        [string[]]$CmdArgs = @(),
        [string]$ProjectPath = (Get-Location).Path
    )

    $felixDir = Join-Path $ProjectPath ".felix"
    $memDir   = Join-Path $felixDir "memory"
    $runsDir  = Join-Path $ProjectPath "runs"

    # Parse subcommand and flags from args array
    $subCmd = if ($CmdArgs.Count -gt 0) { $CmdArgs[0] } else { "" }
    $rest   = if ($CmdArgs.Count -gt 1) { $CmdArgs[1..($CmdArgs.Count - 1)] } else { @() }

    # Helper: parse a flag value (--flag value) from an array
    function Get-ArgValue {
        param([string[]]$Arr, [string]$Flag)
        for ($k = 0; $k -lt $Arr.Count - 1; $k++) {
            if ($Arr[$k] -ieq $Flag) { return $Arr[$k + 1] }
        }
        return $null
    }

    # Helper: check if flag present
    function Test-Flag {
        param([string[]]$Arr, [string]$Flag)
        return ($Arr -icontains $Flag)
    }

    switch ($subCmd.ToLower()) {

        "view" {
            $scope   = Get-ArgValue $rest "--scope"
            $req     = Get-ArgValue $rest "--req"
            $files   = [System.Collections.ArrayList]@()

            $loadDir = {
                param($Dir, $Label)
                if (Test-Path $Dir) {
                    Get-ChildItem -Path $Dir -Filter "*.md" -ErrorAction SilentlyContinue |
                        Sort-Object Name |
                        ForEach-Object {
                            $firstLines = Get-Content $_.FullName -TotalCount 5 -ErrorAction SilentlyContinue
                            $titleLine  = $firstLines | Where-Object { $_ -match "^title:" } | Select-Object -First 1
                            $displayTitle = if ($titleLine) { ($titleLine -replace "^title:\s*", "").Trim() } else { $_.Name }
                            [void]$files.Add([PSCustomObject]@{
                                Scope = $Label
                                File  = $_.FullName.Replace($ProjectPath + "\", "")
                                Title = $displayTitle
                            })
                        }
                }
            }

            $effectiveScope = if ($scope) { $scope } else { "all" }

            if ($effectiveScope -in @("global", "all")) {
                $globalDir = Join-Path $env:USERPROFILE ".felix\memory\global"
                & $loadDir $globalDir "global"
            }
            if ($effectiveScope -in @("repo", "all")) {
                & $loadDir (Join-Path $memDir "repo") "repo"
            }
            if ($effectiveScope -in @("requirement", "all")) {
                if ($req) {
                    & $loadDir (Join-Path $memDir "requirement\$req") "requirement/$req"
                } else {
                    $reqBase = Join-Path $memDir "requirement"
                    if (Test-Path $reqBase) {
                        Get-ChildItem -Path $reqBase -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                            & $loadDir $_.FullName "requirement/$($_.Name)"
                        }
                    }
                }
            }

            if ($files.Count -eq 0) {
                Write-Host "No memory entries found." -ForegroundColor Yellow
                return
            }

            Write-Host ""
            Write-Host "Felix Memory ($($files.Count) entries)" -ForegroundColor Cyan
            Write-Host ""
            foreach ($f in $files) {
                Write-Host "  [$($f.Scope)]  $($f.Title)" -ForegroundColor White
                Write-Host "    $($f.File)" -ForegroundColor Gray
            }
            Write-Host ""
        }

        "add" {
            $addScope = Get-ArgValue $rest "--scope"
            $addTitle = Get-ArgValue $rest "--title"
            $addBody  = Get-ArgValue $rest "--body"
            $addReq   = Get-ArgValue $rest "--req"

            if (-not $addScope) { Write-Host "Error: --scope required (global, repo, requirement)" -ForegroundColor Red; return }
            if (-not $addTitle) { Write-Host "Error: --title required" -ForegroundColor Red; return }
            if (-not $addBody)  { $addBody = "" }

            $targetDir = switch ($addScope) {
                "global"      { Join-Path $env:USERPROFILE ".felix\memory\global" }
                "repo"        { Join-Path $memDir "repo" }
                "requirement" {
                    if (-not $addReq) {
                        Write-Host "Error: --req required for scope=requirement" -ForegroundColor Red
                        return
                    }
                    Join-Path $memDir "requirement\$addReq"
                }
                default { Write-Host "Error: unknown scope '$addScope'" -ForegroundColor Red; return }
            }

            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            $slug = ($addTitle -replace '[^a-zA-Z0-9\s-]', '' -replace '\s+', '-').ToLower().Trim('-')
            if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40).TrimEnd('-') }
            $date     = (Get-Date).ToString("yyyy-MM-dd")
            $filename = "$date-$slug.md"
            $filePath = Join-Path $targetDir $filename
            $scopeFM  = if ($addScope -eq "requirement") { "requirement" } else { $addScope }

            $content = "---`ntitle: $addTitle`nscope: $scopeFM`ncreated: $date`ntags: []`n---`n`n$addBody`n"
            [System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
            Write-Host "Created: $filePath" -ForegroundColor Green
        }

        "edit" {
            $editFile = if ($rest.Count -gt 0) { $rest[0] } else { "" }
            if (-not $editFile) { Write-Host "Error: file path required" -ForegroundColor Red; return }

            $resolvedPath = if ([System.IO.Path]::IsPathRooted($editFile)) { $editFile } else {
                Join-Path $ProjectPath $editFile
            }
            if (-not (Test-Path $resolvedPath)) {
                Write-Host "Error: file not found: $resolvedPath" -ForegroundColor Red; return
            }

            $editor = if ($env:EDITOR) { $env:EDITOR } else { "notepad" }
            & $editor $resolvedPath
        }

        "prune" {
            $olderStr = Get-ArgValue $rest "--older-than"
            $dryRun   = Test-Flag $rest "--dry-run"
            $days     = if ($olderStr) { [int]$olderStr } else { 30 }

            if (-not (Test-Path $runsDir)) {
                Write-Host "No runs/ directory found." -ForegroundColor Yellow
                return
            }

            $cutoff = (Get-Date).AddDays(-$days)
            $candidates = Get-ChildItem -Path $runsDir -Recurse -Filter "agents-md-suggestions.md" `
                -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff }

            if (-not $candidates -or @($candidates).Count -eq 0) {
                Write-Host "No proposal files older than $days days found." -ForegroundColor Yellow
                return
            }

            Write-Host "Found $(@($candidates).Count) proposal file(s) older than $days days:" -ForegroundColor Yellow
            foreach ($f in $candidates) {
                Write-Host "  $($f.FullName)" -ForegroundColor Gray
            }

            if ($dryRun) {
                Write-Host "[dry-run] Would delete $(@($candidates).Count) file(s)." -ForegroundColor Cyan
                return
            }

            $deleted = 0
            foreach ($f in $candidates) {
                try { Remove-Item $f.FullName -Force -ErrorAction Stop; $deleted++ }
                catch { Write-Host "  Failed to delete $($f.FullName): $_" -ForegroundColor Red }
            }
            Write-Host "Pruned $deleted file(s)." -ForegroundColor Green
        }

        default {
            Write-Host "felix memory - usage:" -ForegroundColor Cyan
            Write-Host "  felix memory view [--scope global|repo|requirement] [--req <id>]"
            Write-Host "  felix memory add --scope <scope> --title '<title>' --body '<body>' [--req <id>]"
            Write-Host "  felix memory edit <file>"
            Write-Host "  felix memory prune [--older-than <days>] [--dry-run]"
        }
    }
}
