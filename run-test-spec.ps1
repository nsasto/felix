$ErrorActionPreference = 'Stop'
write-host "================================" -ForegroundColor Green
write-host "Resetting test spec: s-0000" -ForegroundColor Green
write-host "================================" -ForegroundColor Green
write-host ""
felix spec status s-0000 planned
Start-Sleep -Milliseconds 500
Write-Host "================================" -ForegroundColor Green
Write-Host "Running test spec: s-0000" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
write-Host ""
felix run s-0000 --sync -Verbose
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
