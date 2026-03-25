<#
.SYNOPSIS
Validates that commands are consistently registered across all three sources:
  1. .felix/commands/*.ps1 files (the implementations)
    2. src/Felix.Cli/*.cs        (C# System.CommandLine registrations)
  3. .felix/commands/help.ps1  (help text summary + detail switch cases)

Note: felix.ps1 no longer uses [ValidateSet] — unknown commands are discovered
dynamically from commands/*.ps1 at runtime (generic passthrough).

Exits 0 if all consistent, 1 if any divergence found.
#>

param(
    [switch]$WarnOnly  # Print warnings but exit 0 (non-blocking)
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$commandsDir = Join-Path $repoRoot ".felix\commands"
$cliSourceDir = Join-Path $repoRoot "src\Felix.Cli"
$helpPs1 = Join-Path $repoRoot ".felix\commands\help.ps1"

$ok = $true

function Write-Issue {
    param([string]$Msg)
    Write-Host "  [WARN] $Msg" -ForegroundColor Yellow
    $script:ok = $false
}

# ── 1. Command files ─────────────────────────────────────────────────────────
# Subcommand files that are dot-sourced from a parent — not top-level commands.
$subcommandFiles = @("spec-pull", "spec-fix", "spec-push", "context-pull", "context-push")

$fileCommands = Get-ChildItem $commandsDir -Filter "*.ps1" |
ForEach-Object { $_.BaseName } |
Where-Object { $_ -notin $subcommandFiles } |
Sort-Object

# ── 2. C# registered commands ────────────────────────────────────────────────
# Look across the CLI source tree because Program.cs is split into partials.
$csFiles = Get-ChildItem $cliSourceDir -Filter "*.cs" -Recurse | Sort-Object FullName
$csContent = ($csFiles | Get-Content -Raw) -join "`n"
$csMatches = [regex]::Matches($csContent, 'rootCommand\.AddCommand\(Create(\w+)Command\(')
$csCommands = $csMatches | ForEach-Object {
    # Convert PascalCase to kebab-case: RunNext → run-next
    $pascal = $_.Groups[1].Value
    ($pascal -creplace '([A-Z])', '-$1').TrimStart('-').ToLower()
} | Sort-Object -Unique

# ── 3. Help.ps1 ──────────────────────────────────────────────────────────────
$helpContent = Get-Content $helpPs1 -Raw

# Detail section: switch ("name") { cases
$helpDetailMatches = [regex]::Matches($helpContent, '"([a-z][a-z0-9-]*)" \{')
$helpDetailCmds = $helpDetailMatches | ForEach-Object { $_.Groups[1].Value } |
Where-Object { $_ -ne "default" } | Sort-Object -Unique

# Summary listing: Write-Host "  name " or "  name <arg>"
$helpSummaryMatches = [regex]::Matches($helpContent, 'Write-Host "  ([a-z][a-z0-9-]+)[\s<]')
$helpSummaryCmds = $helpSummaryMatches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

# ── Excluded from checks (internal/alias/special) ───────────────────────────
# 'help' and 'tui' don't need detail switch cases (tui is trivial, help IS the command)
# 'dashboard' is a C#-only alias for tui
# 'install' is a hidden C#-only bootstrap command
$csOnlyCommands = @("dashboard", "install", "update")
$noDetailRequired = @("help", "tui", "setup", "version", "agent")
Write-Host ""
Write-Host "Command Registry Check" -ForegroundColor Cyan
Write-Host "------------------------------------------" -ForegroundColor DarkGray

# ── Check: every command file has a C# registration ─────────────────────────
Write-Host "File -> C# registration:" -ForegroundColor Gray
foreach ($cmd in $fileCommands) {
    if ($cmd -notin $csCommands) {
        Write-Issue "'.felix/commands/$cmd.ps1' has no C# command registration in src/Felix.Cli"
    }
}

# ── Check: every C# command (non-alias) has a command file ──────────────────
Write-Host "C# -> command file:" -ForegroundColor Gray
foreach ($cmd in $csCommands) {
    if ($cmd -in $csOnlyCommands) { continue }
    $file = Join-Path $commandsDir "$cmd.ps1"
    if (-not (Test-Path $file)) {
        Write-Issue "C# registers '$cmd' but no '.felix/commands/$cmd.ps1' exists"
    }
}

# ── Check: every command file (non-trivial) has a help detail entry ──────────
Write-Host "File -> help detail:" -ForegroundColor Gray
foreach ($cmd in $fileCommands) {
    if ($cmd -in $noDetailRequired) { continue }
    if ($cmd -notin $helpDetailCmds) {
        Write-Issue "'.felix/commands/$cmd.ps1' has no detail section in help.ps1 (add a `"$cmd`" switch case)"
    }
}

# ── Check: every command file is in the help summary listing ─────────────────
Write-Host "File -> help summary:" -ForegroundColor Gray
foreach ($cmd in $fileCommands) {
    if ($cmd -notin $helpSummaryCmds) {
        Write-Issue "'.felix/commands/$cmd.ps1' is not listed in the help summary (Write-Host block)"
    }
}

Write-Host ""
if ($ok) {
    Write-Host "[OK] All commands consistently registered." -ForegroundColor Green
    exit 0
}
else {
    if ($WarnOnly) {
        Write-Host "[WARN] Command registry has divergence (see above). Build continues." -ForegroundColor Yellow
        exit 0
    }
    else {
        Write-Host "[FAIL] Command registry divergence detected. Fix the issues above or run with -WarnOnly." -ForegroundColor Red
        exit 1
    }
}
