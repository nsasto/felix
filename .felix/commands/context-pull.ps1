
# ── context-pull.ps1 ──────────────────────────────────────────────────────────
# Invoke-ContextPull for `felix context pull`
# Dot-sourced by context.ps1

function Invoke-ContextPull {
    param(
        [switch]$DryRun,
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
        Write-Error "sync.api_key not set in .felix/config.json or FELIX_SYNC_KEY env var."
        exit 1
    }

    $headers = @{ Authorization = "Bearer $apiKey" }

    # ── Resolve project_id from server ───────────────────────────────────────
    $projectId = $null
    try {
        $allProjects = Invoke-RestMethod `
            -Uri "$baseUrl/api/projects" `
            -Method GET `
            -Headers $headers `
            -TimeoutSec 15 `
            -ErrorAction Stop
        $projectId = $allProjects[0].id
    }
    catch {
        Write-Error "Failed to resolve project from server: $_"
        exit 1
    }

    if (-not $projectId) {
        Write-Error "No project found on server. Register the project first."
        exit 1
    }

    # ── GET /api/projects/{id}/manifest ──────────────────────────────────────
    Write-Host ""
    Write-Host "=== felix context pull ===" -ForegroundColor Cyan
    Write-Host "Project: $projectId" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Fetching manifest from server..." -ForegroundColor Cyan

    $manifest = $null
    try {
        $manifest = Invoke-RestMethod `
            -Uri "$baseUrl/api/projects/$projectId/manifest" `
            -Method GET `
            -Headers $headers `
            -TimeoutSec 15 `
            -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to fetch manifest from server: $_"
        exit 1
    }

    # ── Load local hash cache ─────────────────────────────────────────────────
    $hashPath = Join-Path $RepoRoot ".felix\manifest-hashes.json"
    $hashes = @{}
    if (Test-Path $hashPath) {
        try {
            $raw = Get-Content $hashPath -Raw | ConvertFrom-Json
            $raw.PSObject.Properties | ForEach-Object { $hashes[$_.Name] = $_.Value }
        }
        catch {
            Write-Warning "Could not read manifest-hashes.json, treating as empty: $_"
        }
    }

    # ── Column → file map ─────────────────────────────────────────────────────
    $columnMap = [ordered]@{
        "readme"  = "README.md"
        "context" = "CONTEXT.md"
        "agents"  = "AGENTS.md"
    }

    $updatedCount = 0
    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    foreach ($column in $columnMap.Keys) {
        $fileName = $columnMap[$column]
        $content = $manifest.$column

        if ($null -eq $content) {
            Write-Host "  [SKIP] $fileName (not stored on server)" -ForegroundColor DarkYellow
            continue
        }

        $destPath = Join-Path $RepoRoot $fileName

        # Guard: existing local file not in our hash cache — skip unless --force
        if ((Test-Path $destPath) -and -not $hashes.ContainsKey($fileName) -and -not $Force) {
            Write-Host "  [SKIP] $fileName (local file not tracked; use --force to overwrite)" -ForegroundColor DarkYellow
            continue
        }

        # Server returns base64-encoded content (symmetric with push).
        # Decode to raw bytes — this bypasses PowerShell 5.1 / Invoke-RestMethod
        # charset mis-detection (PS5 reads UTF-8 JSON as Latin-1 when the server
        # doesn't include an explicit charset in Content-Type, causing double-encoding).
        $fileBytes = [Convert]::FromBase64String($content)

        # Hash the decoded bytes — must match the push hash (SHA256 of raw file bytes)
        $serverHash = [BitConverter]::ToString($sha256.ComputeHash($fileBytes)).Replace('-', '').ToLower()
        $cachedHash = $hashes[$fileName]   # hash we stored after last successful pull/push

        if (-not $Force -and $cachedHash -eq $serverHash) {
            Write-Host "  [SKIP] $fileName (up to date)" -ForegroundColor Gray
            continue
        }

        if ($DryRun) {
            $action = if (Test-Path $destPath) { "update" } else { "create" }
            Write-Host "  [DRY-RUN] Would $action`: $fileName" -ForegroundColor Yellow
            continue
        }

        # Write raw bytes — no BOM, no newline conversion, no encoding surprise
        [System.IO.File]::WriteAllBytes($destPath, $fileBytes)
        $hashes[$fileName] = $serverHash
        $updatedCount++
        Write-Host "  [OK] $fileName" -ForegroundColor Green
    }

    if ($DryRun) {
        Write-Host ""
        Write-Host "Dry-run complete — no files written." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # ── Save updated hashes ───────────────────────────────────────────────────
    if ($updatedCount -gt 0) {
        $hashes | ConvertTo-Json -Depth 5 | Set-Content $hashPath -Encoding UTF8
        Write-Host ""
        Write-Host "$updatedCount file(s) updated." -ForegroundColor Green
    }
    else {
        Write-Host ""
        Write-Host "Nothing pulled." -ForegroundColor Gray
    }
    Write-Host ""
}
