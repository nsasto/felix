<#
.SYNOPSIS
felix query  -  stable versioned JSON interface for agent-readable state (Phase F3).

.DESCRIPTION
Exposes Invoke-Query for felix.ps1 dispatch.
Kinds: requirements | runs | state | usage

Examples:
  felix query requirements --status planned --json
  felix query runs --since 24h --requirement S-0042
  felix query usage --since 7d --json
  felix query state --json
#>

function Invoke-Query {
    param(
        [string[]]$CmdArgs = @(),
        [string]$ProjectPath = (Get-Location).Path
    )

    $felixDir = Join-Path $ProjectPath ".felix"
    $json     = $CmdArgs -icontains "--json"

    # Resolve kind
    $kind = ""
    foreach ($a in $CmdArgs) {
        if (-not $a.StartsWith("-")) { $kind = $a.ToLower(); break }
    }

    function Write-Result {
        param($Obj)
        if ($json) {
            $Obj | ConvertTo-Json -Depth 6
        } else {
            $Obj | Format-List
        }
    }

    function Error-Out {
        param([string]$Msg, [int]$Code = 1)
        if ($json) {
            [ordered]@{ _v = 1; error = $Msg } | ConvertTo-Json
        } else {
            Write-Host "Error: $Msg" -ForegroundColor Red
        }
        exit $Code
    }

    function Get-ArgValue {
        param([string]$Name)
        for ($i = 0; $i -lt $CmdArgs.Count - 1; $i++) {
            if ($CmdArgs[$i] -ieq $Name) { return $CmdArgs[$i + 1] }
        }
        return $null
    }

    function Parse-SinceValue {
        param([string]$Value)
        if (-not $Value) { return $null }

        if ($Value -match '^(\d+)h$') {
            return (Get-Date).AddHours(-[int]$Matches[1])
        }

        if ($Value -match '^(\d+)d$') {
            return (Get-Date).AddDays(-[int]$Matches[1])
        }

        try {
            return [datetime]::Parse($Value)
        }
        catch {
            return $null
        }
    }

    function Get-UsageTokenValue {
        param($Usage, [string]$Name)
        if (-not $Usage) { return $null }
        $prop = $Usage.PSObject.Properties[$Name]
        if (-not $prop -or $null -eq $prop.Value) { return $null }
        try { return [int64]$prop.Value } catch { return $null }
    }

    function Get-PricingCatalog {
        param([string]$FelixDir)

        $pricingPath = Join-Path $FelixDir "model-pricing.json"
        if (-not (Test-Path $pricingPath)) {
            return [ordered]@{
                path     = $pricingPath
                currency = "USD"
                entries  = @()
            }
        }

        try {
            $raw = Get-Content $pricingPath -Raw | ConvertFrom-Json
            $entries = @()
            if ($raw.prices) { $entries = @($raw.prices) }
            elseif ($raw.models) { $entries = @($raw.models) }

            return [ordered]@{
                path     = $pricingPath
                currency = if ($raw.currency) { [string]$raw.currency } else { "USD" }
                entries  = $entries
            }
        }
        catch {
            return [ordered]@{
                path     = $pricingPath
                currency = "USD"
                entries  = @()
                error    = $_.Exception.Message
            }
        }
    }

    function Test-PricingMatch {
        param(
            $Entry,
            [string]$Provider,
            [string]$Model
        )

        $entryProvider = if ($Entry.provider) { [string]$Entry.provider } else { "*" }
        $entryModel = if ($Entry.model) { [string]$Entry.model } else { "*" }

        $providerMatches = $entryProvider -eq "*" -or [string]::Equals($entryProvider, $Provider, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $providerMatches) { return $false }

        if ($entryModel -eq "*") { return $true }
        if ([string]::Equals($entryModel, $Model, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }

        return $Model -like $entryModel
    }

    function Get-UsagePricingEntry {
        param(
            $Catalog,
            [string]$Provider,
            [string]$Model
        )

        if (-not $Catalog -or -not $Catalog.entries) { return $null }

        $matches = @($Catalog.entries | Where-Object { Test-PricingMatch -Entry $_ -Provider $Provider -Model $Model })
        if ($matches.Count -eq 0) { return $null }

        # Prefer exact model/provider entries, then wildcard model entries.
        $exact = @($matches | Where-Object {
                $_.provider -and $_.model -and
                [string]::Equals([string]$_.provider, $Provider, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$_.model, $Model, [System.StringComparison]::OrdinalIgnoreCase)
            })
        if ($exact.Count -gt 0) { return $exact[0] }

        $providerDefault = @($matches | Where-Object {
                $_.provider -and [string]::Equals([string]$_.provider, $Provider, [System.StringComparison]::OrdinalIgnoreCase) -and
                (-not $_.model -or [string]$_.model -eq "*")
            })
        if ($providerDefault.Count -gt 0) { return $providerDefault[0] }

        return $matches[0]
    }

    function ConvertTo-NullableDecimal {
        param($Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return $null }
        try { return [decimal]$Value } catch { return $null }
    }

    function Get-EntryPrice {
        param($Entry, [string]$Name)
        if (-not $Entry) { return $null }
        $prop = $Entry.PSObject.Properties[$Name]
        if (-not $prop) { return $null }
        return ConvertTo-NullableDecimal $prop.Value
    }

    function Get-EstimatedUsageCost {
        param(
            $PricingEntry,
            [int64]$InputTokens = 0,
            [int64]$OutputTokens = 0,
            [int64]$CacheReadInputTokens = 0,
            [int64]$CacheCreationInputTokens = 0
        )

        if (-not $PricingEntry) { return $null }

        $inputRate = Get-EntryPrice -Entry $PricingEntry -Name "input_per_million"
        $outputRate = Get-EntryPrice -Entry $PricingEntry -Name "output_per_million"
        $cacheReadRate = Get-EntryPrice -Entry $PricingEntry -Name "cache_read_per_million"
        $cacheCreationRate = Get-EntryPrice -Entry $PricingEntry -Name "cache_creation_per_million"

        $cost = [decimal]0
        $hasRate = $false

        if ($null -ne $inputRate) {
            $cost += ([decimal]$InputTokens / 1000000) * $inputRate
            $hasRate = $true
        }
        if ($null -ne $outputRate) {
            $cost += ([decimal]$OutputTokens / 1000000) * $outputRate
            $hasRate = $true
        }
        if ($null -ne $cacheReadRate) {
            $cost += ([decimal]$CacheReadInputTokens / 1000000) * $cacheReadRate
            $hasRate = $true
        }
        if ($null -ne $cacheCreationRate) {
            $cost += ([decimal]$CacheCreationInputTokens / 1000000) * $cacheCreationRate
            $hasRate = $true
        }

        if (-not $hasRate) { return $null }
        return [math]::Round($cost, 6)
    }

    switch ($kind) {
        "requirements" {
            $reqFile = Join-Path $felixDir "requirements.json"
            if (-not (Test-Path $reqFile)) { Error-Out "requirements.json not found" }

            $data = Get-Content $reqFile -Raw | ConvertFrom-Json
            $reqs = @($data.requirements)

            # Filter --status
            $statusFilter = $null
            for ($i = 0; $i -lt $CmdArgs.Count - 1; $i++) {
                if ($CmdArgs[$i] -ieq "--status") { $statusFilter = $CmdArgs[$i+1]; break }
            }
            if ($statusFilter) {
                $reqs = @($reqs | Where-Object { $_.status -ieq $statusFilter })
            }

            $result = [ordered]@{
                _v           = 1
                kind         = "requirements"
                total        = $reqs.Count
                requirements = @($reqs | ForEach-Object {
                    [ordered]@{
                        id          = $_.id
                        title       = $_.title
                        status      = $_.status
                        priority    = $_.priority
                        spec_path   = $_.spec_path
                        tags        = @($_.tags)
                    }
                })
            }
            Write-Result $result
        }

        "runs" {
            $runsDir = Join-Path $ProjectPath "runs"
            if (-not (Test-Path $runsDir)) { Error-Out "runs/ directory not found" }

            # Filters
            $sinceArg = Get-ArgValue "--since"
            $reqFilter = Get-ArgValue "--requirement"
            $cutoff = Parse-SinceValue $sinceArg

            $runDirs = Get-ChildItem -Path $runsDir -Directory -ErrorAction SilentlyContinue |
                Where-Object {
                    if ($reqFilter -and $_.Name -notmatch [regex]::Escape($reqFilter)) { return $false }
                    if ($cutoff -and $_.LastWriteTime -lt $cutoff) { return $false }
                    return $true
                } |
                Sort-Object LastWriteTime -Descending

            $runs = @($runDirs | ForEach-Object {
                $d = $_
                $planFile  = Join-Path $d.FullName "plan.md"
                $stateFile = Join-Path $d.FullName "state.json"
                $outcome   = "unknown"
                if (Test-Path $stateFile) {
                    try { $outcome = (Get-Content $stateFile -Raw | ConvertFrom-Json).outcome } catch {}
                }
                [ordered]@{
                    id           = $d.Name
                    path         = $d.FullName.Replace($ProjectPath + "\", "")
                    last_modified = $d.LastWriteTime.ToString("o")
                    has_plan     = (Test-Path $planFile)
                    outcome      = $outcome
                }
            })

            $result = [ordered]@{
                _v    = 1
                kind  = "runs"
                total = $runs.Count
                runs  = $runs
            }
            Write-Result $result
        }

        "usage" {
            $runsDir = Join-Path $ProjectPath "runs"
            if (-not (Test-Path $runsDir)) { Error-Out "runs/ directory not found" }

            $pricingCatalog = Get-PricingCatalog -FelixDir $felixDir
            $sinceArg = Get-ArgValue "--since"
            $reqFilter = Get-ArgValue "--requirement"
            $runFilter = Get-ArgValue "--run-id"
            $cutoff = Parse-SinceValue $sinceArg

            $usageEntries = @(
                Get-ChildItem -Path $runsDir -Directory -ErrorAction SilentlyContinue |
                    Where-Object {
                        if ($runFilter -and $_.Name -ne $runFilter) { return $false }
                        if ($reqFilter -and $_.Name -notmatch [regex]::Escape($reqFilter)) { return $false }
                        if ($cutoff -and $_.LastWriteTime -lt $cutoff) { return $false }
                        return $true
                    } |
                    Sort-Object LastWriteTime -Descending |
                    ForEach-Object {
                        $usagePath = Join-Path $_.FullName "usage.json"
                        if (-not (Test-Path $usagePath)) { return }

                        try {
                            $usage = Get-Content $usagePath -Raw | ConvertFrom-Json
                        }
                        catch {
                            return
                        }

                        $tokens = $usage.usage
                        $provider = if ($usage.agent.provider) { [string]$usage.agent.provider } else { [string]$usage.agent.adapter }
                        $effectiveModel = if ($usage.model.effective) { [string]$usage.model.effective } else { [string]$usage.model.configured }
                        $pricingEntry = Get-UsagePricingEntry -Catalog $pricingCatalog -Provider $provider -Model $effectiveModel
                        $inputTokens = Get-UsageTokenValue $tokens "input_tokens"
                        $outputTokens = Get-UsageTokenValue $tokens "output_tokens"
                        $cacheReadTokens = Get-UsageTokenValue $tokens "cache_read_input_tokens"
                        $cacheCreationTokens = Get-UsageTokenValue $tokens "cache_creation_input_tokens"
                        $estimatedCost = Get-EstimatedUsageCost `
                            -PricingEntry $pricingEntry `
                            -InputTokens $(if ($null -eq $inputTokens) { 0 } else { $inputTokens }) `
                            -OutputTokens $(if ($null -eq $outputTokens) { 0 } else { $outputTokens }) `
                            -CacheReadInputTokens $(if ($null -eq $cacheReadTokens) { 0 } else { $cacheReadTokens }) `
                            -CacheCreationInputTokens $(if ($null -eq $cacheCreationTokens) { 0 } else { $cacheCreationTokens })

                        [ordered]@{
                            run_id                      = if ($usage.run_id) { $usage.run_id } else { $_.Name }
                            path                        = $usagePath.Replace($ProjectPath + "\", "")
                            timestamp_utc               = $usage.timestamp_utc
                            duration_seconds            = $usage.duration_seconds
                            exit_code                   = $usage.exit_code
                            succeeded                   = $usage.succeeded
                            usage_available             = $usage.usage_available
                            usage_source                = $usage.usage_source
                            session_id                  = $usage.session_id
                            agent_id                    = $usage.agent.id
                            agent_name                  = $usage.agent.name
                            provider                    = $provider
                            adapter                     = $usage.agent.adapter
                            configured_model            = $usage.model.configured
                            effective_model             = $effectiveModel
                            model_source                = $usage.model.source
                            input_tokens                = $inputTokens
                            output_tokens               = $outputTokens
                            total_tokens                = Get-UsageTokenValue $tokens "total_tokens"
                            cache_read_input_tokens     = $cacheReadTokens
                            cache_creation_input_tokens = $cacheCreationTokens
                            observed_tokens             = Get-UsageTokenValue $tokens "observed_tokens"
                            cost_available              = ($null -ne $estimatedCost)
                            estimated_cost              = $estimatedCost
                            pricing_model               = if ($pricingEntry -and $pricingEntry.model) { [string]$pricingEntry.model } else { $null }
                        }
                    }
            )

            $totals = [ordered]@{
                input_tokens                = [int64]0
                output_tokens               = [int64]0
                total_tokens                = [int64]0
                cache_read_input_tokens     = [int64]0
                cache_creation_input_tokens = [int64]0
                observed_tokens             = [int64]0
            }
            $estimatedCostTotal = [decimal]0
            $costEntries = 0

            foreach ($entry in $usageEntries) {
                foreach ($name in @("input_tokens", "output_tokens", "total_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "observed_tokens")) {
                    if ($null -ne $entry[$name]) {
                        $totals[$name] += [int64]$entry[$name]
                    }
                }

                if ($null -ne $entry.estimated_cost) {
                    $estimatedCostTotal += [decimal]$entry.estimated_cost
                    $costEntries++
                }
            }

            $result = [ordered]@{
                _v      = 1
                kind    = "usage"
                total   = $usageEntries.Count
                currency = $pricingCatalog.currency
                pricing = [ordered]@{
                    path          = $pricingCatalog.path
                    entries       = @($pricingCatalog.entries).Count
                    error         = if ($pricingCatalog.error) { $pricingCatalog.error } else { $null }
                    costed_runs   = $costEntries
                }
                totals  = $totals
                estimated_cost = if ($costEntries -gt 0) { [math]::Round($estimatedCostTotal, 6) } else { $null }
                usage   = $usageEntries
            }

            if ($json) {
                Write-Result $result
            }
            else {
                Write-Host ("Usage records: {0}" -f $usageEntries.Count) -ForegroundColor Cyan
                Write-Host ("Tokens: input={0} output={1} total={2} cache_read={3} cache_create={4} observed={5}" -f `
                    $totals.input_tokens,
                    $totals.output_tokens,
                    $totals.total_tokens,
                    $totals.cache_read_input_tokens,
                    $totals.cache_creation_input_tokens,
                    $totals.observed_tokens) -ForegroundColor Gray
                if ($costEntries -gt 0) {
                    Write-Host ("Estimated cost: {0} {1} ({2}/{3} run(s) priced)" -f $pricingCatalog.currency, ([math]::Round($estimatedCostTotal, 6)), $costEntries, $usageEntries.Count) -ForegroundColor Gray
                }
                else {
                    Write-Host ("Estimated cost: unavailable (add .felix/model-pricing.json)") -ForegroundColor DarkGray
                }
                $usageEntries |
                    Select-Object run_id, provider, effective_model, input_tokens, output_tokens, total_tokens, cache_read_input_tokens, cache_creation_input_tokens, estimated_cost, duration_seconds, succeeded |
                    Format-Table -AutoSize
            }
        }

        "state" {
            $stateFile = Join-Path $felixDir "state.json"
            $state     = [ordered]@{}
            if (Test-Path $stateFile) {
                try {
                    $raw = Get-Content $stateFile -Raw | ConvertFrom-Json
                    foreach ($p in $raw.PSObject.Properties) { $state[$p.Name] = $p.Value }
                } catch {}
            }

            $result = [ordered]@{
                _v            = 1
                kind          = "state"
                project_path  = $ProjectPath
                felix_dir     = $felixDir
                state         = $state
            }
            Write-Result $result
        }

        default {
            if ($kind -in @("events","plugins","skills","memory")) {
                $alternatives = @{
                    events  = "felix event query"
                    plugins = "felix plugin list"
                    skills  = "felix skill list"
                    memory  = "felix memory view"
                }
                $alt = $alternatives[$kind]
                if ($json) {
                    [ordered]@{
                        _v    = 1
                        error = "Kind '$kind' is not supported by 'felix query'. Use '$alt' instead."
                    } | ConvertTo-Json
                } else {
                    Write-Host "Error: 'felix query $kind' is not supported." -ForegroundColor Red
                    Write-Host "Use '$alt' instead." -ForegroundColor Yellow
                }
                exit 1
            }

            Write-Host "felix query - usage:" -ForegroundColor Cyan
            Write-Host "  felix query requirements [--status <status>] [--json]"
            Write-Host "  felix query runs [--since <Nh|Nd>] [--requirement <id>] [--json]"
            Write-Host "  felix query usage [--since <Nh|Nd>] [--requirement <id>] [--run-id <id>] [--json]"
            Write-Host "  felix query state [--json]"
        }
    }
}
