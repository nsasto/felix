$reqId = "ec11315f-db18-4ac9-8e6d-e4e71ac13318"
$projectId = "00000000-0000-0000-0000-000000000001"

Write-Host "`n=== Testing Runs API ===" -ForegroundColor Cyan

# Test 1: Get all runs (no filter)
Write-Host "`n1. All runs (limit 5):" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Uri "http://localhost:8080/api/agents/runs?limit=5" -Method Get
    Write-Host "  Count: $($result.count)" -ForegroundColor Green
    Write-Host "  First run ID: $($result.runs[0].id)" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Filter by requirement_id
Write-Host "`n2. Runs for S-0000 (requirement_id=$reqId):" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Uri "http://localhost:8080/api/agents/runs?requirement_id=$reqId&limit=5" -Method Get
    Write-Host "  Count: $($result.count)" -ForegroundColor Green
    if ($result.count -gt 0) {
        Write-Host "  First run:" -ForegroundColor Green
        Write-Host "    ID: $($result.runs[0].id)" -ForegroundColor Gray
        Write-Host "    Status: $($result.runs[0].status)" -ForegroundColor Gray
        Write-Host "    Requirement ID: $($result.runs[0].requirement_id)" -ForegroundColor Gray
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Check requirements API
Write-Host "`n3. Checking requirements API for S-0000:" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Uri "http://localhost:8080/api/projects/$projectId/requirements" -Method Get
    $s0000 = $result.requirements | Where-Object { $_.code -eq 'S-0000' }
    if ($s0000) {
        Write-Host "  Found S-0000:" -ForegroundColor Green
        Write-Host "    ID: $($s0000.id)" -ForegroundColor Gray
        Write-Host " Code: $($s0000.code)" -ForegroundColor Gray
        Write-Host "    Title: $($s0000.title)" -ForegroundColor Gray
        
        # Compare IDs
        if ($s0000.id -eq $reqId) {
            Write-Host "  [OK] ID matches run requirement_id" -ForegroundColor Green
        } else {
            Write-Host "  [BAD] ID MISMATCH! Expected $reqId, got $($s0000.id)" -ForegroundColor Red
        }
    } else {
        Write-Host "  S-0000 not found!" -ForegroundColor Red
    }
} catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
