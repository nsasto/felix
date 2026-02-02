# Run FelixTrayApp
$exePath = Join-Path $PSScriptRoot "bin\Debug\net8.0-windows10.0.22621.0\FelixTrayApp.exe"

if (Test-Path $exePath) {
    Write-Host "Starting FelixTrayApp..." -ForegroundColor Green
    Start-Process $exePath
    Write-Host "App started. Look for the tray icon in your system tray." -ForegroundColor Cyan
} else {
    Write-Host "ERROR: FelixTrayApp.exe not found. Please build the project first:" -ForegroundColor Red
    Write-Host "  dotnet build" -ForegroundColor Yellow
}
