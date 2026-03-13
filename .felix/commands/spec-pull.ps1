
# ── spec-pull.ps1 ─────────────────────────────────────────────────────────────
# Invoke-SpecPull for `felix spec pull`
# Dot-sourced by spec.ps1

function Invoke-SpecPull {
    param(
        [switch]$DryRun,
        [switch]$Delete,
        [switch]$Force   # overwrite local files even if not tracked in manifest
    )

    # ── Load config ──────────────────────────────────────────────────────────
    $configPath = Join-Path $RepoRoot ".felix\config.json"
    if (-not (Test-Path $configPath)) {
        Write-Error "No .felix/config.json found. Run 'felix setup' first."
        exit 1
    }

    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    $baseUrl = if ($env:FELIX_SYNC_URL) { $env:FELIX_SYNC_URL } else { $config.sync.base_url }
    $apiKey = if ($env:FELIX_SYNC_KEY) { $env:FELIX_SYNC_KEY } else { $config.sync.api_key }

    if (-not $baseUrl) {
        Write-Error "sync.base_url not set in .felix/config.json. Run 'felix setup' to configure."
        exit 1
    }
    if (-not $apiKey) {
        Write-Error "sync.api_key not set in .felix/config.json or FELIX_SYNC_KEY env var. Run 'felix setup' to add your API key."
        exit 1
    }

    $headers = @{ Authorization = "Bearer $apiKey" }

    # ── Load local manifest ──────────────────────────────────────────────────
    $manifestPath = Join-Path $RepoRoot ".felix\spec-manifest.json"
    $manifest = @{ files = @{} }
    if (Test-Path $manifestPath) {
        try {
            $raw = Get-Content $manifestPath -Raw | ConvertFrom-Json
            if ($raw.files) {
                $raw.files.PSObject.Properties | ForEach-Object {
                    $manifest.files[$_.Name] = $_.Value
                }
            }
        }
        catch {
            Write-Warning "Could not read spec-manifest.json, treating as empty: $_"
        }
    }

    # ── POST /api/sync/specs/check ───────────────────────────────────────────
    Write-Host ""
    Write-Host "Checking for changes..." -ForegroundColor Cyan

    $checkBody = @{ files = $manifest.files } | ConvertTo-Json -Depth 5
    try {
        $checkResult = Invoke-RestMethod `
            -Uri "$baseUrl/api/sync/specs/check" `
            -Method POST `
            -Headers $headers `
            -ContentType "application/json" `
            -Body $checkBody `
            -TimeoutSec 15 `
            -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to check specs with server: $_"
        exit 1
    }

    $toDownload = $checkResult.download
    $toDelete = $checkResult.delete

    if ($toDownload.Count -eq 0 -and $toDelete.Count -eq 0) {
        Write-Host "Already up to date." -ForegroundColor Green
        Write-Host ""
        return
    }

    Write-Host "  $($toDownload.Count) file(s) to download, $($toDelete.Count) file(s) to remove" -ForegroundColor Gray
    Write-Host ""

    $specsDir = Join-Path $RepoRoot "specs"
    $newFileCount = 0

    # ── Download changed files ───────────────────────────────────────────────
    foreach ($entry in $toDownload) {
        $relPath = $entry.path
        $destPath = Join-Path $RepoRoot ($relPath -replace '/', '\')

        if ($DryRun) {
            $action = if (Test-Path $destPath) { "update" } else { "download" }
            Write-Host "  [DRY-RUN] Would $action`: $relPath" -ForegroundColor Yellow
            continue
        }

        # Guard: untracked local file - skip unless --force
        if ((Test-Path $destPath) -and -not $manifest.files.ContainsKey($relPath) -and -not $Force) {
            Write-Host "  [SKIP] $relPath (local file not in manifest; use --force to overwrite)" -ForegroundColor DarkYellow
            continue
        }

        $destDir = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        try {
            $encodedPath = [Uri]::EscapeDataString($relPath)
            Invoke-RestMethod `
                -Uri "$baseUrl/api/sync/specs/file?path=$encodedPath" `
                -Method GET `
                -Headers $headers `
                -OutFile $destPath `
                -TimeoutSec 30 `
                -ErrorAction Stop

            $actualHash = (Get-FileHash $destPath -Algorithm SHA256).Hash.ToLower()
            $expectedHash = $entry.hash.ToLower()
            if ($actualHash -ne $expectedHash) {
                Write-Warning "Hash mismatch for $relPath (expected $expectedHash, got $actualHash)"
            }

            $isNew = -not $manifest.files.ContainsKey($relPath)
            $manifest.files[$relPath] = $entry.hash
            if ($isNew) { $newFileCount++ }
            Write-Host "  [OK] $relPath" -ForegroundColor Green

            # Create .meta.json sidecar for new .md spec files (fallback only;
            # the server also sends a separate .meta.json entry with full content including status)
            if ($isNew -and $relPath -match 'specs/S-\d{4}[^/]*\.md$') {
                $metaRelPath = $relPath -replace '\.md$', '.meta.json'
                $metaPath = Join-Path $RepoRoot ($metaRelPath -replace '/', '\')
                if (-not (Test-Path $metaPath)) {
                    [ordered]@{
                        status     = 'planned'
                        priority   = 'medium'
                        tags       = @()
                        depends_on = @()
                        updated_at = (Get-Date -Format 'yyyy-MM-dd')
                    } | ConvertTo-Json -Depth 5 | Set-Content $metaPath -Encoding UTF8
                }
            }
        }
        catch {
            Write-Warning "Failed to download $relPath`: $_"
        }
    }

    # ── Delete orphaned files ────────────────────────────────────────────────
    foreach ($relPath in $toDelete) {
        if ($DryRun) {
            Write-Host "  [DRY-RUN] Would delete: $relPath" -ForegroundColor Yellow
            continue
        }

        if ($Delete) {
            $destPath = Join-Path $RepoRoot ($relPath -replace '/', '\')
            if (Test-Path $destPath) {
                Remove-Item $destPath -Force
                Write-Host "  [DELETED] $relPath" -ForegroundColor DarkYellow
            }
            $manifest.files.Remove($relPath)
        }
        else {
            Write-Host "  [SKIPPED] $relPath (pass --delete to remove)" -ForegroundColor Gray
        }
    }

    # ── Save manifest ────────────────────────────────────────────────────────
    if (-not $DryRun) {
        $manifestData = [ordered]@{
            synced_at = (Get-Date -Format "o")
            files     = $manifest.files
        }
        $manifestData | ConvertTo-Json -Depth 5 | Set-Content $manifestPath -Encoding UTF8
    }

    Write-Host ""
    if ($DryRun) {
        Write-Host "Dry run complete. No files were changed." -ForegroundColor Yellow
    }
    else {
        Write-Host "Spec pull complete." -ForegroundColor Green
        if ($newFileCount -gt 0) {
            Write-Host ""
            Write-Host "Hint: $newFileCount new spec file(s) downloaded. Run 'felix spec fix' to register them in requirements.json." -ForegroundColor DarkCyan
        }
    }
    Write-Host ""
}
