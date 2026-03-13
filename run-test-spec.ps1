$ErrorActionPreference = 'Stop'

if (Test-Path ".env") {
    # Load simple KEY=VALUE entries from repo root .env.
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^\s*$' -or $_ -match '^\s*#') { return }
        $pair = $_ -split '=', 2
        if ($pair.Count -ne 2) { return }
        $name = $pair[0].Trim()
        $value = $pair[1].Trim()
        if ($value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        } elseif ($value.StartsWith("'") -and $value.EndsWith("'")) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        Set-Item -Path ("Env:{0}" -f $name) -Value $value
    }
}

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
