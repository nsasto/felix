#!/usr/bin/env pwsh
# Start Felix Backend and Frontend in separate terminals

Write-Host ""
Write-Host "Starting Felix..." -ForegroundColor Green
Write-Host ""

# Start Backend in new terminal
Write-Host "Starting Backend (http://localhost:8080)..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PSScriptRoot\app\backend'; python main.py"

# Wait a moment for backend to start
Start-Sleep -Seconds 3

# Start Frontend in new terminal
Write-Host "Starting Frontend (http://localhost:3000)..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PSScriptRoot\app\frontend'; npm run dev"

Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host "Felix is starting!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""
Write-Host "Backend API:  " -NoNewline -ForegroundColor Gray
Write-Host "http://localhost:8080" -ForegroundColor Yellow
Write-Host "API Docs:     " -NoNewline -ForegroundColor Gray
Write-Host "http://localhost:8080/docs" -ForegroundColor Yellow
Write-Host "Frontend UI:  " -NoNewline -ForegroundColor Gray
Write-Host "http://localhost:3000" -ForegroundColor Yellow
Write-Host ""
Write-Host "To stop: Press Ctrl+C in each terminal window." -ForegroundColor Gray
Write-Host ""
