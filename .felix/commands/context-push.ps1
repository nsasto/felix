
# ── context-push.ps1 ──────────────────────────────────────────────────────────
# Invoke-ContextPush for `felix context push`
# Dot-sourced by context.ps1

function Invoke-ContextPush {
    param(
        [switch]$DryRun,
        [switch]$Force   # push even if hash matches (re-upload unchanged files)
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
            -Headers @{ Authorization = "Bearer $apiKey" } `
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

    # ── File → column map ─────────────────────────────────────────────────────
    $fileMap = [ordered]@{
        "README.md"  = "readme"
        "CONTEXT.md" = "context"
        "AGENTS.md"  = "agents"
    }

    # ── Collect changed files ─────────────────────────────────────────────────
    Write-Host ""
    Write-Host "=== felix context push ===" -ForegroundColor Cyan
    Write-Host "Project: $projectId" -ForegroundColor Gray
    Write-Host ""

    $payload = @{}

    foreach ($fileName in $fileMap.Keys) {
        $column = $fileMap[$fileName]
        $filePath = Join-Path $RepoRoot $fileName

        if (-not (Test-Path $filePath)) {
            Write-Host "  [SKIP] $fileName (file not found)" -ForegroundColor DarkYellow
            continue
        }

        $currentHash = (Get-FileHash $filePath -Algorithm SHA256).Hash.ToLower()
        $cachedHash = $hashes[$fileName]

        if (-not $Force -and $cachedHash -eq $currentHash) {
            Write-Host "  [SKIP] $fileName (unchanged)" -ForegroundColor Gray
            continue
        }

        $content = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($filePath))
        $payload[$column] = $content
        $hashes[$fileName] = $currentHash

        if ($DryRun) {
            Write-Host "  [DRY-RUN] Would push: $fileName → $column" -ForegroundColor Yellow
        }
        else {
            Write-Host "  [PUSH] $fileName" -ForegroundColor Green
        }
    }

    if ($payload.Count -eq 0) {
        Write-Host "Nothing to push." -ForegroundColor Green
        Write-Host ""
        return
    }

    if ($DryRun) {
        Write-Host ""
        Write-Host "Dry-run complete — no changes sent." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # ── PATCH /api/projects/{id}/manifest ────────────────────────────────────
    $bodyJson = $payload | ConvertTo-Json -Depth 5
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
    try {
        Invoke-RestMethod `
            -Uri "$baseUrl/api/projects/$projectId/manifest" `
            -Method PATCH `
            -Headers $headers `
            -ContentType "application/json; charset=utf-8" `
            -Body $bodyBytes `
            -TimeoutSec 30 `
            -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "Failed to push manifest to server: $_"
        exit 1
    }

    # ── Save updated hashes ───────────────────────────────────────────────────
    $hashes | ConvertTo-Json -Depth 5 | Set-Content $hashPath -Encoding UTF8

    Write-Host ""
    Write-Host "Manifest pushed successfully." -ForegroundColor Green
    Write-Host ""
}
