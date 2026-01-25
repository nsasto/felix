#!/usr/bin/env pwsh
# Test Felix Backend and Frontend

Write-Host ""
Write-Host "Testing Felix..." -ForegroundColor Green
Write-Host ""

$allPassed = $true

# Test 1: Backend Health Check
Write-Host "[1/4] Backend health check..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/health" -UseBasicParsing -TimeoutSec 5
    if ($response.StatusCode -eq 200) {
        Write-Host "  ✅ Backend is healthy (port 8080)" -ForegroundColor Green
    }
    else {
        Write-Host "  ❌ Backend returned status $($response.StatusCode)" -ForegroundColor Red
        $allPassed = $false
    }
}
catch {
    Write-Host "  ❌ Backend not reachable: $_" -ForegroundColor Red
    Write-Host "     Make sure backend is running: cd app/backend && python main.py" -ForegroundColor Yellow
    $allPassed = $false
}

# Test 2: Frontend Check
Write-Host "[2/4] Frontend check..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -TimeoutSec 5
    if ($response.StatusCode -eq 200) {
        Write-Host "  ✅ Frontend is running (port 3000)" -ForegroundColor Green
    }
    else {
        Write-Host "  ❌ Frontend returned status $($response.StatusCode)" -ForegroundColor Red
        $allPassed = $false
    }
}
catch {
    Write-Host "  ❌ Frontend not reachable: $_" -ForegroundColor Red
    Write-Host "     Make sure frontend is running: cd app/frontend && npm run dev" -ForegroundColor Yellow
    $allPassed = $false
}

# Test 3: API Endpoints
Write-Host "[3/4] API endpoints..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/api/projects" -UseBasicParsing -TimeoutSec 5
    if ($response.StatusCode -eq 200) {
        Write-Host "  ✅ Projects API working" -ForegroundColor Green
    }
    else {
        Write-Host "  ❌ Projects API returned status $($response.StatusCode)" -ForegroundColor Red
        $allPassed = $false
    }
}
catch {
    Write-Host "  ❌ Projects API failed: $_" -ForegroundColor Red
    $allPassed = $false
}

# Test 4: CORS Configuration
Write-Host "[4/4] CORS configuration..." -ForegroundColor Cyan
try {
    $headers = @{
        "Origin" = "http://localhost:3000"
    }
    $response = Invoke-WebRequest -Uri "http://localhost:8080/health" -Method OPTIONS -Headers $headers -UseBasicParsing -TimeoutSec 5
    $corsHeader = $response.Headers["Access-Control-Allow-Origin"]
    if ($corsHeader -eq "http://localhost:3000") {
        Write-Host "  ✅ CORS configured correctly" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠️  CORS header: $corsHeader" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  ⚠️  Could not verify CORS: $_" -ForegroundColor Yellow
}

Write-Host ""
if ($allPassed) {
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "All tests passed! ✅" -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Felix is ready to use:" -ForegroundColor Cyan
    Write-Host "  → Open http://localhost:3000 in your browser" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}
else {
    Write-Host "=====================================" -ForegroundColor Red
    Write-Host "Some tests failed ❌" -ForegroundColor Red
    Write-Host "=====================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Run .\start-felix.ps1 to start the services" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
