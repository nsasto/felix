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
    if ($Force) {
        Write-Host "  [force] Requesting server-side create/update for all specs, including missing requirement mappings." -ForegroundColor Yellow
    }

    # In CI or redirected output, prefer plain progress lines over Write-Progress bars.
    $usePlainProgress = (($env:CI -eq "true") -or ($env:GITHUB_ACTIONS -eq "true") -or [Console]::IsOutputRedirected)

    # Build upload batch
    $files = @()
    $totalFiles = $specFiles.Count
    $preparedCount = 0
    foreach ($file in $specFiles) {
        $preparedCount++
        $percent = [Math]::Floor(($preparedCount / $totalFiles) * 100)
        if ($usePlainProgress) {
            if ($preparedCount -eq 1 -or $preparedCount -eq $totalFiles -or ($preparedCount % 25 -eq 0)) {
                Write-Host ("  [prepare] {0}/{1} ({2}%) {3}" -f $preparedCount, $totalFiles, $percent, $file.Name) -ForegroundColor DarkGray
            }
        }
        else {
            Write-Progress -Activity "Preparing spec upload" -Status "$preparedCount/$totalFiles $($file.Name)" -PercentComplete $percent
        }

        $relPath = "specs/" + ($file.FullName.Substring($specsDir.Length).TrimStart('\', '/').Replace('\', '/'))
        $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($file.FullName))
        $files += @{ path = $relPath; content = $b64 }
    }
    if (-not $usePlainProgress) {
        Write-Progress -Activity "Preparing spec upload" -Completed
    }

    if ($DryRun) {
        Write-Host ""
        Write-Host "  [dry-run] Would upload:" -ForegroundColor Yellow
        if ($Force) {
            Write-Host "  [dry-run] --force would request create-if-missing on the server (if supported)." -ForegroundColor Yellow
        }
        foreach ($f in $files) {
            Write-Host "    $($f.path)" -ForegroundColor Gray
        }
        Write-Host ""
        return
    }

    # Upload in chunks to avoid timeouts on large batches
    $chunkSize = if ($env:FELIX_SPEC_PUSH_CHUNK_SIZE) { [int]$env:FELIX_SPEC_PUSH_CHUNK_SIZE } else { 10 }
    $timeoutSec = if ($env:FELIX_SPEC_PUSH_TIMEOUT_SEC) { [int]$env:FELIX_SPEC_PUSH_TIMEOUT_SEC } else { 120 }
    $maxRetries = if ($env:FELIX_SPEC_PUSH_RETRIES) { [int]$env:FELIX_SPEC_PUSH_RETRIES } else { 2 }

    $totalChunks = [Math]::Ceiling($files.Count / $chunkSize)
    Write-Host "  Uploading in $totalChunks chunk(s) of up to $chunkSize specs (timeout ${timeoutSec}s per chunk)..." -ForegroundColor Gray

    $allResults = @()
    for ($ci = 0; $ci -lt $totalChunks; $ci++) {
        $start = $ci * $chunkSize
        $end = [Math]::Min($start + $chunkSize, $files.Count) - 1
        $chunk = $files[$start..$end]
        $chunkNum = $ci + 1

        $bodyObj = [ordered]@{ files = $chunk }
        if ($Force) {
            $bodyObj.force = $true
            $bodyObj.create_missing_requirements = $true
            $bodyObj.create_requirements_if_missing = $true
        }
        $body = $bodyObj | ConvertTo-Json -Depth 10 -Compress

        $attempt = 0
        $success = $false
        while ($attempt -le $maxRetries -and -not $success) {
            $attempt++
            $label = "chunk $chunkNum/$totalChunks ($($chunk.Count) specs)"
            if ($attempt -gt 1) {
                $delay = $attempt * 5
                Write-Host "  [retry] Attempt $attempt for $label in ${delay}s..." -ForegroundColor Yellow
                Start-Sleep -Seconds $delay
            } else {
                Write-Host "  [upload] $label" -ForegroundColor DarkGray
            }
            try {
                $result = Invoke-RestMethod `
                    -Uri "$baseUrl/api/sync/specs/upload" `
                    -Method POST `
                    -Headers $headers `
                    -ContentType "application/json; charset=utf-8" `
                    -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) `
                    -TimeoutSec $timeoutSec `
                    -ErrorAction Stop
                if ($result.results) {
                    $allResults += @($result.results)
                }
                $success = $true
            }
            catch {
                if ($attempt -gt $maxRetries) {
                    Write-Error "Failed to upload $label after $attempt attempt(s): $_"
                    exit 1
                }
                Write-Host "  [warn] $label failed: $_ (will retry)" -ForegroundColor Yellow
            }
        }
    }

    # Report results
    $uploaded = 0
    $failed = 0
    $missingServerRequirementCount = 0
    $forceCreateNotHonoredCount = 0
    Write-Host ""
    $resultCount = $allResults.Count
    $processedResults = 0
    foreach ($r in $allResults) {
        $processedResults++
        if ($resultCount -gt 0) {
            $percent = [Math]::Floor(($processedResults / $resultCount) * 100)
            if ($usePlainProgress) {
                if ($processedResults -eq 1 -or $processedResults -eq $resultCount -or ($processedResults % 25 -eq 0)) {
                    Write-Host ("  [result]  {0}/{1} ({2}%) {3}" -f $processedResults, $resultCount, $percent, $r.path) -ForegroundColor DarkGray
                }
            }
            else {
                Write-Progress -Activity "Processing upload results" -Status "$processedResults/$resultCount $($r.path)" -PercentComplete $percent
            }
        }

        if ($r.uploaded) {
            Write-Host "  [OK] $($r.path)" -ForegroundColor Green
            $uploaded++
        }
        else {
            $errorText = [string]$r.error
            if ($errorText) {
                # Normalize mojibake seen in some terminals when server returns UTF-8 punctuation.
                $errorText = $errorText -replace 'â\?\?', '-'
                if ($errorText -match 'No requirement found with this spec_path') {
                    $missingServerRequirementCount++
                    if ($Force) {
                        $forceCreateNotHonoredCount++
                    }
                    $errorText = 'No matching requirement for this spec_path on the server project. Verify backend URL/API key project mapping, then bootstrap remote requirements.'
                }
            }
            Write-Host "  [SKIP] $($r.path): $errorText" -ForegroundColor Yellow
            $failed++
        }
    }
    if (-not $usePlainProgress) {
        Write-Progress -Activity "Processing upload results" -Completed
    }

    Write-Host ""
    if ($failed -eq 0) {
        Write-Host "Spec push complete. $uploaded file(s) uploaded." -ForegroundColor Green
    }
    else {
        Write-Host "Spec push complete. $uploaded uploaded, $failed skipped." -ForegroundColor Yellow
        if ($Force -and $forceCreateNotHonoredCount -gt 0) {
            Write-Host "Server did not create $forceCreateNotHonoredCount missing requirement mapping(s) despite --force." -ForegroundColor Yellow
            Write-Host "This backend may not support create-if-missing in spec upload yet." -ForegroundColor Gray
        }
        if ($missingServerRequirementCount -eq $failed -and $failed -gt 0) {
            Write-Host "All skipped specs are missing requirement rows on the server project (local files exist)." -ForegroundColor Gray
            Write-Host "Check FELIX_SYNC_URL + API key project mapping, then bootstrap requirements on the backend." -ForegroundColor Gray
            Write-Host "Tip: 'felix spec fix' updates local requirements.json only; it does not create remote requirement rows." -ForegroundColor Gray
        }
        else {
            Write-Host "Skipped specs may not have matching requirements in the DB yet." -ForegroundColor Gray
            Write-Host "Run 'felix spec fix' then retry." -ForegroundColor Gray
        }
    }
    Write-Host ""
}