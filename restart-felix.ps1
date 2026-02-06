#!/usr/bin/env pwsh
<#
.SYNOPSIS
Restart Felix services by killing all related processes and starting fresh

.DESCRIPTION
Stops all Python/Node processes related to Felix (backend/frontend),
waits for clean shutdown, then starts both services in new terminal windows.

.EXAMPLE
.\restart-felix.ps1
#>

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "  Felix Service Restart" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

Write-Host "`n[1/3] Stopping all Felix processes..." -ForegroundColor Yellow

# Kill backend processes (Python/Uvicorn)
$backendProcesses = Get-Process -ErrorAction SilentlyContinue | Where-Object { 
    ($_.ProcessName -match 'python|py') -and 
    ($_.Path -match 'Felix' -or $_.CommandLine -match 'Felix|main\.py|uvicorn')
}

if ($backendProcesses) {
    foreach ($proc in $backendProcesses) {
        Write-Host "   Killing Backend: $($proc.ProcessName) (PID $($proc.Id))" -ForegroundColor Red
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Host "   No backend processes found" -ForegroundColor Gray
}

# Kill frontend processes (Node/Vite)
$frontendProcesses = Get-Process -ErrorAction SilentlyContinue | Where-Object { 
    ($_.ProcessName -match 'node') -and 
    ($_.Path -match 'Felix' -or $_.CommandLine -match 'Felix|vite|npm')
}

if ($frontendProcesses) {
    foreach ($proc in $frontendProcesses) {
        Write-Host "   Killing Frontend: $($proc.ProcessName) (PID $($proc.Id))" -ForegroundColor Red
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Host "   No frontend processes found" -ForegroundColor Gray
}

# Wait for processes to fully terminate
Write-Host "`n[2/3] Waiting for clean shutdown..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

# Verify ports are free
$port8080 = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
$port3000 = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue

if ($port8080) {
    Write-Host "   Warning: Port 8080 still in use (PID $($port8080.OwningProcess))" -ForegroundColor Yellow
}
if ($port3000) {
    Write-Host "   Warning: Port 3000 still in use (PID $($port3000.OwningProcess))" -ForegroundColor Yellow
}

Write-Host "`n[3/3] Starting Felix services..." -ForegroundColor Green

# Get project root
$projectRoot = $PSScriptRoot

# Start backend in new window
Write-Host "`n   Starting Backend (http://localhost:8080)..." -ForegroundColor Cyan
$backendPath = Join-Path $projectRoot "app\backend"

Start-Process powershell -ArgumentList @(
    '-NoExit',
    '-Command',
    "Set-Location '$backendPath'; Write-Host '=== Felix Backend ===' -ForegroundColor Cyan; if (Test-Path .venv\Scripts\Activate.ps1) { & .\.venv\Scripts\Activate.ps1 }; python main.py"
)

# Wait for backend to initialize
Start-Sleep -Seconds 3

# Start frontend in new window
Write-Host "   Starting Frontend (http://localhost:3000)..." -ForegroundColor Cyan
$frontendPath = Join-Path $projectRoot "app\frontend"

Start-Process powershell -ArgumentList @(
    '-NoExit',
    '-Command',
    "Set-Location '$frontendPath'; Write-Host '=== Felix Frontend ===' -ForegroundColor Cyan; npm run dev"
)

Write-Host "`n==================================================" -ForegroundColor Green
Write-Host "   Felix Services Started" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Green

Write-Host "`nService URLs:" -ForegroundColor White
Write-Host "  Frontend:  http://localhost:3000" -ForegroundColor Cyan
Write-Host "  Backend:   http://localhost:8080" -ForegroundColor Cyan
Write-Host "  API Docs:  http://localhost:8080/docs" -ForegroundColor Cyan

Write-Host "`n Wait 10-15 seconds for services to fully initialize" -ForegroundColor Yellow
Write-Host "   Then open http://localhost:3000 in your browser" -ForegroundColor Yellow

Write-Host "`nNext Steps:" -ForegroundColor White
Write-Host "  1. Open browser to http://localhost:3000" -ForegroundColor Gray
Write-Host "  2. Click 'Add Project' button" -ForegroundColor Gray
Write-Host "  3. Browse to: $projectRoot" -ForegroundColor Gray
Write-Host "  4. Kanban should load requirements from felix/requirements.json" -ForegroundColor Gray

Write-Host "`n Ready!" -ForegroundColor Green
