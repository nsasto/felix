#!/usr/bin/env pwsh
# Start Felix Backend and Frontend in separate terminals

Write-Host ""
Write-Host "Starting Felix..." -ForegroundColor Green
Write-Host ""

# Auto-detect and start PostgreSQL
Write-Host "Checking PostgreSQL..." -ForegroundColor Cyan
try {
    $psqlPath = Get-Command psql -ErrorAction Stop | Select-Object -ExpandProperty Source
    $pgBin = Split-Path $psqlPath
    $pgData = Join-Path (Split-Path $pgBin) "data"
    
    # Check if PostgreSQL is running
    $testConnection = & $psqlPath -U postgres -c "SELECT 1;" -t 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Starting PostgreSQL server..." -ForegroundColor Yellow
        $pgCtl = Join-Path $pgBin "pg_ctl.exe"
        if (Test-Path $pgCtl) {
            # Start with timeout, show output if it fails
            $startOutput = & $pgCtl -D $pgData start -w -t 10 -l "$pgData\logfile" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "PostgreSQL started" -ForegroundColor Green
            } else {
                Write-Host "Warning: pg_ctl exited with code $LASTEXITCODE" -ForegroundColor Yellow
                Write-Host "Output: $startOutput" -ForegroundColor Gray
                Write-Host "Continuing anyway..." -ForegroundColor Gray
            }
        } else {
            Write-Host "Warning: pg_ctl not found at $pgCtl" -ForegroundColor Yellow
        }
    } else {
        Write-Host "PostgreSQL already running" -ForegroundColor Green
    }
    
    # Set environment for backend
    $env:DATABASE_URL = "postgresql://postgres@localhost:5432/felix"
}
catch {
    Write-Host "PostgreSQL not found - backend will fail to start without it" -ForegroundColor Yellow
    Write-Host "  Install PostgreSQL or run: .\scripts\setup-db.ps1" -ForegroundColor Gray
}
Write-Host ""

# Start Backend in new terminal
Write-Host "Starting Backend (http://localhost:8080)..." -ForegroundColor Cyan
$backendCmd = "cd '$PSScriptRoot\app\backend'; `$env:DATABASE_URL='postgresql://postgres@localhost:5432/felix'; if (Test-Path .venv\Scripts\Activate.ps1) { & .\.venv\Scripts\Activate.ps1 }; python main.py"
Start-Process powershell -ArgumentList "-NoExit", "-Command", $backendCmd

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
