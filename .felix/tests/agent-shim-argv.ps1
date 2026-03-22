param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"

$argsJoined = if ($Args -and $Args.Count -gt 0) { $Args -join " " } else { "" }
$signal = "<promise>ALL_COMPLETE</promise>"

$cwd = (Get-Location).Path
$projectRoot = Split-Path $cwd -Parent
$fallbackPlanPath = $null
$runsDir = Join-Path $projectRoot "runs"
if (Test-Path $runsDir) {
    $latestRun = Get-ChildItem $runsDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestRun) {
        $fallbackPlanPath = Join-Path $latestRun.FullName "plan-S-0001.md"
    }
}

$planPath = $null
if ($argsJoined -match '\*\*(?<path>[^*]+plan-[^*]+\.md)\*\*') {
    $planPath = $matches['path']
}
elseif ($fallbackPlanPath) {
    $planPath = $fallbackPlanPath
}

if ($planPath) {
    $planDir = Split-Path $planPath -Parent
    if ($planDir -and -not (Test-Path $planDir)) {
        New-Item -ItemType Directory -Path $planDir -Force | Out-Null
    }

    $planContent = @"
# Implementation Plan for S-0001

## Summary

Shim-generated smoke test plan.

## Tasks

- [ ] Smoke task
"@
    Set-Content $planPath $planContent -Encoding UTF8
    $signal = "<promise>PLAN_COMPLETE</promise>"
}
$envValue = $env:FELIX_AGENT_TEST

Write-Output "__AGENT_SHIM__=1"
Write-Output "__AGENT_CWD__=$cwd"
Write-Output "__AGENT_ENV__=$envValue"
Write-Output "__AGENT_PROMPT_LEN__=0"
Write-Output "__AGENT_ARGS__=$argsJoined"
Write-Output "**Task Completed:** Smoke test agent invocation"
Write-Output $signal

exit 0