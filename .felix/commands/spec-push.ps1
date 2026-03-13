# spec-push.ps1
# Invoke-SpecPush for `felix spec push`
# Dot-sourced by spec.ps1

function Invoke-SpecPush {
    param(
        [switch]$DryRun,
        [switch]$Force   # push even if content appears unchanged on server
    )

    # Load config
    $configPath = Join-Path $RepoRoot ".felix\config.json"
    if (-not (Test-Path $configPath)) {
        Write-Error "No .felix/config.json found. Run 'felix setup' first."
        exit 1
    }

    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    $baseUrl = if ($env:FELIX_SYNC_URL) { $env:FELIX_SYNC_URL } else { $config.sync.base_url }
    $apiKey  = if ($env:FELIX_SYNC_KEY)  { $env:FELIX_SYNC_KEY  } else { $config.sync.api_key }

    if (-not $baseUrl) {
        Write-Error "sync.base_url not set in .felix/config.json. Run 'felix setup' to configure."
        exit 1
    }
    if (-not $apiKey) {
        Write-Error "sync.api_key not set in .felix/config.json or FELIX_SYNC_KEY env var. Run 'felix setup' to add your API key."
        exit 1
    }

    $headers = @{ Authorization = "Bearer $apiKey" }

    # Discover local spec files
    $specsDir = Join-Path $RepoRoot "specs"
    if (-not (Test-Path $specsDir)) {
        Write-Error "No specs/ directory found at: $specsDir"
        exit 1
    }

    $specFiles = Get-ChildItem -Path $specsDir -Filter "*.md" -Recurse | Sort-Object FullName
    if ($specFiles.Count -eq 0) {
        Write-Host ""
        Write-Host "No spec files found in specs/" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "Pushing $($specFiles.Count) spec file(s) to server..." -ForegroundColor Cyan

    # Build upload batch
    $files = @()
    foreach ($file in $specFiles) {
        $relPath = "specs/" + ($file.FullName.Substring($specsDir.Length).TrimStart('\', '/').Replace('\', '/'))
        $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($file.FullName))
        $files += @{ path = $relPath; content = $b64 }
    }

    if ($DryRun) {
        Write-Host ""
        Write-Host "  [dry-run] Would upload:" -ForegroundColor Yellow
        foreach ($f in $files) {
            Write-Host "    $($f.path)" -ForegroundColor Gray
        }
        Write-Host ""
        return
    }

    # POST to /api/sync/specs/upload
    $body = @{ files = $files } | ConvertTo-Json -Depth 10 -Compress
    try {
        $result = Invoke-RestMethod `
            -Uri "$baseUrl/api/sync/specs/upload" `
            -Method POST `
            -Headers $headers `
            -ContentType "application/json; charset=utf-8" `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
            -TimeoutSec 60 `
            -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to upload specs: $_"
        exit 1
    }

    # Report results
    $uploaded = 0
    $failed   = 0
    Write-Host ""
    foreach ($r in $result.results) {
        if ($r.uploaded) {
            Write-Host "  [OK] $($r.path)" -ForegroundColor Green
            $uploaded++
        }
        else {
            Write-Host "  [SKIP] $($r.path): $($r.error)" -ForegroundColor Yellow
            $failed++
        }
    }

    Write-Host ""
    if ($failed -eq 0) {
        Write-Host "Spec push complete. $uploaded file(s) uploaded." -ForegroundColor Green
    }
    else {
        Write-Host "Spec push complete. $uploaded uploaded, $failed skipped." -ForegroundColor Yellow
        Write-Host "Skipped specs may not have matching requirements in the DB yet." -ForegroundColor Gray
        Write-Host "Run 'felix spec fix' then retry." -ForegroundColor Gray
    }
    Write-Host ""
}