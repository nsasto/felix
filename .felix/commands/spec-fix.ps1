
# ── spec-fix.ps1 ──────────────────────────────────────────────────────────────
# Helpers and Invoke-SpecFix for `felix spec fix`
# Dot-sourced by spec.ps1

function Get-NextAvailableSpecId {
    param([int]$StartFrom, [string]$SpecsDir)
    $nextId = $StartFrom + 1
    while (Test-Path (Join-Path $SpecsDir "S-$($nextId.ToString('0000'))*")) {
        $nextId++
    }
    return $nextId
}

# ── Invoke-SpecFix ────────────────────────────────────────────────────────────

function Invoke-SpecFix {
    param(
        [switch]$FixDuplicates
    )
    
    Write-Host ""
    Write-Host "=== Spec Fix Utility ===" -ForegroundColor Cyan
    Write-Host "Scanning specs folder and validating requirements.json..." -ForegroundColor Gray
    Write-Host ""
    
    $specsDir = Join-Path $RepoRoot "specs"
    $requirementsFile = Join-Path $RepoRoot ".felix\requirements.json"
    
    if (-not (Test-Path $specsDir)) {
        Write-Error "Specs directory not found: $specsDir"
        exit 1
    }
    
    # Load or create requirements.json
    $requirementsData = [PSCustomObject]@{ requirements = @() }
    if (Test-Path $requirementsFile) {
        try {
            $parsed = Get-Content $requirementsFile -Raw | ConvertFrom-Json
            # Normalize bare array format (legacy) to { requirements: [] } object
            if ($parsed -is [array]) {
                $requirementsData = [PSCustomObject]@{ requirements = $parsed }
            }
            else {
                $requirementsData = $parsed
            }
            Write-Host "[OK] Loaded requirements.json" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to parse requirements.json - will recreate"
            $requirementsData = [PSCustomObject]@{ requirements = @() }
        }
    }
    else {
        Write-Warning "requirements.json not found - will create new"
    }
    
    # Get all spec files
    $specFiles = Get-ChildItem -Path $specsDir -Filter "S-*.md" | Sort-Object Name
    Write-Host "Found $($specFiles.Count) spec files" -ForegroundColor Cyan
    Write-Host ""
    
    # Track changes
    $added = @()
    $updated = @()
    $orphaned = @()
    $errors = @()
    $duplicates = @()
    $fixed = @()
    $processedIds = @{}
    
    # Find max spec ID for duplicate renaming
    $allSpecIds = @()
    $tempFiles = Get-ChildItem -Path $specsDir -Filter "S-*.md"
    foreach ($f in $tempFiles) {
        if ($f.Name -match '^S-(\d{4})') {
            $allSpecIds += [int]$Matches[1]
        }
    }
    $maxSpecId = if ($allSpecIds.Count -gt 0) { ($allSpecIds | Measure-Object -Maximum).Maximum } else { 0 }
    
    # Build lookup of existing requirements
    $existingReqs = @{}
    foreach ($req in $requirementsData.requirements) {
        $reqHash = [ordered]@{
            id        = $req.id
            spec_path = $req.spec_path
            status    = $req.status
        }
        if ($req.commit_on_complete -eq $true) {
            $reqHash.commit_on_complete = $true
        }
        $existingReqs[$req.id] = $reqHash
    }
    
    # Process each spec file
    foreach ($specFile in $specFiles) {
        $fileName = $specFile.Name
        
        if ($fileName -match '^(S-\d{4})') {
            $reqId = $Matches[1]
            
            # Check for duplicate IDs
            if ($processedIds.ContainsKey($reqId)) {
                if ($FixDuplicates) {
                    $nextId = Get-NextAvailableSpecId -StartFrom $maxSpecId -SpecsDir $specsDir
                    $maxSpecId = $nextId
                    $newReqId = "S-$($nextId.ToString('0000'))"
                    $newFileName = $fileName -replace '^S-\d{4}', $newReqId
                    $oldPath = Join-Path $specsDir $fileName
                    $newPath = Join-Path $specsDir $newFileName
                    
                    try {
                        $useGit = $false
                        if (Test-Path (Join-Path $RepoRoot ".git")) {
                            $ErrorActionPreference = 'SilentlyContinue'
                            git mv $oldPath $newPath 2>$null
                            $ErrorActionPreference = 'Continue'
                            if ($LASTEXITCODE -eq 0) { $useGit = $true }
                        }
                        if (-not $useGit) {
                            Rename-Item -Path $oldPath -NewName $newFileName -ErrorAction Stop
                        }
                        Write-Host "  [FIX] Renamed duplicate $reqId -> $newReqId ($newFileName)" -ForegroundColor Cyan
                        $fixed += "$fileName -> $newFileName"
                        $reqId = $newReqId
                        $fileName = $newFileName
                        $specFile = Get-Item -Path $newPath
                    }
                    catch {
                        $errors += "Failed to rename $fileName : $_"
                        Write-Host "  [ERROR] Failed to rename $fileName - $_" -ForegroundColor Red
                        continue
                    }
                }
                else {
                    $duplicates += $fileName
                    Write-Host "  [WARN] Duplicate ID $reqId in $fileName (already processed $($processedIds[$reqId]))" -ForegroundColor Magenta
                    continue
                }
            }
            $processedIds[$reqId] = $fileName
            
            try {
                if ($existingReqs.ContainsKey($reqId)) {
                    $existing = $existingReqs[$reqId]
                    $relativePath = "specs/$fileName"
                    if ($existing.spec_path -ne $relativePath) {
                        $existing.spec_path = $relativePath
                        $updated += $reqId
                        Write-Host "  [UPDATE] $reqId - $fileName" -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "  [OK] $reqId - $fileName" -ForegroundColor Green
                    }
                }
                else {
                    $newReq = [ordered]@{
                        id        = $reqId
                        spec_path = "specs/$fileName"
                        status    = "draft"
                    }
                    $existingReqs[$reqId] = $newReq
                    $added += $reqId
                    Write-Host "  [ADD] $reqId - $fileName" -ForegroundColor Green
                }
                $existingReqs.Remove($reqId)
            }
            catch {
                $errors += "Failed to process $fileName : $_"
                Write-Host "  [ERROR] $fileName - $_" -ForegroundColor Red
            }
        }
        else {
            $errors += "Invalid filename format: $fileName"
            Write-Host "  [WARN] Invalid $fileName - not in S-NNNN format" -ForegroundColor Magenta
        }
    }
    
    # Check for orphaned entries
    if ($existingReqs.Count -gt 0) {
        foreach ($orphanedReq in $existingReqs.Values) {
            $orphaned += $orphanedReq.id
            Write-Host "  [ORPHAN] $($orphanedReq.id) - file not found: $($orphanedReq.spec_path)" -ForegroundColor Yellow
        }
    }
    
    # Prompt for default status if there are new specs to add
    $defaultStatus = "draft"
    if ($added.Count -gt 0) {
        Write-Host ""
        Write-Host "Found $($added.Count) new spec(s) not in requirements.json." -ForegroundColor Cyan
        Write-Host "What status should they default to?" -ForegroundColor Cyan
        Write-Host "  [1] draft       - spec exists but not ready for agent" -ForegroundColor Gray
        Write-Host "  [2] planned     - ready for agent to pick up" -ForegroundColor Gray
        Write-Host "  [3] in_progress - currently being worked on" -ForegroundColor Gray
        Write-Host "  [4] blocked     - waiting on something" -ForegroundColor Gray
        Write-Host "  [5] done        - already finished" -ForegroundColor Gray
        Write-Host "  [6] complete    - already finished" -ForegroundColor Gray
        Write-Host ""
        $choice = Read-Host "Enter choice [1-6] (default: 1 draft)"
        switch ($choice.Trim()) {
            "2" { $defaultStatus = "planned" }
            "3" { $defaultStatus = "in_progress" }
            "4" { $defaultStatus = "blocked" }
            "5" { $defaultStatus = "done" }
            "6" { $defaultStatus = "complete" }
            default { $defaultStatus = "draft" }
        }
        Write-Host ""
    }

    # Rebuild requirements array from spec files
    $allRequirements = @()
    foreach ($specFile in $specFiles) {
        if ($specFile.Name -match '^(S-\d{4})') {
            $reqId = $Matches[1]
            $origReq = $requirementsData.requirements | Where-Object { $_.id -eq $reqId }
            
            if ($origReq) {
                # Existing requirement - check .meta.json for a status override
                $metaPath = Join-Path $specsDir "$($specFile.BaseName).meta.json"
                $resolvedStatus = $origReq.status
                if (Test-Path $metaPath) {
                    try {
                        $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
                        if ($meta.status) { $resolvedStatus = $meta.status }
                    }
                    catch {}
                }
                $reqHash = [ordered]@{
                    id        = $origReq.id
                    spec_path = "specs/$($specFile.Name)"
                    status    = $resolvedStatus
                }
                if ($origReq.commit_on_complete -eq $true) {
                    $reqHash.commit_on_complete = $true
                }
                $allRequirements += $reqHash
            }
            else {
                # New requirement - check .meta.json for a status override
                $metaPath = Join-Path $specsDir "$($specFile.BaseName).meta.json"
                $resolvedStatus = $defaultStatus
                if (Test-Path $metaPath) {
                    try {
                        $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
                        if ($meta.status) { $resolvedStatus = $meta.status }
                    }
                    catch {}
                }
                $allRequirements += [ordered]@{
                    id        = $reqId
                    spec_path = "specs/$($specFile.Name)"
                    status    = $resolvedStatus
                }
                # Write .meta.json sidecar if it doesn't already exist
                if (-not (Test-Path $metaPath)) {
                    $meta = [ordered]@{
                        status     = $resolvedStatus
                        priority   = "medium"
                        tags       = @()
                        depends_on = @()
                        updated_at = (Get-Date -Format "yyyy-MM-dd")
                    }
                    $meta | ConvertTo-Json -Depth 5 | Set-Content $metaPath -Encoding UTF8
                }
            }
        }
    }
    
    # Sort requirements by ID
    $requirementsData.requirements = $allRequirements | Sort-Object id
    
    # Save requirements.json
    try {
        $json = $requirementsData | ConvertTo-Json -Depth 10 -Compress:$false
        $json = $json -replace ':\s*\{\s*\}', ': []'
        $json = $json -creplace '("(?:depends_on|tags)":\s*)"([^"]+)"', '$1["$2"]'
        Set-Content -Path $requirementsFile -Value $json -Encoding UTF8
        Write-Host ""
        Write-Host "[OK] Saved requirements.json" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to save requirements.json: $_"
        exit 1
    }
    
    # Report summary
    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Total specs:      $($specFiles.Count)" -ForegroundColor White
    Write-Host "Added:            $($added.Count)" -ForegroundColor Green
    Write-Host "Updated:          $($updated.Count)" -ForegroundColor Yellow
    if ($fixed.Count -gt 0) {
        Write-Host "Fixed:            $($fixed.Count)" -ForegroundColor Cyan
    }
    Write-Host "Duplicates:       $($duplicates.Count)" -ForegroundColor Magenta
    Write-Host "Orphaned:         $($orphaned.Count)" -ForegroundColor Yellow
    Write-Host "Errors:           $($errors.Count)" -ForegroundColor Red
    
    if ($fixed.Count -gt 0) {
        Write-Host ""
        Write-Host "[OK] Fixed duplicate specs:" -ForegroundColor Cyan
        foreach ($fix in $fixed) {
            Write-Host "  - $fix" -ForegroundColor Gray
        }
    }
    
    if ($duplicates.Count -gt 0) {
        Write-Host ""
        Write-Host "[WARN] Duplicate spec IDs found (skipped):" -ForegroundColor Magenta
        foreach ($file in $duplicates) {
            Write-Host "  - $file" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "To automatically rename duplicates, run:" -ForegroundColor Yellow
        Write-Host "  felix spec fix --fix-duplicates" -ForegroundColor Gray
    }
    
    if ($orphaned.Count -gt 0) {
        Write-Host ""
        Write-Host "[WARN] Orphaned entries (in requirements.json but file missing):" -ForegroundColor Yellow
        foreach ($id in $orphaned) {
            Write-Host "  - $id" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "To remove orphaned entries, delete them manually or run:" -ForegroundColor Gray
        foreach ($id in $orphaned) {
            Write-Host "  felix spec delete $id" -ForegroundColor Gray
        }
    }
    
    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "Errors encountered:" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host "  - $err" -ForegroundColor Gray
        }
        Write-Host ""
        exit 1
    }

    Write-Host ""
    exit 0
}
