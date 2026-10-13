[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('setup','migrate','run','next','loop','resume','stop','status')][string]$Action,
    [string]$ProjectPath = (Get-Location).Path,
    [ValidateSet('claude-code','opencode','codex')][string]$Harness = 'claude-code',
    [string]$RequirementId,
    [string]$SpecPath,
    [string]$RunId,
    [string]$Answer,
    [int]$MaxIterations = 0,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Invoke-Felix3Task.ps1')

$project = (Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop).Path
$configPath = Join-Path (Join-Path $project '.felix3') 'config.json'

function Initialize-Felix3Config {
    param([Parameter(Mandatory)][string]$SelectedHarness)
    if (Test-Path -LiteralPath $configPath -PathType Leaf) { throw "Felix 3 is already configured at $configPath; edit that file instead of replacing it." }
    $exampleName = switch ($SelectedHarness) {
        'opencode' { 'opencode/felix3-opencode.config.example.json' }
        'codex' { 'codex/felix3-codex.config.example.json' }
        default { 'felix3.config.example.json' }
    }
    $examplePath = Join-Path $PSScriptRoot $exampleName
    if (-not (Test-Path -LiteralPath $examplePath -PathType Leaf)) { throw "Felix 3 $SelectedHarness configuration example is unavailable: $examplePath" }
    New-Item -ItemType Directory -Path (Split-Path -Parent $configPath) -Force | Out-Null
    Copy-Item -LiteralPath $examplePath -Destination $configPath
    if ($SelectedHarness -eq 'opencode') {
        $sourceAgents = Join-Path $PSScriptRoot 'opencode/agents'
        $targetAgents = Join-Path (Join-Path $project '.opencode') 'agents'
        New-Item -ItemType Directory -Path $targetAgents -Force | Out-Null
        foreach ($agentFile in Get-ChildItem -LiteralPath $sourceAgents -File -Filter '*.md') {
            $targetFile = Join-Path $targetAgents $agentFile.Name
            if (-not (Test-Path -LiteralPath $targetFile)) { Copy-Item -LiteralPath $agentFile.FullName -Destination $targetFile }
        }
    }
    return $configPath
}

switch ($Action) {
    'setup' {
        $created = Initialize-Felix3Config -SelectedHarness $Harness
        Write-Host "Felix 3 configured for $Harness at $created. Add validation commands and provider credentials before running."
    }
    'migrate' {
        $legacy = @(@('.felix/config.json','.felix/requirements.json','.felix/agents.json','requirements.json','specs') | Where-Object { Test-Path -LiteralPath (Join-Path $project $_) })
        if (Test-Path -LiteralPath $configPath -PathType Leaf) {
            Write-Host "Felix 3 config already exists: $configPath"
            Write-Host 'No changes planned.'
            break
        }
        Write-Host 'Felix 3 migration preview'
        if ($legacy.Count -gt 0) { Write-Host ("Detected V2 project data: " + ($legacy -join ', ')) }
        else { Write-Host 'No common Felix 2 project files detected.' }
        Write-Host "Would create: $configPath (harness: $Harness)"
        Write-Host 'Existing Felix 2 files, specs, requirements, and agent profiles will be preserved unchanged.'
        Write-Host 'V3 work selection uses Markdown frontmatter status in specs; no V2 requirements or agent config is imported.'
        if (-not $Apply) { Write-Host 'Preview only. Re-run with --apply to create the V3 project config.'; break }
        $created = Initialize-Felix3Config -SelectedHarness $Harness
        Write-Host "Felix 3 config created at $created. Review it and set spec statuses before running."
    }
    'run' {
        if ([string]::IsNullOrWhiteSpace($RequirementId) -or [string]::IsNullOrWhiteSpace($SpecPath)) { throw 'Usage: felix v3 run <requirement-id> --spec <project-relative-path>' }
        $result = Invoke-Felix3Task -ProjectPath $project -RequirementId $RequirementId -SpecPath $SpecPath
        $result | Format-List
        if ($result.Status -ne 'completed') { exit 1 }
    }
    'next' {
        $config = Import-Felix3Config -Path $configPath
        $result = if ($config.work_source.provider -eq 'felix-cloud') { Invoke-Felix3CloudWorkCycle -ProjectPath $project -Answer $Answer } else { Invoke-Felix3LocalWorkCycle -ProjectPath $project -Answer $Answer }
        if ($result.Status -eq 'no-work') { Write-Host 'No ready Felix 3 work is available.' }
        else { $result.Run | Format-List }
        if ($result.Status -in @('blocked','interrupted')) { exit 1 }
    }
    'loop' {
        $iteration = 0
        while ($MaxIterations -le 0 -or $iteration -lt $MaxIterations) {
            $iteration++
            $config = Import-Felix3Config -Path $configPath
            $result = if ($config.work_source.provider -eq 'felix-cloud') { Invoke-Felix3CloudWorkCycle -ProjectPath $project } else { Invoke-Felix3LocalWorkCycle -ProjectPath $project }
            if ($result.Status -eq 'no-work') {
                Write-Host 'No ready Felix 3 work; checking again in 10 seconds.'
                Start-Sleep -Seconds 10
                continue
            }
            $result.Run | Format-List
            if ($result.Status -in @('awaiting-input','awaiting-plan-approval','interrupted')) {
                Write-Host "Run $($result.Run.RunId) is $($result.Status). Resume with 'felix v3 resume $($result.Run.RunId)'."
                break
            }
        }
    }
    'resume' {
        if ([string]::IsNullOrWhiteSpace($RunId)) { throw 'Usage: felix v3 resume <run-id> [-Answer <text>]' }
        $claimPath = Join-Path (Join-Path (Join-Path $project '.felix3') 'work-source') 'cloud-claim.json'
        if (Test-Path -LiteralPath $claimPath -PathType Leaf) {
            $claim = Get-Content -LiteralPath $claimPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$claim.run_id -eq $RunId) {
                $result = Invoke-Felix3CloudWorkCycle -ProjectPath $project -Answer $Answer
            }
            else { $result = Resume-Felix3Task -ProjectPath $project -RunId $RunId -Answer $Answer }
        }
        else {
            $localStatePath = Join-Path (Join-Path (Join-Path $project '.felix3') 'work-source') 'local-active.json'
            if ((Test-Path -LiteralPath $localStatePath -PathType Leaf) -and ([string](Get-Content -LiteralPath $localStatePath -Raw | ConvertFrom-Json).run_id -eq $RunId)) {
                $result = (Invoke-Felix3LocalWorkCycle -ProjectPath $project -Answer $Answer).Run
            } else { $result = Resume-Felix3Task -ProjectPath $project -RunId $RunId -Answer $Answer }
        }
        $result | Format-List
        if ($result.Status -notin @('completed','awaiting-input','awaiting-plan-approval')) { exit 1 }
    }
    'stop' {
        if ([string]::IsNullOrWhiteSpace($RunId)) { throw 'Usage: felix v3 stop <run-id>' }
        Stop-Felix3Task -ProjectPath $project -RunId $RunId | Format-List
    }
    'status' {
        if ([string]::IsNullOrWhiteSpace($RunId)) { throw 'Usage: felix v3 status <run-id>' }
        $config = Import-Felix3Config -Path $configPath
        $runsRoot = Resolve-Felix3Path -Path ([string]$config.artifacts.runs_dir) -BasePath $project
        $runDirectory = Resolve-Felix3RunDirectory -RunsRoot $runsRoot -RunId $RunId
        $statePath = Join-Path $runDirectory 'state.json'
        if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "Felix 3 run state not found: $RunId" }
        Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json | Format-List
    }
}
