
function Invoke-List {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    # Parse filters and flags
    $statusFilter = $null
    $priorityFilter = $null
    $blockedByIncompleteDeps = $false
    $withDeps = $false
    $tagFilter = $null
    
    for ($i = 0; $i -lt $Args.Count; $i++) {
        switch ($Args[$i]) {
            "--status" { $statusFilter = $Args[$i + 1]; $i++ }
            "--priority" { $priorityFilter = $Args[$i + 1]; $i++ }
            "--tags" { $tagFilter = $Args[$i + 1]; $i++ }
            "--blocked-by" { 
                if ($Args[$i + 1] -eq "incomplete-deps") {
                    $blockedByIncompleteDeps = $true
                }
                $i++
            }
            "--with-deps" { $withDeps = $true }
        }
    }

    # Load requirements.json
    $requirementsPath = "$RepoRoot\.felix\requirements.json"
    if (-not (Test-Path $requirementsPath)) {
        Write-Error "Requirements file not found: $requirementsPath"
        exit 1
    }

    $requirements = Get-Content $requirementsPath -Raw | ConvertFrom-Json
    
    # Build lookup for dependency checking
    $requirementsById = @{}
    foreach ($req in $requirements.requirements) {
        $requirementsById[$req.id] = $req
    }

    # Apply filters
    $filtered = $requirements.requirements
    
    if ($statusFilter) {
        $filtered = $filtered | Where-Object { $_.status -eq $statusFilter }
    }
    
    if ($priorityFilter) {
        $filtered = $filtered | Where-Object { $_.priority -eq $priorityFilter }
    }
    
    if ($tagFilter) {
        $tags = $tagFilter -split ','
        $filtered = $filtered | Where-Object { 
            $reqTags = $_.tags
            ($tags | Where-Object { $reqTags -contains $_ }).Count -gt 0
        }
    }
    
    if ($blockedByIncompleteDeps) {
        $filtered = $filtered | Where-Object {
            if ($_.depends_on -and $_.depends_on.Count -gt 0) {
                $hasIncomplete = $false
                foreach ($depId in $_.depends_on) {
                    $depReq = $requirementsById[$depId]
                    if (-not $depReq -or $depReq.status -notin @("done", "complete")) {
                        $hasIncomplete = $true
                        break
                    }
                }
                $hasIncomplete
            }
            else {
                $false
            }
        }
    }

    # Sort by ID for consistent ordering
    $filtered = $filtered | Sort-Object { $_.id }

    if ($Format -eq "json") {
        $filtered | ConvertTo-Json -Depth 10
    } 
    else {
        Write-Host ""
        Write-Host "Requirements:" -ForegroundColor Cyan
        
        # Show active filters
        $filters = @()
        if ($statusFilter) { $filters += "status=$statusFilter" }
        if ($priorityFilter) { $filters += "priority=$priorityFilter" }
        if ($tagFilter) { $filters += "tags=$tagFilter" }
        if ($blockedByIncompleteDeps) { $filters += "blocked-by=incomplete-deps" }
        
        if ($filters.Count -gt 0) {
            Write-Host "Filters: $($filters -join ', ')" -ForegroundColor Gray
        }
        Write-Host ""
        
        foreach ($req in $filtered) {
            $color = switch ($req.status) {
                "done" { "Green" }
                "complete" { "Green" }
                "in-progress" { "Yellow" }
                "planned" { "Cyan" }
                "blocked" { "Red" }
                default { "White" }
            }
            
            Write-Host "  $($req.id): $($req.title)" -ForegroundColor $color -NoNewline
            Write-Host " [$($req.status)]" -ForegroundColor Gray
            
            # Show dependencies if requested
            if ($withDeps -and $req.depends_on -and $req.depends_on.Count -gt 0) {
                Write-Host "    Depends on: " -NoNewline -ForegroundColor DarkGray
                $depStatuses = @()
                foreach ($depId in $req.depends_on) {
                    $depReq = $requirementsById[$depId]
                    if ($depReq) {
                        $depColor = if ($depReq.status -in @("done", "complete")) { "Green" } else { "Yellow" }
                        $depStatuses += "$depId ($($depReq.status))"
                    }
                    else {
                        $depStatuses += "$depId (missing)"
                    }
                }
                Write-Host ($depStatuses -join ', ') -ForegroundColor DarkGray
            }
        }
        
        Write-Host ""
        Write-Host "Total: $($filtered.Count)" -ForegroundColor Gray
        Write-Host ""
    }
}
