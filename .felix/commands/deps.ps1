
function Invoke-Deps {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    if ($Args.Count -eq 0) {
        Write-Error "Usage: felix deps <requirement-id> [--check|--tree|--incomplete]"
        Write-Host "Examples:"
        Write-Host "  felix deps S-0018              Show dependencies of S-0018"
        Write-Host "  felix deps S-0018 --check      Check if dependencies are complete"
        Write-Host "  felix deps S-0018 --tree       Show full dependency tree"
        Write-Host "  felix deps --incomplete        List all requirements with incomplete dependencies"
        exit 1
    }

    $requirementId = $Args[0]
    $showTree = $false
    $checkOnly = $false
    $showIncomplete = $false

    # Parse flags
    for ($i = 1; $i -lt $Args.Count; $i++) {
        switch ($Args[$i]) {
            "--tree" { $showTree = $true }
            "--check" { $checkOnly = $true }
            "--incomplete" { $showIncomplete = $true }
        }
    }

    # Handle --incomplete flag (show all requirements with incomplete deps)
    if ($requirementId -eq "--incomplete") {
        $showIncomplete = $true
        $requirementId = $null
    }

    # Load requirements.json
    $requirementsFile = Join-Path $RepoRoot ".felix/requirements.json"
    if (-not (Test-Path $requirementsFile)) {
        Write-Error "requirements.json not found at $requirementsFile"
        exit 1
    }

    try {
        $requirementsData = Get-Content $requirementsFile -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error "Failed to parse requirements.json: $_"
        exit 1
    }

    # Build lookup by ID
    $requirementsById = @{}
    foreach ($req in $requirementsData.requirements) {
        $requirementsById[$req.id] = $req
    }

    # Show all incomplete if requested
    if ($showIncomplete) {
        Write-Host ""
        Write-Host "=== Requirements with Incomplete Dependencies ===" -ForegroundColor Cyan
        Write-Host ""

        $foundAny = $false
        foreach ($req in $requirementsData.requirements) {
            if ($req.depends_on -and $req.depends_on.Count -gt 0) {
                $incomplete = @()
                foreach ($depId in $req.depends_on) {
                    $depReq = $requirementsById[$depId]
                    if ($depReq -and $depReq.status -notin @("done", "complete")) {
                        $incomplete += "$depId ($($depReq.status))"
                    }
                    elseif (-not $depReq) {
                        $incomplete += "$depId (missing)"
                    }
                }

                if ($incomplete.Count -gt 0) {
                    $foundAny = $true
                    Write-Host "  $($req.id) - $($req.title)" -ForegroundColor Yellow
                    Write-Host "    Status: $($req.status)" -ForegroundColor Gray
                    Write-Host "    Incomplete dependencies: $($incomplete -join ', ')" -ForegroundColor Red
                    Write-Host ""
                }
            }
        }

        if (-not $foundAny) {
            Write-Host "  [OK] All requirements have complete dependencies" -ForegroundColor Green
        }
        Write-Host ""
        exit 0
    }

    # Validate requirement ID
    if ($requirementId -notmatch '^S-\d{4}$') {
        Write-Error "Invalid requirement ID format. Expected S-NNNN (e.g., S-0001)"
        exit 1
    }

    # Find requirement
    $requirement = $requirementsById[$requirementId]
    if (-not $requirement) {
        Write-Error "Requirement $requirementId not found in requirements.json"
        exit 1
    }

    Write-Host ""
    Write-Host "=== Dependency Analysis: $requirementId ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Requirement: $($requirement.title)" -ForegroundColor White
    Write-Host "Status: $($requirement.status)" -ForegroundColor $(if ($requirement.status -in @("done", "complete")) { "Green" } else { "Yellow" })
    Write-Host ""

    # Check if requirement has dependencies
    if (-not $requirement.depends_on -or $requirement.depends_on.Count -eq 0) {
        Write-Host "[OK] No dependencies" -ForegroundColor Green
        Write-Host ""
        exit 0
    }

    # Analyze dependencies
    Write-Host "Dependencies ($($requirement.depends_on.Count)):" -ForegroundColor Yellow
    Write-Host ""

    $allComplete = $true
    $incompleteDeps = @()
    $missingDeps = @()

    foreach ($depId in $requirement.depends_on) {
        $depReq = $requirementsById[$depId]
        
        if (-not $depReq) {
            Write-Host "  [ERROR] $depId - MISSING from requirements.json" -ForegroundColor Red
            $missingDeps += $depId
            $allComplete = $false
            continue
        }

        $isComplete = $depReq.status -in @("done", "complete")
        $statusColor = if ($isComplete) { "Green" } else { "Yellow" }
        $statusIcon = if ($isComplete) { "[OK]" } else { "[WARN]" }

        Write-Host "  $statusIcon $depId - $($depReq.title)" -ForegroundColor $statusColor
        Write-Host "        Status: $($depReq.status)" -ForegroundColor Gray
        Write-Host "        Priority: $($depReq.priority)" -ForegroundColor Gray

        if (-not $isComplete) {
            $allComplete = $false
            $incompleteDeps += $depId
        }

        # Show dependency tree if requested
        if ($showTree -and $depReq.depends_on -and $depReq.depends_on.Count -gt 0) {
            Write-Host "        Depends on: $($depReq.depends_on -join ', ')" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    # Summary
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    if ($allComplete) {
        Write-Host "[OK] All dependencies are complete" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "[WARN] Incomplete dependencies detected" -ForegroundColor Yellow
        if ($incompleteDeps.Count -gt 0) {
            Write-Host "  Incomplete: $($incompleteDeps -join ', ')" -ForegroundColor Yellow
        }
        if ($missingDeps.Count -gt 0) {
            Write-Host "  Missing: $($missingDeps -join ', ')" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "Consider completing dependencies before starting $requirementId" -ForegroundColor Gray
        exit 1
    }
}
