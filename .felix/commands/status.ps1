
function Invoke-Status {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    $requirementId = if ($Args -and $Args.Count -gt 0) { $Args[0] } else { $null }

    # Load requirements.json
    $requirementsPath = "$RepoRoot\.felix\requirements.json"
    if (-not (Test-Path $requirementsPath)) {
        Write-Error "Requirements file not found: $requirementsPath"
        exit 1
    }

    $requirements = Get-Content $requirementsPath -Raw | ConvertFrom-Json

    if ($requirementId) {
        # Show specific requirement
        $req = $requirements.requirements | Where-Object { $_.id -eq $requirementId }
        if (-not $req) {
            Write-Error "Requirement not found: $requirementId"
            exit 1
        }

        if ($Format -eq "json") {
            $req | ConvertTo-Json -Depth 10
        } 
        else {
            Write-Host ""
            Write-Host "Requirement: $($req.id)" -ForegroundColor Cyan
            Write-Host "Title: $($req.title)"
            
            $statusColor = switch ($req.status) {
                "done" { "Green" }
                "complete" { "Green" }
                "in-progress" { "Yellow" }
                "planned" { "Cyan" }
                "blocked" { "Red" }
                default { "White" }
            }
            Write-Host "Status: $($req.status)" -ForegroundColor $statusColor
            Write-Host "Priority: $($req.priority)"
            
            # Check dependencies
            if ($req.depends_on -and $req.depends_on.Count -gt 0) {
                Write-Host "Dependencies: $($req.depends_on -join ', ')" -ForegroundColor Gray
                
                # Build lookup for dependency checking
                $requirementsById = @{}
                foreach ($r in $requirements.requirements) {
                    $requirementsById[$r.id] = $r
                }
                
                # Check for incomplete dependencies
                $incompleteDeps = @()
                $missingDeps = @()
                foreach ($depId in $req.depends_on) {
                    $depReq = $requirementsById[$depId]
                    if (-not $depReq) {
                        $missingDeps += $depId
                    }
                    elseif ($depReq.status -notin @("done", "complete")) {
                        $incompleteDeps += "$depId ($($depReq.status))"
                    }
                }
                
                if ($incompleteDeps.Count -gt 0) {
                    Write-Host ""
                    Write-Host "[WARN] Incomplete dependencies:" -ForegroundColor Yellow
                    foreach ($dep in $incompleteDeps) {
                        Write-Host "  - $dep" -ForegroundColor Yellow
                    }
                }
                
                if ($missingDeps.Count -gt 0) {
                    Write-Host ""
                    Write-Host "[ERROR] Missing dependencies:" -ForegroundColor Red
                    foreach ($dep in $missingDeps) {
                        Write-Host "  - $dep" -ForegroundColor Red
                    }
                }
            }
            
            if ($req.spec_path) {
                Write-Host "Spec: $($req.spec_path)" -ForegroundColor Gray
            }
            if ($req.last_run_id) {
                Write-Host "Last Run: $($req.last_run_id)" -ForegroundColor Gray
            }
            Write-Host ""
        }
    } 
    else {
        # Show summary
        if ($Format -eq "json") {
            $requirements.requirements | ConvertTo-Json -Depth 10
        } 
        else {
            Write-Host ""
            Write-Host "Felix Requirements Status" -ForegroundColor Cyan
            Write-Host "Repository: $RepoRoot" -ForegroundColor Gray
            Write-Host ""
            
            $byStatus = $requirements.requirements | Group-Object status
            foreach ($group in $byStatus) {
                $color = switch ($group.Name) {
                    "done" { "Green" }
                    "complete" { "Green" }
                    "in-progress" { "Yellow" }
                    "in_progress" { "Yellow" }
                    "planned" { "Cyan" }
                    "blocked" { "Red" }
                    default { "White" }
                }
                Write-Host "$($group.Name): $($group.Count)" -ForegroundColor $color
            }
            Write-Host ""
        }
    }
}
