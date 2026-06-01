<#
.SYNOPSIS
Context Budgeter for Felix v2 (Phase A5).

.DESCRIPTION
Token estimation and budget enforcement for prompt assembly.

Config block (.felix/config.json):
  "context": { "budget_tokens": 32000 }

Weights and eviction order are code constants in v2.0 (not user-tunable).
Default weights:
  layered_agents 0.15, repo_map 0.05, spec 0.20, plan 0.15,
  context_map 0.20, skills 0.10, memory 0.10, extras 0.05

Eviction order (first evicted when over budget):
  extras -> memory -> context_map -> skills -> layered_agents -> repo_map -> plan -> spec

Output: "tokens: N/M" summary printed on every iteration (via Emit-Log).
Budget event emitted to Event Bus (AS2) per iteration.
#>

# Code constants (v2.0  -  not user-tunable; promoted to config on bench-backed demand)
$script:BUDGET_WEIGHTS = @{
    layered_agents = 0.15
    repo_map       = 0.05
    spec           = 0.20
    plan           = 0.15
    context_map    = 0.20
    skills         = 0.10
    memory         = 0.10
    extras         = 0.05
}

$script:EVICTION_ORDER = @(
    "extras",
    "memory",
    "context_map",
    "skills",
    "layered_agents",
    "repo_map",
    "plan",
    "spec"
)

$script:DEFAULT_BUDGET_TOKENS = 32000

# Rough chars-per-token heuristic (tiktoken-equivalent for English prose)
$script:CHARS_PER_TOKEN = 4

function Get-TokenEstimate {
    <#
    .SYNOPSIS
    Estimates token count for a string using a cheap heuristic.

    .PARAMETER Text
    The text to estimate.

    .OUTPUTS
    Integer token estimate.
    #>
    param([string]$Text)

    if (-not $Text) { return 0 }
    return [int][Math]::Ceiling($Text.Length / $script:CHARS_PER_TOKEN)
}

function Get-BudgetTokens {
    <#
    .SYNOPSIS
    Returns the configured token budget.

    .PARAMETER Config
    Felix config object. Reads config.context.budget_tokens.
    #>
    param($Config)

    if ($Config -and $Config.context -and $Config.context.budget_tokens) {
        return [int]$Config.context.budget_tokens
    }
    return $script:DEFAULT_BUDGET_TOKENS
}

function Invoke-ContextBudget {
    <#
    .SYNOPSIS
    Enforces the context budget by evicting sources that exceed the limit.

    .PARAMETER Sources
    Ordered hashtable of source-name -> content string.
    Keys must be from: layered_agents, repo_map, spec, plan, context_map, skills, memory, extras

    .PARAMETER BudgetTokens
    Total token budget (default 32000).

    .OUTPUTS
    A hashtable:
      Sources      – hashtable of kept source-name -> content (evicted sources set to "")
      TokenTable   – hashtable of source-name -> estimated tokens
      TotalTokens  – total tokens in kept sources
      BudgetTokens – the budget used
      Evicted      – array of evicted source names
      Summary      – "tokens: N/M" one-liner
    #>
    param(
        [hashtable]$Sources,
        [int]$BudgetTokens = $script:DEFAULT_BUDGET_TOKENS
    )

    # Estimate tokens per source
    $tokenTable = @{}
    $totalTokens = 0
    foreach ($key in $Sources.Keys) {
        $est = Get-TokenEstimate -Text $Sources[$key]
        $tokenTable[$key] = $est
        $totalTokens += $est
    }

    $evicted = [System.Collections.ArrayList]@()
    $keptSources = @{}
    foreach ($key in $Sources.Keys) {
        $keptSources[$key] = $Sources[$key]
    }

    # Evict in order until we fit within budget
    if ($totalTokens -gt $BudgetTokens) {
        foreach ($sourceToEvict in $script:EVICTION_ORDER) {
            if ($totalTokens -le $BudgetTokens) { break }
            if ($keptSources.ContainsKey($sourceToEvict) -and $keptSources[$sourceToEvict]) {
                $totalTokens -= $tokenTable[$sourceToEvict]
                $keptSources[$sourceToEvict] = ""
                [void]$evicted.Add($sourceToEvict)

                if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
                    Emit-Log -Level "warn" -Message "Context budget: evicted '$sourceToEvict' ($($tokenTable[$sourceToEvict]) tokens)  -  running total: $totalTokens/$BudgetTokens" -Component "context-budgeter"
                }
            }
        }
    }

    $summary = "tokens: $totalTokens/$BudgetTokens"

    return @{
        Sources      = $keptSources
        TokenTable   = $tokenTable
        TotalTokens  = $totalTokens
        BudgetTokens = $BudgetTokens
        Evicted      = $evicted.ToArray()
        Summary      = $summary
    }
}

function Get-ContextInspectReport {
    <#
    .SYNOPSIS
    Builds the report for `felix context inspect`.

    .PARAMETER Sources
    Hashtable of source-name -> content.

    .PARAMETER BudgetTokens
    Token budget.

    .PARAMETER AsJson
    Return JSON-serializable hashtable instead of formatted string.
    #>
    param(
        [hashtable]$Sources,
        [int]$BudgetTokens = $script:DEFAULT_BUDGET_TOKENS,
        [switch]$AsJson
    )

    $result = Invoke-ContextBudget -Sources $Sources -BudgetTokens $BudgetTokens

    $rows = [System.Collections.ArrayList]@()
    $allKeys = @("layered_agents","repo_map","spec","plan","context_map","skills","memory","extras")
    foreach ($key in $allKeys) {
        $tokens   = if ($result.TokenTable.ContainsKey($key)) { $result.TokenTable[$key] } else { 0 }
        $weight   = if ($script:BUDGET_WEIGHTS.ContainsKey($key)) { $script:BUDGET_WEIGHTS[$key] } else { 0 }
        $alloc    = [int][Math]::Round($BudgetTokens * $weight)
        $kept     = $key -notin $result.Evicted
        [void]$rows.Add(@{
            source    = $key
            estimated = $tokens
            allocated = $alloc
            weight    = $weight
            kept      = $kept
        })
    }

    if ($AsJson) {
        return @{
            "_v"          = 1
            total_tokens  = $result.TotalTokens
            budget_tokens = $BudgetTokens
            evicted       = $result.Evicted
            sources       = $rows.ToArray()
            summary       = $result.Summary
        }
    }

    # Formatted table
    $lines = [System.Collections.ArrayList]@()
    [void]$lines.Add("Context Budget Report")
    [void]$lines.Add("$('-' * 60)")
    [void]$lines.Add(("{0,-20} {1,8} {2,8} {3,7} {4}" -f "Source", "Est.Tok", "Alloc", "Weight", "Status"))
    [void]$lines.Add(("{0,-20} {1,8} {2,8} {3,7} {4}" -f "------------------", "-------", "------", "------", "------"))

    foreach ($row in $rows) {
        $status = if ($row.kept) { "kept" } else { "EVICTED" }
        [void]$lines.Add(("{0,-20} {1,8} {2,8} {3,7:P0} {4}" -f $row.source, $row.estimated, $row.allocated, $row.weight, $status))
    }
    [void]$lines.Add(("{0,-20} {1,8}" -f "------------------", "-------"))
    [void]$lines.Add(("{0,-20} {1,8}/{2}" -f "TOTAL", $result.TotalTokens, $BudgetTokens))
    if ($result.Evicted.Count -gt 0) {
        [void]$lines.Add("")
        [void]$lines.Add("[!] Evicted: $($result.Evicted -join ', ')")
    }
    return $lines -join "`n"
}
