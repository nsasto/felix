<#
.SYNOPSIS
felix tool  -  manage the agent tool allowlist (Phase F5).

.DESCRIPTION
Exposes Invoke-Tool for felix.ps1 dispatch.
Subcommands:
  harden [--yes] [--dry-run]   Flip default to "deny"; infer allowlist from audit log
  status                       Show current tools config and recent audit stats
#>

function Invoke-Tool {
    param(
        [string[]]$CmdArgs = @(),
        [string]$ProjectPath = (Get-Location).Path
    )

    $felixDir   = Join-Path $ProjectPath ".felix"
    $configFile = Join-Path $felixDir "config.json"
    $eventFile  = Join-Path $felixDir "events.jsonl"

    $subCmd = if ($CmdArgs.Count -gt 0) { $CmdArgs[0].ToLower() } else { "" }
    $rest   = if ($CmdArgs.Count -gt 1) { $CmdArgs[1..($CmdArgs.Count - 1)] } else { @() }
    $yes    = $rest -icontains "--yes"
    $dryRun = $rest -icontains "--dry-run"

    # Helper: load config json
    function Load-Config {
        if (-not (Test-Path $configFile)) { return [ordered]@{} }
        try { return Get-Content $configFile -Raw | ConvertFrom-Json } catch { return [ordered]@{} }
    }

    # Helper: save config back
    function Save-Config {
        param($Cfg)
        $Cfg | ConvertTo-Json -Depth 8 | Set-Content $configFile -Encoding UTF8
    }

    switch ($subCmd) {

        "harden" {
            # Step 1: infer allowlist from recent audit log (tool.call events)
            $inferred = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

            if (Test-Path $eventFile) {
                Get-Content $eventFile -Encoding UTF8 -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        $line = $_.Trim()
                        if (-not $line) { return }
                        try {
                            $evt = $line | ConvertFrom-Json
                            if ($evt.kind -eq "tool.call" -and $evt.payload.tool) {
                                [void]$inferred.Add($evt.payload.tool)
                            }
                        } catch {}
                    }
            }

            $inferredList = @($inferred | Sort-Object)

            Write-Host ""
            Write-Host "felix tool harden" -ForegroundColor Cyan
            Write-Host ""

            if ($inferredList.Count -gt 0) {
                Write-Host "Inferred allowlist from audit log ($($inferredList.Count) tool(s)):" -ForegroundColor White
                foreach ($t in $inferredList) { Write-Host "  - $t" -ForegroundColor Gray }
            } else {
                Write-Host "No tool.call events found in audit log. Using empty allowlist." -ForegroundColor Yellow
                Write-Host "Run the agent first to populate the audit log, then harden." -ForegroundColor Gray
            }

            Write-Host ""
            Write-Host "This will change tools.default from 'allow' to 'deny'." -ForegroundColor Yellow
            Write-Host "Unknown tool calls will be DENIED with a structured error." -ForegroundColor Yellow
            Write-Host ""

            if (-not $yes -and -not $dryRun) {
                $confirm = Read-Host "Proceed? [y/N]"
                if ($confirm -notmatch '^[yY]') {
                    Write-Host "Aborted." -ForegroundColor Gray
                    return
                }
            }

            if ($dryRun) {
                Write-Host "[dry-run] Would write tools config:" -ForegroundColor Cyan
                Write-Host "  default: deny"
                Write-Host "  allow: [$($inferredList -join ', ')]"
                return
            }

            $cfg = Load-Config
            # Ensure tools block exists
            if (-not $cfg.PSObject.Properties["tools"]) {
                $cfg | Add-Member -NotePropertyName "tools" -NotePropertyValue ([ordered]@{
                    allow   = @()
                    deny    = @()
                    default = "allow"
                })
            }
            $cfg.tools.allow   = $inferredList
            $cfg.tools.deny    = @()
            $cfg.tools.default = "deny"
            Save-Config $cfg

            Write-Host "tools.default = 'deny'" -ForegroundColor Green
            Write-Host "tools.allow   = [$($inferredList -join ', ')]" -ForegroundColor Green
            Write-Host ""
            Write-Host "Run 'felix tool status' to verify. Alias: 'felix tools harden'" -ForegroundColor Gray
        }

        "status" {
            $cfg = Load-Config
            $tools = if ($cfg.tools) { $cfg.tools } else { $null }

            Write-Host ""
            Write-Host "Tool allowlist status" -ForegroundColor Cyan
            Write-Host ""

            if ($tools) {
                $default = if ($tools.default) { $tools.default } else { "allow" }
                $allow   = @($tools.allow)
                $deny    = @($tools.deny)

                $statusColor = if ($default -ieq "deny") { "Yellow" } else { "Green" }
                Write-Host "  default : $default" -ForegroundColor $statusColor
                Write-Host "  allow   : $($allow.Count) pattern(s)"
                foreach ($a in $allow) { Write-Host "    + $a" -ForegroundColor Gray }
                if ($deny.Count -gt 0) {
                    Write-Host "  deny    : $($deny.Count) pattern(s)"
                    foreach ($d in $deny) { Write-Host "    - $d" -ForegroundColor Red }
                }
            } else {
                Write-Host "  No tools config found -- default-allow (v1 behaviour)" -ForegroundColor Green
            }

            # Recent audit stats
            if (Test-Path $eventFile) {
                $toolCalls = @(Get-Content $eventFile -Encoding UTF8 -ErrorAction SilentlyContinue |
                    Where-Object { $_ -match '"tool.call"' })
                Write-Host ""
                Write-Host "  Audit log: $($toolCalls.Count) tool.call event(s) in events.jsonl" -ForegroundColor Gray
            }
            Write-Host ""
        }

        default {
            Write-Host "felix tool - usage:" -ForegroundColor Cyan
            Write-Host "  felix tool harden [--yes] [--dry-run]   Flip to deny, infer allowlist from audit"
            Write-Host "  felix tool status                        Show current allowlist + audit stats"
            Write-Host ""
            Write-Host "Alias: 'felix tools harden' (deprecated in next minor)"
        }
    }
}
