<#
.SYNOPSIS
Felix requirement lease manager (Phase H2).
Provides atomic claim/release for parallel workers via filesystem lock files.

.DESCRIPTION
Lease files live at .felix/.locks/<requirement-id>.lock
Atomic claim uses New-Item -ItemType File with ErrorAction Stop - fails if file exists.

Lease JSON schema:
  {
    "worker_id":   "felix-w7@hostname",
    "run_id":      "S-0042-abc123",
    "claimed_at":  "2026-06-01T14:22:33Z",
    "lease_until": "2026-06-01T14:52:33Z",
    "pid":         12345
  }

TTL: 30 min default, refreshed every 5 min by running worker.
Expired lease -> reclaimable by any worker; expiry event emitted.
#>

$LEASE_TTL_MINUTES    = 30
$LEASE_REFRESH_MINUTES = 5

function Get-WorkerId {
    <#
    .SYNOPSIS
    Returns a stable worker ID for this process: "felix-<pid>@<hostname>".
    #>
    return "felix-$PID@$env:COMPUTERNAME"
}

function Get-LockDir {
    param([string]$ProjectPath)
    $lockDir = Join-Path $ProjectPath ".felix\.locks"
    if (-not (Test-Path $lockDir)) {
        New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
    }
    return $lockDir
}

function Get-LeasePath {
    param([string]$ProjectPath, [string]$RequirementId)
    return Join-Path (Get-LockDir $ProjectPath) "$RequirementId.lock"
}

function New-RequirementLease {
    <#
    .SYNOPSIS
    Atomically claims a requirement for this worker.
    Returns the lease object on success, $null if already claimed by another worker.

    .PARAMETER ProjectPath
    Path to project root.
    .PARAMETER RequirementId
    Requirement ID to claim (e.g. S-0042).
    .PARAMETER RunId
    Run ID string for this execution.
    .PARAMETER TtlMinutes
    Lease TTL in minutes (default 30).
    #>
    param(
        [string]$ProjectPath,
        [string]$RequirementId,
        [string]$RunId = "",
        [int]$TtlMinutes = $LEASE_TTL_MINUTES
    )

    $leasePath = Get-LeasePath -ProjectPath $ProjectPath -RequirementId $RequirementId

    # Check for and expire stale leases first
    if (Test-Path $leasePath) {
        $existing = Get-LeaseContent -LeasePath $leasePath
        if ($existing -and -not (Test-LeaseValid -Lease $existing)) {
            # Lease expired: remove so we can reclaim
            Write-Host "  [lease] Expired lease for $RequirementId (worker: $($existing.worker_id)) - reclaiming" -ForegroundColor Yellow
            Remove-Item $leasePath -Force -ErrorAction SilentlyContinue
            # Emit expiry event (best-effort)
            try {
                $eventsFile = Join-Path $ProjectPath ".felix\events.jsonl"
                $evt = [PSCustomObject]@{
                    type = "lease.expired"
                    ts   = (Get-Date -Format "o")
                    data = @{ requirement_id = $RequirementId; worker_id = $existing.worker_id; run_id = $existing.run_id }
                }
                $evt | ConvertTo-Json -Compress | Add-Content $eventsFile -Encoding UTF8
            } catch {}
        } elseif ($existing) {
            # Active lease held by another worker
            return $null
        }
    }

    $now    = (Get-Date).ToUniversalTime()
    $lease  = [PSCustomObject]@{
        worker_id   = Get-WorkerId
        run_id      = $RunId
        requirement_id = $RequirementId
        claimed_at  = $now.ToString("o")
        lease_until = $now.AddMinutes($TtlMinutes).ToString("o")
        pid         = $PID
    }

    # Atomic write: New-Item -ErrorAction Stop fails if file already exists
    try {
        $json = $lease | ConvertTo-Json -Compress
        # Use .NET FileStream with FileMode.CreateNew for true atomic create
        $stream = [System.IO.File]::Open(
            $leasePath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
        return $lease
    } catch [System.IO.IOException] {
        # File already exists -> claimed by another worker
        return $null
    } catch {
        Write-Host "  [lease] Claim error for $RequirementId : $_" -ForegroundColor Red
        return $null
    }
}

function Get-LeaseContent {
    <#
    .SYNOPSIS
    Reads and parses a lease file. Returns $null if file missing or corrupt.
    #>
    param([string]$LeasePath)

    if (-not (Test-Path $LeasePath)) { return $null }
    try {
        return Get-Content $LeasePath -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Test-LeaseValid {
    <#
    .SYNOPSIS
    Returns $true if the lease exists and has not expired.
    #>
    param($Lease)

    if (-not $Lease) { return $false }
    try {
        $until = [DateTime]::Parse($Lease.lease_until)
        return ((Get-Date).ToUniversalTime() -lt $until)
    } catch {
        return $false
    }
}

function Test-LeaseOwnedByMe {
    <#
    .SYNOPSIS
    Returns $true if this process owns the lease.
    #>
    param($Lease)
    if (-not $Lease) { return $false }
    return ($Lease.pid -eq $PID -and $Lease.worker_id -eq (Get-WorkerId))
}

function Update-LeaseExpiry {
    <#
    .SYNOPSIS
    Refreshes the lease_until timestamp. Should be called every LEASE_REFRESH_MINUTES.
    Returns $true on success.
    #>
    param(
        [string]$ProjectPath,
        [string]$RequirementId,
        [int]$TtlMinutes = $LEASE_TTL_MINUTES
    )

    $leasePath = Get-LeasePath -ProjectPath $ProjectPath -RequirementId $RequirementId
    $lease = Get-LeaseContent -LeasePath $leasePath
    if (-not $lease) { return $false }
    if (-not (Test-LeaseOwnedByMe -Lease $lease)) { return $false }

    $lease.lease_until = (Get-Date).ToUniversalTime().AddMinutes($TtlMinutes).ToString("o")
    try {
        $lease | ConvertTo-Json -Compress | Set-Content $leasePath -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}

function Remove-RequirementLease {
    <#
    .SYNOPSIS
    Releases a lease. Only removes if owned by this process.
    #>
    param(
        [string]$ProjectPath,
        [string]$RequirementId,
        [switch]$Force
    )

    $leasePath = Get-LeasePath -ProjectPath $ProjectPath -RequirementId $RequirementId
    if (-not (Test-Path $leasePath)) { return $true }

    if (-not $Force) {
        $lease = Get-LeaseContent -LeasePath $leasePath
        if (-not (Test-LeaseOwnedByMe -Lease $lease)) {
            Write-Host "  [lease] Cannot release $RequirementId - owned by $($lease.worker_id)" -ForegroundColor Yellow
            return $false
        }
    }

    Remove-Item $leasePath -Force -ErrorAction SilentlyContinue
    return $true
}

function Get-AllLeases {
    <#
    .SYNOPSIS
    Returns all lease objects in the project, with an IsValid flag.
    #>
    param([string]$ProjectPath)

    $lockDir = Join-Path $ProjectPath ".felix\.locks"
    if (-not (Test-Path $lockDir)) { return @() }

    $result = [System.Collections.ArrayList]@()
    Get-ChildItem -Path $lockDir -Filter "*.lock" | ForEach-Object {
        $lease = Get-LeaseContent -LeasePath $_.FullName
        if ($lease) {
            $lease | Add-Member -NotePropertyName "IsValid" -NotePropertyValue (Test-LeaseValid -Lease $lease) -Force
            $lease | Add-Member -NotePropertyName "IsOwnedByMe" -NotePropertyValue (Test-LeaseOwnedByMe -Lease $lease) -Force
            [void]$result.Add($lease)
        }
    }
    return $result.ToArray()
}

function Get-ExpiredLeases {
    <#
    .SYNOPSIS
    Returns leases that have expired (TTL elapsed and worker PID no longer running).
    #>
    param([string]$ProjectPath)

    $all = Get-AllLeases -ProjectPath $ProjectPath
    return $all | Where-Object { -not $_.IsValid }
}

function Test-RequirementLeased {
    <#
    .SYNOPSIS
    Returns $true if the requirement is currently held by a valid (non-expired) lease.
    #>
    param([string]$ProjectPath, [string]$RequirementId)

    $leasePath = Get-LeasePath -ProjectPath $ProjectPath -RequirementId $RequirementId
    $lease = Get-LeaseContent -LeasePath $leasePath
    return (Test-LeaseValid -Lease $lease)
}
