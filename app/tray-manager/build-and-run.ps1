# Build and Run FelixTrayApp
Write-Host "Building FelixTrayApp..." -ForegroundColor Cyan
dotnet build

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nBuild successful! Starting app..." -ForegroundColor Green
    & "$PSScriptRoot\run.ps1"
} else {
    Write-Host "`nBuild failed. Please fix errors above." -ForegroundColor Red
}
