<#
.SYNOPSIS
Event Bus reader helper (Phase E7).

.DESCRIPTION
Reads .felix/events.jsonl and returns filtered events for a given run.
Used by learning-capture and other consumers to avoid log scraping.
#>

function Get-RunEvents {
    <#
    .SYNOPSIS
    Returns events from the Event Bus filtered by run ID and optionally by event kind.

    .PARAMETER FelixDir
    Path to the .felix directory.

    .PARAMETER RunId
    Run ID to filter on (matched against the run_id field).

    .PARAMETER Kinds
    Optional array of event kind strings to filter on. If omitted, all kinds are returned.
    Kind matching is case-insensitive and checks both the top-level "kind" and "type" fields.

    .OUTPUTS
    Array of parsed event objects. Empty array if file not found or no matches.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FelixDir,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $false)]
        [string[]]$Kinds = @()
    )

    $eventsPath = Join-Path $FelixDir "events.jsonl"
    if (-not (Test-Path $eventsPath)) {
        return @()
    }

    $matched = [System.Collections.ArrayList]@()

    try {
        $lines = Get-Content $eventsPath -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $lines) { return @() }

        foreach ($line in $lines) {
            $line = $line.Trim()
            if (-not $line) { continue }

            $evt = $null
            try { $evt = $line | ConvertFrom-Json } catch { continue }

            # Filter by run_id
            $evtRunId = if ($evt.run_id) { $evt.run_id } elseif ($evt.runId) { $evt.runId } else { "" }
            if ($evtRunId -ne $RunId) { continue }

            # Filter by kind/type if requested
            if ($Kinds -and $Kinds.Count -gt 0) {
                $evtKind = if ($evt.kind) { $evt.kind } elseif ($evt.type) { $evt.type } else { "" }
                $match = $false
                foreach ($k in $Kinds) {
                    if ($evtKind -ieq $k) { $match = $true; break }
                }
                if (-not $match) { continue }
            }

            [void]$matched.Add($evt)
        }
    }
    catch {
        # Silent failure - event bus must never break execution
    }

    $arr = $matched.ToArray()
    if ($arr.Count -eq 0) { return @() }
    if ($arr.Count -eq 1) { return ,$arr }
    return $arr
}
