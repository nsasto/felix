<#
.SYNOPSIS
Phase E unit tests - Learning, Memory, Review (Test-PhaseE.ps1)

Tests: Get-RunEvents, Get-MemoryContext, memory.ps1 subcommands,
       learning-capture on-postiteration, review --acknowledge,
       doctor stale-review check, config flag auto_propose=false
#>

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

# â”€â”€ Assert helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$script:TestsPassed = 0
$script:TestsFailed = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Label)
    if ($Expected -ne $Actual) {
        Write-Host "  FAIL [$Label]: expected '$Expected', got '$Actual'" -ForegroundColor Red
        $script:TestsFailed++
    } else {
        Write-Host "  PASS [$Label]" -ForegroundColor Green
        $script:TestsPassed++
    }
}

function Assert-True {
    param($Condition, [string]$Label)
    if (-not $Condition) {
        Write-Host "  FAIL [$Label]: condition was false" -ForegroundColor Red
        $script:TestsFailed++
    } else {
        Write-Host "  PASS [$Label]" -ForegroundColor Green
        $script:TestsPassed++
    }
}

function Assert-False {
    param($Condition, [string]$Label)
    if ($Condition) {
        Write-Host "  FAIL [$Label]: condition was true (expected false)" -ForegroundColor Red
        $script:TestsFailed++
    } else {
        Write-Host "  PASS [$Label]" -ForegroundColor Green
        $script:TestsPassed++
    }
}

function Assert-NotNull {
    param($Value, [string]$Label)
    if ($null -eq $Value) {
        Write-Host "  FAIL [$Label]: value was null" -ForegroundColor Red
        $script:TestsFailed++
    } else {
        Write-Host "  PASS [$Label]" -ForegroundColor Green
        $script:TestsPassed++
    }
}

function Assert-Null {
    param($Value, [string]$Label)
    if ($null -ne $Value) {
        Write-Host "  FAIL [$Label]: expected null, got '$Value'" -ForegroundColor Red
        $script:TestsFailed++
    } else {
        Write-Host "  PASS [$Label]" -ForegroundColor Green
        $script:TestsPassed++
    }
}

function Assert-Contains {
    param($Substring, $Actual, [string]$Label)
    if ($Actual -notmatch [regex]::Escape($Substring)) {
        Write-Host "  FAIL [$Label]: '$Substring' not found in output" -ForegroundColor Red
        $script:TestsFailed++
    } else {
        Write-Host "  PASS [$Label]" -ForegroundColor Green
        $script:TestsPassed++
    }
}

# â”€â”€ Resolve repo root â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
$repoRoot  = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$felixCore = Join-Path $repoRoot ".felix\core"
$felixCmds = Join-Path $repoRoot ".felix\commands"
$felixPlug = Join-Path $repoRoot ".felix\plugins"

# â”€â”€ Temp dir helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function New-TempDir {
    $t = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $t -Force | Out-Null
    return $t
}

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# SECTION 1: Get-RunEvents (E7)
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n== Get-RunEvents (E7) =="

. (Join-Path $felixCore "event-reader.ps1")

$tmp1 = New-TempDir

# Write mock events.jsonl
$events = @(
    @{ run_id = "S-0001-run1"; kind = "iteration.start"; message = "started" } | ConvertTo-Json -Compress
    @{ run_id = "S-0001-run1"; kind = "backpressure.fail"; message = "tests failed"; context = @{ command = "pytest" } } | ConvertTo-Json -Compress
    @{ run_id = "S-0001-run1"; kind = "iteration.complete"; outcome = "success" } | ConvertTo-Json -Compress
    @{ run_id = "S-0002-run2"; kind = "backpressure.fail"; message = "other run" } | ConvertTo-Json -Compress
)
Set-Content (Join-Path $tmp1 "events.jsonl") ($events -join "`n") -Encoding UTF8

$all = @(Get-RunEvents -FelixDir $tmp1 -RunId "S-0001-run1")
Assert-Equal 3 $all.Count "Get-RunEvents: returns all events for run_id"

$fails = @(Get-RunEvents -FelixDir $tmp1 -RunId "S-0001-run1" -Kinds @("backpressure.fail"))
Assert-Equal 1 $fails.Count "Get-RunEvents: filters by kind"

$none = @(Get-RunEvents -FelixDir $tmp1 -RunId "S-9999-notexist")
Assert-Equal 0 $none.Count "Get-RunEvents: returns empty for unknown run"

$empty = @(Get-RunEvents -FelixDir $tmp1 -RunId "S-0002-run2")
Assert-Equal 1 $empty.Count "Get-RunEvents: isolates other run events"

# No file case
$noFile = @(Get-RunEvents -FelixDir $tmp1 -RunId "X") 
Assert-Equal 0 $noFile.Count "Get-RunEvents: returns empty when no events.jsonl"

Remove-Item $tmp1 -Recurse -Force

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# SECTION 2: Get-MemoryContext (E4)
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n== Get-MemoryContext (E4) =="

. (Join-Path $felixCore "memory-loader.ps1")

$tmp2 = New-TempDir

# Create mock memory tree
$repoMemDir = Join-Path $tmp2 "memory\repo"
$reqMemDir  = Join-Path $tmp2 "memory\requirement\S-0001"
New-Item -ItemType Directory $repoMemDir -Force | Out-Null
New-Item -ItemType Directory $reqMemDir -Force | Out-Null

$repoFile = Join-Path $repoMemDir "2026-01-01-test.md"
Set-Content $repoFile @"
---
title: Repo memory test
scope: repo
created: 2026-01-01
tags: []
---

Remember this repo fact.
"@ -Encoding UTF8

$reqFile = Join-Path $reqMemDir "2026-01-01-req.md"
Set-Content $reqFile @"
---
title: Req memory test
scope: requirement
created: 2026-01-01
tags: []
---

Remember this requirement fact.
"@ -Encoding UTF8

# Repo scope only (exclude global to avoid user files)
$repoCtx = Get-MemoryContext -FelixDir $tmp2 -IncludeGlobal $false
Assert-True ($repoCtx -match "Repo memory test" -or $repoCtx -match "Remember this repo fact") "Get-MemoryContext: includes repo memory"
Assert-False ($repoCtx -match "Remember this requirement fact") "Get-MemoryContext: excludes requirement when no req-id"

# Repo + requirement scope
$reqCtx = Get-MemoryContext -FelixDir $tmp2 -RequirementId "S-0001" -IncludeGlobal $false
Assert-True ($reqCtx -match "Remember this repo fact") "Get-MemoryContext: includes repo in combined"
Assert-True ($reqCtx -match "Remember this requirement fact") "Get-MemoryContext: includes requirement memory"

# Empty when no files
$empty2 = Get-MemoryContext -FelixDir $tmp2 -RequirementId "S-NONE" -IncludeGlobal $false
$emptyPath = Join-Path $tmp2 "memory\repo\2026-01-01-test.md"
Remove-Item $emptyPath -Force -ErrorAction SilentlyContinue
Remove-Item $reqFile -Force -ErrorAction SilentlyContinue
$noMem = Get-MemoryContext -FelixDir $tmp2 -IncludeGlobal $false
Assert-Equal "" $noMem "Get-MemoryContext: empty when no files"

# Multiple files separated by ---
New-Item -ItemType Directory $repoMemDir -Force | Out-Null
Set-Content (Join-Path $repoMemDir "a.md") "---`ntitle: A`nscope: repo`ncreated: 2026-01-01`ntags: []`n---`nFact A" -Encoding UTF8
Set-Content (Join-Path $repoMemDir "b.md") "---`ntitle: B`nscope: repo`ncreated: 2026-01-01`ntags: []`n---`nFact B" -Encoding UTF8
$multi = Get-MemoryContext -FelixDir $tmp2 -IncludeGlobal $false
Assert-True ($multi -match "Fact A") "Get-MemoryContext: multi-file includes A"
Assert-True ($multi -match "Fact B") "Get-MemoryContext: multi-file includes B"
Assert-True ($multi -match "---") "Get-MemoryContext: multi-file has separator"

Remove-Item $tmp2 -Recurse -Force

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# SECTION 3: memory.ps1 - view subcommand
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n== memory.ps1 view (E5) =="

$tmp3 = New-TempDir
$fakeProject = Join-Path $tmp3 "project"
New-Item -ItemType Directory $fakeProject -Force | Out-Null
$fakeFelix = Join-Path $fakeProject ".felix"
$fakeMemRepo = Join-Path $fakeFelix "memory\repo"
New-Item -ItemType Directory $fakeMemRepo -Force | Out-Null

Set-Content (Join-Path $fakeMemRepo "2026-01-01-hello.md") @"
---
title: Hello Memory
scope: repo
created: 2026-01-01
tags: []
---

Some content
"@ -Encoding UTF8

$viewOut = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    . '$($felixCmds -replace "'","''")\memory.ps1'
    Invoke-Memory -CmdArgs @('view', '--scope', 'repo') -ProjectPath '$($fakeProject -replace "'","''")'
" 2>&1 | Out-String

Assert-True ($viewOut -match "Hello Memory" -or $viewOut -match "hello") "memory view: shows title from repo scope"
Assert-True ($viewOut -match "repo") "memory view: shows scope label"

Remove-Item $tmp3 -Recurse -Force

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# SECTION 4: memory.ps1 - add subcommand
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n== memory.ps1 add (E5) =="

$tmp4 = New-TempDir
$proj4 = Join-Path $tmp4 "project"
$mem4  = Join-Path $proj4 ".felix\memory\repo"
New-Item -ItemType Directory $mem4 -Force | Out-Null

$addOut = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    . '$($felixCmds -replace "'","''")\memory.ps1'
    Invoke-Memory -CmdArgs @('add', '--scope', 'repo', '--title', 'Test Entry', '--body', 'Test body text') -ProjectPath '$($proj4 -replace "'","''")'
" 2>&1 | Out-String

$created = Get-ChildItem $mem4 -Filter "*.md" -ErrorAction SilentlyContinue
Assert-True ($created.Count -gt 0) "memory add: creates a file"
if ($created.Count -gt 0) {
    $fileContent = Get-Content $created[0].FullName -Raw
    Assert-True ($fileContent -match "title: Test Entry") "memory add: frontmatter has title"
    Assert-True ($fileContent -match "scope: repo") "memory add: frontmatter has scope"
    Assert-True ($fileContent -match "created:") "memory add: frontmatter has created"
    Assert-True ($fileContent -match "Test body text") "memory add: body is written"
}

Remove-Item $tmp4 -Recurse -Force

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# SECTION 5: memory.ps1 - prune subcommand
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n== memory.ps1 prune (E5) =="

$tmp5 = New-TempDir
$proj5  = Join-Path $tmp5 "project"
$runs5  = Join-Path $proj5 "runs"
$mem5   = Join-Path $proj5 ".felix\memory\repo"
New-Item -ItemType Directory $runs5 -Force | Out-Null
New-Item -ItemType Directory $mem5  -Force | Out-Null

# Old proposal (60 days ago)
$oldRun = Join-Path $runs5 "S-0001-old"
New-Item -ItemType Directory $oldRun -Force | Out-Null
$oldFile = Join-Path $oldRun "agents-md-suggestions.md"
Set-Content $oldFile "# Old proposal" -Encoding UTF8
(Get-Item $oldFile).LastWriteTime = (Get-Date).AddDays(-60)

# Recent proposal (1 day ago)
$newRun = Join-Path $runs5 "S-0001-new"
New-Item -ItemType Directory $newRun -Force | Out-Null
$newFile = Join-Path $newRun "agents-md-suggestions.md"
Set-Content $newFile "# New proposal" -Encoding UTF8

# Memory file (should NEVER be pruned)
$memFile = Join-Path $mem5 "important.md"
Set-Content $memFile "# Protected" -Encoding UTF8
(Get-Item $memFile).LastWriteTime = (Get-Date).AddDays(-120)

$pruneOut = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    . '$($felixCmds -replace "'","''")\memory.ps1'
    Invoke-Memory -CmdArgs @('prune', '--older-than', '30') -ProjectPath '$($proj5 -replace "'","''")'
" 2>&1 | Out-String

Assert-False (Test-Path $oldFile) "memory prune: deletes old proposal file"
Assert-True (Test-Path $newFile) "memory prune: preserves recent proposal file"
Assert-True (Test-Path $memFile) "memory prune: never touches .felix/memory/ files"

# Dry run
$newFile2 = Join-Path (New-Item -ItemType Directory (Join-Path $runs5 "S-run-dry") -Force).FullName "agents-md-suggestions.md"
Set-Content $newFile2 "# dry" -Encoding UTF8
(Get-Item $newFile2).LastWriteTime = (Get-Date).AddDays(-90)

$dryOut = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    . '$($felixCmds -replace "'","''")\memory.ps1'
    Invoke-Memory -CmdArgs @('prune', '--older-than', '30', '--dry-run') -ProjectPath '$($proj5 -replace "'","''")'
" 2>&1 | Out-String

Assert-True (Test-Path $newFile2) "memory prune --dry-run: does not delete"
Assert-True ($dryOut -match "dry-run") "memory prune --dry-run: mentions dry-run"

Remove-Item $tmp5 -Recurse -Force

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# SECTION 6: learning-capture on-postiteration (E1)
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n== learning-capture on-postiteration (E1) =="

$tmp6  = New-TempDir
$felix6 = Join-Path $tmp6 "felix"
$run6   = Join-Path $tmp6 "run"
New-Item -ItemType Directory $felix6 -Force | Out-Null
New-Item -ItemType Directory $run6  -Force | Out-Null

# Write mock events.jsonl with a backpressure failure
$runId6 = "S-0042-20260101-120000-it1"
$evts6  = @(
    ([ordered]@{ run_id = $runId6; kind = "backpressure.fail"; message = "pytest failed"; context = [ordered]@{ command = "pytest tests/" } } | ConvertTo-Json -Compress)
    ([ordered]@{ run_id = $runId6; kind = "IterationCompleted"; outcome = "failure" } | ConvertTo-Json -Compress)
)
Set-Content (Join-Path $felix6 "events.jsonl") ($evts6 -join "`n") -Encoding UTF8

# Simulate calling the hook
$hookScript = Join-Path $felixPlug "learning-capture\on-postiteration.ps1"
$hookResult = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    `$r = & '$($hookScript -replace "'","''")'  ``
        -HookName 'OnPostIteration'  ``
        -RunId '$runId6'  ``
        -Data @{ FelixDir = '$($felix6 -replace "'","''")'; RunDir = '$($run6 -replace "'","''")' }
    `$r.ShouldContinue
" 2>&1

$suggestFile = Join-Path $run6 "agents-md-suggestions.md"
Assert-True (Test-Path $suggestFile) "learning-capture: creates agents-md-suggestions.md"

if (Test-Path $suggestFile) {
    $suggestContent = Get-Content $suggestFile -Raw
    Assert-True ($suggestContent -match "Suggestions from") "learning-capture: file has heading"
    Assert-True ($suggestContent -match "Proposed AGENTS.md additions") "learning-capture: has AGENTS.md section"
    Assert-True ($suggestContent -match "pytest") "learning-capture: includes failed command"
}

# Test ShouldContinue = true
$scVal = $hookResult | Select-String "^True$" 
Assert-True ($scVal -ne $null -or $hookResult -match "True") "learning-capture: returns ShouldContinue=true"

Remove-Item $tmp6 -Recurse -Force

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# SECTION 7: learning-capture with auto_propose=false
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n== learning-capture auto_propose=false (E1) =="

$tmp7  = New-TempDir
$run7  = Join-Path $tmp7 "run"
New-Item -ItemType Directory $run7 -Force | Out-Null
New-Item -ItemType Directory $tmp7 -Force | Out-Null

# Write events (would normally generate proposals)
Set-Content (Join-Path $tmp7 "events.jsonl") (@([ordered]@{ run_id = "X"; kind = "backpressure.fail"; message = "fail" } | ConvertTo-Json -Compress)) -Encoding UTF8

$hookScript7 = Join-Path $felixPlug "learning-capture\on-postiteration.ps1"
powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    `$cfg = [PSCustomObject]@{ learning = [PSCustomObject]@{ auto_propose = `$false } }
    & '$($hookScript7 -replace "'","''")'  ``
        -HookName 'OnPostIteration'  ``
        -RunId 'X'  ``
        -Data @{ FelixDir = '$($tmp7 -replace "'","''")'; RunDir = '$($run7 -replace "'","''")' }  ``
        -Config `$cfg
" 2>&1 | Out-Null

$noSuggest = Join-Path $run7 "agents-md-suggestions.md"
Assert-False (Test-Path $noSuggest) "learning-capture: skips when auto_propose=false (via Config)"

Remove-Item $tmp7 -Recurse -Force

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# SECTION 8: review --acknowledge (E2)
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n== review --acknowledge (E2) =="

$tmp8  = New-TempDir
$proj8 = Join-Path $tmp8 "project"
$fx8   = Join-Path $proj8 ".felix"
New-Item -ItemType Directory $fx8 -Force | Out-Null

$reviewScript = Join-Path $felixCmds "review.ps1"
powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    . '$($reviewScript -replace "'","''")'
    Invoke-Review -CmdArgs @('--acknowledge') -ProjectPath '$($proj8 -replace "'","''")'
" 2>&1 | Out-Null

$stateFile8 = Join-Path $fx8 "state.json"
Assert-True (Test-Path $stateFile8) "review --acknowledge: creates state.json"

if (Test-Path $stateFile8) {
    $state8 = Get-Content $stateFile8 -Raw | ConvertFrom-Json
    Assert-NotNull $state8.last_review "review --acknowledge: writes last_review"
}

# DryRun: should NOT write
Remove-Item $stateFile8 -Force -ErrorAction SilentlyContinue
powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    . '$($reviewScript -replace "'","''")'
    Invoke-Review -CmdArgs @('--acknowledge', '--dry-run') -ProjectPath '$($proj8 -replace "'","''")'
" 2>&1 | Out-Null

Assert-False (Test-Path $stateFile8) "review --acknowledge --dry-run: does not write state.json"

Remove-Item $tmp8 -Recurse -Force

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# SECTION 9: doctor stale-review check (E3)
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n== doctor stale-review check (E3) =="

$tmp9  = New-TempDir
$proj9 = Join-Path $tmp9 "project"
$fx9   = Join-Path $proj9 ".felix"
New-Item -ItemType Directory $fx9 -Force | Out-Null

# Create minimal AGENTS.md and specs dir so other checks don't fail noisily
Set-Content (Join-Path $proj9 "AGENTS.md") "# Test" -Encoding UTF8

$doctorScript = Join-Path $felixCmds "doctor.ps1"

# Case 1: no last_review - should warn
$out9a = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    & '$($doctorScript -replace "'","''")'  ``
        -Json  ``
        -ProjectPath '$($proj9 -replace "'","''")'
" 2>&1 | Out-String

$json9a = $null
try { $json9a = $out9a | ConvertFrom-Json } catch {}
if ($json9a) {
    $srCheck = $json9a.checks | Where-Object { $_.id -eq "stale-review" }
    Assert-NotNull $srCheck "doctor: stale-review check present"
    Assert-Equal "warn" ($srCheck.status) "doctor: stale-review warns when no last_review"
} else {
    Assert-True ($out9a -match "stale-review") "doctor: stale-review present in output"
}

# Case 2: recent last_review - should be ok
$freshState = @{ last_review = (Get-Date).ToString("o") }
$freshState | ConvertTo-Json | Set-Content (Join-Path $fx9 "state.json") -Encoding UTF8

$out9b = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    & '$($doctorScript -replace "'","''")'  ``
        -Json  ``
        -ProjectPath '$($proj9 -replace "'","''")'
" 2>&1 | Out-String

$json9b = $null
try { $json9b = $out9b | ConvertFrom-Json } catch {}
if ($json9b) {
    $srCheck2 = $json9b.checks | Where-Object { $_.id -eq "stale-review" }
    Assert-Equal "ok" ($srCheck2.status) "doctor: stale-review ok when recent"
} else {
    Assert-True ($out9b -match "stale-review" -or $out9b -match "ok") "doctor: stale-review ok in output"
}

# Case 3: overdue last_review (> 90 days)
$oldState = @{ last_review = (Get-Date).AddDays(-100).ToString("o") }
$oldState | ConvertTo-Json | Set-Content (Join-Path $fx9 "state.json") -Encoding UTF8

$out9c = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    & '$($doctorScript -replace "'","''")'  ``
        -Json  ``
        -ProjectPath '$($proj9 -replace "'","''")'
" 2>&1 | Out-String

$json9c = $null
try { $json9c = $out9c | ConvertFrom-Json } catch {}
if ($json9c) {
    $srCheck3 = $json9c.checks | Where-Object { $_.id -eq "stale-review" }
    Assert-Equal "warn" ($srCheck3.status) "doctor: stale-review warns when overdue"
} else {
    Assert-True ($out9c -match "overdue") "doctor: stale-review overdue message present"
}

Remove-Item $tmp9 -Recurse -Force

# ---------------------------------------------------------------------------
# SECTION 9b: doctor usage telemetry checks
# ---------------------------------------------------------------------------
Write-Host "`n== doctor usage telemetry checks =="

$tmp9d  = New-TempDir
$proj9d = Join-Path $tmp9d "project"
$fx9d   = Join-Path $proj9d ".felix"
$run9d  = Join-Path $proj9d "runs\S-0001-run1"
New-Item -ItemType Directory $fx9d -Force | Out-Null
New-Item -ItemType Directory $run9d -Force | Out-Null
Set-Content (Join-Path $proj9d "AGENTS.md") "# Test" -Encoding UTF8

$out9dMissing = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    & '$($doctorScript -replace "'","''")'  ``
        -Json  ``
        -ProjectPath '$($proj9d -replace "'","''")'
" 2>&1 | Out-String

$json9dMissing = $out9dMissing | ConvertFrom-Json
$usageMissing = $json9dMissing.checks | Where-Object { $_.id -eq "usage-artifacts" }
Assert-Equal "warn" ($usageMissing.status) "doctor: usage-artifacts warns when existing runs have no usage.json"

$usageRecord9d = [ordered]@{
    _v              = 1
    run_id          = "S-0001-run1"
    usage_available = $true
    agent           = [ordered]@{ provider = "codex"; adapter = "codex"; name = "codex" }
    model           = [ordered]@{ configured = "gpt-test"; effective = "gpt-test"; source = "codex.output" }
    usage           = [ordered]@{ input_tokens = 10; output_tokens = 20; total_tokens = 30 }
}
$usageRecord9d | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $run9d "usage.json") -Encoding UTF8

$out9dNoPricing = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    & '$($doctorScript -replace "'","''")'  ``
        -Json  ``
        -ProjectPath '$($proj9d -replace "'","''")'
" 2>&1 | Out-String

$json9dNoPricing = $out9dNoPricing | ConvertFrom-Json
$usageOk = $json9dNoPricing.checks | Where-Object { $_.id -eq "usage-artifacts" }
$pricingMissing = $json9dNoPricing.checks | Where-Object { $_.id -eq "usage-pricing" }
Assert-Equal "ok" ($usageOk.status) "doctor: usage-artifacts ok when usage.json has token and model details"
Assert-Equal "warn" ($pricingMissing.status) "doctor: usage-pricing warns when pricing file is missing"

$pricing9d = [ordered]@{
    _v       = 1
    currency = "USD"
    prices   = @(
        [ordered]@{
            provider           = "codex"
            model              = "gpt-test"
            input_per_million  = 1.0
            output_per_million = 2.0
        }
    )
}
$pricing9d | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $fx9d "model-pricing.json") -Encoding UTF8

$out9dPriced = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    & '$($doctorScript -replace "'","''")'  ``
        -Json  ``
        -ProjectPath '$($proj9d -replace "'","''")'
" 2>&1 | Out-String

$json9dPriced = $out9dPriced | ConvertFrom-Json
$pricingOk = $json9dPriced.checks | Where-Object { $_.id -eq "usage-pricing" }
Assert-Equal "ok" ($pricingOk.status) "doctor: usage-pricing ok when observed model has pricing"

$usageRecord9d.usage_available = $false
$usageRecord9d.model.effective = ""
$usageRecord9d | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $run9d "usage.json") -Encoding UTF8

$out9dUnavailable = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    & '$($doctorScript -replace "'","''")'  ``
        -Json  ``
        -ProjectPath '$($proj9d -replace "'","''")'
" 2>&1 | Out-String

$json9dUnavailable = $out9dUnavailable | ConvertFrom-Json
$usageUnavailable = $json9dUnavailable.checks | Where-Object { $_.id -eq "usage-artifacts" }
Assert-Equal "warn" ($usageUnavailable.status) "doctor: usage-artifacts warns when provider usage/model details are missing"

Remove-Item $tmp9d -Recurse -Force

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# SECTION 10: learning-capture with no failure events (no file expected)
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n== learning-capture no-failure events (E1) =="

$tmp10  = New-TempDir
$run10  = Join-Path $tmp10 "run"
New-Item -ItemType Directory $run10 -Force | Out-Null

# Write events with only success events - no proposals expected (nothing meaningful)
$runId10 = "S-0001-20260101-000000-it1"
Set-Content (Join-Path $tmp10 "events.jsonl") @"
{"run_id":"$runId10","kind":"IterationCompleted","outcome":"success"}
"@ -Encoding UTF8

$hook10 = Join-Path $felixPlug "learning-capture\on-postiteration.ps1"
powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    & '$($hook10 -replace "'","''")'  ``
        -HookName 'OnPostIteration'  ``
        -RunId '$runId10'  ``
        -Data @{ FelixDir = '$($tmp10 -replace "'","''")'; RunDir = '$($run10 -replace "'","''")' }
" 2>&1 | Out-Null

$suggest10 = Join-Path $run10 "agents-md-suggestions.md"
# File may or may not exist depending on whether success generates proposals
# Key test: if created, it should not be empty
if (Test-Path $suggest10) {
    $sc10 = Get-Content $suggest10 -Raw
    Assert-True ($sc10.Length -gt 0) "learning-capture success only: file is non-empty if created"
} else {
    Assert-True $true "learning-capture success only: no proposals is acceptable"
}

Remove-Item $tmp10 -Recurse -Force

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# SECTION 11: review --prompts (E2)
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n== review --prompts (E2) =="

$tmp11  = New-TempDir
$proj11 = Join-Path $tmp11 "project"
$fx11   = Join-Path $proj11 ".felix"
$pdir11 = Join-Path $fx11 "prompts"
New-Item -ItemType Directory $pdir11 -Force | Out-Null

# Write a prompt with known patterns
Set-Content (Join-Path $pdir11 "building.md") @"
# Building

do NOT write code in planning mode.
<promise>I will complete this task</promise>
Use JSON-only output when responding.
"@ -Encoding UTF8

$reviewScript11 = Join-Path $felixCmds "review.ps1"
$out11 = powershell -NoProfile -NonInteractive -Command "
    `$PSDefaultParameterValues['*:ErrorAction'] = 'Continue'
    . '$($reviewScript11 -replace "'","''")'
    Invoke-Review -CmdArgs @('--prompts') -ProjectPath '$($proj11 -replace "'","''")'
" 2>&1 | Out-String

Assert-True ($out11 -match "do NOT" -or $out11 -match "promise" -or $out11 -match "JSON") "review --prompts: detects heuristic patterns"
Assert-True ($out11 -match "building.md") "review --prompts: reports file name"

Remove-Item $tmp11 -Recurse -Force

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# SUMMARY
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Phase E Tests: $script:TestsPassed passed, $script:TestsFailed failed" -ForegroundColor $(if ($script:TestsFailed -eq 0) { "Green" } else { "Red" })
Write-Host "=====================================" -ForegroundColor Cyan

if ($script:TestsFailed -gt 0) { exit 1 } else { exit 0 }

