# Search result memoisation for felix search (Phase D3).
# Cache file: runs/<run-id>/search-cache.json
# Format: { "entries": { "<key>": { "result": <obj>, "ts": "<ISO>" } } }

function Get-SearchCacheKey {
    param(
        [string]$Query,
        [string]$Flags
    )
    $inputStr = "$Query|$Flags"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($inputStr)
    $sha1  = [System.Security.Cryptography.SHA1]::Create()
    $hash  = $sha1.ComputeHash($bytes)
    $sha1.Dispose()
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Get-SearchCache {
    param(
        [string]$RunDir,
        [string]$Key
    )
    $cachePath = Join-Path $RunDir "search-cache.json"
    if (-not (Test-Path $cachePath)) { return $null }
    try {
        $cache = Get-Content $cachePath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if (-not $cache -or -not $cache.entries) { return $null }
        $entry = $cache.entries.$Key
        if ($null -ne $entry) { return $entry.result }
    } catch { }
    return $null
}

function Set-SearchCache {
    param(
        [string]$RunDir,
        [string]$Key,
        [object]$Value
    )
    if (-not (Test-Path $RunDir)) { return }
    $cachePath = Join-Path $RunDir "search-cache.json"

    $cache = $null
    if (Test-Path $cachePath) {
        try {
            $cache = Get-Content $cachePath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        } catch { }
    }
    if (-not $cache) {
        $cache = [PSCustomObject]@{ entries = [PSCustomObject]@{} }
    }
    if (-not $cache.entries) {
        $cache | Add-Member -MemberType NoteProperty -Name "entries" -Value ([PSCustomObject]@{}) -Force
    }

    $entryObj = [PSCustomObject]@{
        result = $Value
        ts     = (Get-Date -Format "o")
    }
    $cache.entries | Add-Member -MemberType NoteProperty -Name $Key -Value $entryObj -Force
    $cache | ConvertTo-Json -Depth 10 | Set-Content $cachePath -Encoding UTF8
}

function Clear-SearchCache {
    param([string]$RunDir)
    $cachePath = Join-Path $RunDir "search-cache.json"
    if (Test-Path $cachePath) {
        Remove-Item $cachePath -Force -ErrorAction SilentlyContinue
    }
}
