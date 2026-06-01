<#
.SYNOPSIS
felix review  -  unified surface for inspecting learnings and prompt audits (Phase E2).

.DESCRIPTION
Subcommands exposed as Invoke-Review for felix.ps1 dispatch.
Modes (via args array):
  --learnings   Walk agents-md-suggestions.md proposals; accept/reject/defer
  --prompts     Audit prompts/skills for model-workaround heuristics
  --all         Both in sequence
  --acknowledge Stamp state.json#last_review (silences doctor staleness warning)
  --dry-run     Preview without writing or committing
#>

function Invoke-Review {
    param(
        [string[]]$CmdArgs = @(),
        [string]$ProjectPath = (Get-Location).Path
    )

    $learnings   = $CmdArgs -contains "--learnings"
    $prompts     = $CmdArgs -contains "--prompts"
    $all         = $CmdArgs -contains "--all"
    $acknowledge = $CmdArgs -contains "--acknowledge"
    $dryRun      = $CmdArgs -contains "--dry-run"

    $felixDir   = Join-Path $ProjectPath ".felix"
    $stateFile  = Join-Path $felixDir "state.json"
    $agentsFile = Join-Path $ProjectPath "AGENTS.md"
    $runsDir    = Join-Path $ProjectPath "runs"

    function Invoke-Acknowledge {
        $state = [ordered]@{}
        if (Test-Path $stateFile) {
            try {
                $raw    = Get-Content $stateFile -Raw -Encoding UTF8
                $parsed = $raw | ConvertFrom-Json
                foreach ($prop in $parsed.PSObject.Properties) {
                    $state[$prop.Name] = $prop.Value
                }
            } catch {}
        }
        $now = (Get-Date).ToUniversalTime().ToString("o")
        $state["last_review"] = $now

        if ($dryRun) {
            Write-Host "[dry-run] Would stamp last_review = $now in state.json" -ForegroundColor Cyan
            return
        }

        $state | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
        Write-Host "Stamped last_review = $now in state.json" -ForegroundColor Green
        Write-Host "Run 'felix doctor' to confirm the stale-review check is cleared." -ForegroundColor Gray
    }

    function Invoke-ReviewLearnings {
        if (-not (Test-Path $runsDir)) {
            Write-Host "No runs/ directory found. Nothing to review." -ForegroundColor Yellow
            return
        }

        $proposalFiles = Get-ChildItem -Path $runsDir -Recurse -Filter "agents-md-suggestions.md" `
            -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 10

        if (-not $proposalFiles -or @($proposalFiles).Count -eq 0) {
            Write-Host "No agents-md-suggestions.md files found in recent runs." -ForegroundColor Yellow
            return
        }

        $accepted = 0
        $skipped  = 0
        $deferred = 0

        foreach ($file in $proposalFiles) {
            Write-Host ""
            Write-Host "=== Proposal: $($file.FullName)" -ForegroundColor Cyan
            Write-Host ""
            Get-Content $file.FullName | ForEach-Object { Write-Host $_ }
            Write-Host ""

            if ($dryRun) {
                Write-Host "[dry-run] Would prompt: [A]ccept  [S]kip  [D]efer  [Q]uit" -ForegroundColor Cyan
                $skipped++
                continue
            }

            $choice = ""
            while ($choice -notin @("a","s","d","q")) {
                $choice = (Read-Host "[A]ccept  [S]kip  [D]efer  [Q]uit").Trim().ToLower()
            }

            switch ($choice) {
                "a" {
                    $content    = Get-Content $file.FullName -Raw
                    $headerLine = if ($file.FullName -match "\\runs\\([^\\]+)\\") { $Matches[1] } else { $file.Name }
                    $additions  = ""
                    if ($content -match "(?s)## Proposed AGENTS.md additions\s*\n(.*?)(\n##|\z)") {
                        $additions = $Matches[1].Trim()
                    }
                    if ($additions) {
                        $date   = (Get-Date).ToString("yyyy-MM-dd")
                        $marker = "<!-- [felix-learning] $date from $headerLine -->"
                        $block  = "`n`n$marker`n$additions"

                        if (-not (Test-Path $agentsFile)) {
                            Set-Content $agentsFile $block.Trim() -Encoding UTF8
                        } else {
                            $existing = Get-Content $agentsFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                            $existing = $existing.TrimEnd()
                            Set-Content $agentsFile ($existing + $block) -Encoding UTF8
                        }

                        $gitMsg = "[felix-learning] accept learning from $headerLine"
                        try {
                            Push-Location $ProjectPath
                            git add $agentsFile 2>$null
                            git commit -m $gitMsg 2>&1 | Out-Null
                            Write-Host "  Accepted and committed: $gitMsg" -ForegroundColor Green
                        } catch {
                            Write-Host "  Accepted (commit failed: $_)" -ForegroundColor Yellow
                        } finally {
                            Pop-Location
                        }
                    } else {
                        Write-Host "  No '## Proposed AGENTS.md additions' section found." -ForegroundColor Yellow
                    }
                    $accepted++
                }
                "s" { Write-Host "  Skipped." -ForegroundColor Gray; $skipped++ }
                "d" { Write-Host "  Deferred." -ForegroundColor Gray; $deferred++ }
                "q" { Write-Host "Quit." -ForegroundColor Gray; return }
            }
        }

        Write-Host ""
        Write-Host "Review complete: $accepted accepted, $skipped skipped, $deferred deferred." -ForegroundColor Cyan
    }

    function Invoke-ReviewPrompts {
        $promptsDir = Join-Path $felixDir "prompts"
        $skillsDir  = Join-Path $felixDir "skills"

        $patterns = @(
            [ordered]@{ Label = "<promise> tag";             Regex = "<promise>" }
            [ordered]@{ Label = '"do NOT" rule';             Regex = 'do NOT' }
            [ordered]@{ Label = "JSON-only output contract"; Regex = 'JSON.only|json.only' }
            [ordered]@{ Label = "per-task-size constraint";  Regex = 'small task|large task|task size' }
        )

        $searchDirs = @()
        if (Test-Path $promptsDir) { $searchDirs += $promptsDir }
        if (Test-Path $skillsDir)  { $searchDirs += $skillsDir }

        if ($searchDirs.Count -eq 0) {
            Write-Host "No prompts/ or skills/ directories found." -ForegroundColor Yellow
            return
        }

        $findings = [System.Collections.ArrayList]@()
        foreach ($dir in $searchDirs) {
            $mdFiles = Get-ChildItem -Path $dir -Filter "*.md" -Recurse -ErrorAction SilentlyContinue
            foreach ($f in $mdFiles) {
                $lines = Get-Content $f.FullName -ErrorAction SilentlyContinue
                if (-not $lines) { continue }
                $lineNum = 0
                foreach ($line in $lines) {
                    $lineNum++
                    foreach ($pat in $patterns) {
                        if ($line -imatch $pat.Regex) {
                            [void]$findings.Add([PSCustomObject]@{
                                File    = $f.FullName.Replace($ProjectPath + "\", "")
                                Line    = $lineNum
                                Pattern = $pat.Label
                                Content = $line.Trim()
                            })
                        }
                    }
                }
            }
        }

        if ($findings.Count -eq 0) {
            Write-Host "No model-workaround patterns found in prompts or skills." -ForegroundColor Green
            return
        }

        Write-Host ""
        Write-Host "Found $($findings.Count) potential model-workaround pattern(s):" -ForegroundColor Yellow
        Write-Host ""
        foreach ($f in $findings) {
            Write-Host "  $($f.File):$($f.Line)  [$($f.Pattern)]" -ForegroundColor Yellow
            Write-Host "    $($f.Content)" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "Review each occurrence and consider retiring rules that no longer apply." -ForegroundColor Cyan
    }

    # Dispatch
    if ($acknowledge) { Invoke-Acknowledge; return }
    if ($all)         { Invoke-ReviewLearnings; Invoke-ReviewPrompts; return }
    if ($learnings)   { Invoke-ReviewLearnings; return }
    if ($prompts)     { Invoke-ReviewPrompts; return }

    Write-Host "felix review - usage:" -ForegroundColor Cyan
    Write-Host "  felix review --learnings    Walk recent run proposals and accept/reject"
    Write-Host "  felix review --prompts      Audit prompts and skills for model-workaround patterns"
    Write-Host "  felix review --all          Both, in sequence"
    Write-Host "  felix review --acknowledge  Stamp last_review in state.json"
    Write-Host "  felix review --dry-run      Preview without writing or committing"
}
