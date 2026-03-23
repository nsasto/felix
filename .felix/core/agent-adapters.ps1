# Agent Adapters - Multi-Agent Support for Felix
# Provides adapter pattern for different LLM CLIs (Droid, Claude, Codex, Gemini, Copilot)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot/emit-event.ps1"

<#
.SYNOPSIS
Base adapter interface for LLM agents.

.DESCRIPTION
Each adapter handles agent-specific:
- Prompt formatting
- Response parsing
- Completion signal detection
- CLI argument construction
#>

function Get-CompletionSignalPattern {
    return '(?m)^[ \t]*<promise>(PLAN_COMPLETE|PLANNING_COMPLETE|TASK_COMPLETE|ALL_COMPLETE)</promise>[ \t]*$'
}

function Resolve-LegacyCompletionSignal {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Signal
    )

    switch ($Signal.Trim()) {
        "PLAN_COMPLETE" { return "PLAN_COMPLETE" }
        "PLANNING_COMPLETE" { return "PLAN_COMPLETE" }
        "TASK_COMPLETE" { return "TASK_COMPLETE" }
        "ALL_COMPLETE" { return "ALL_COMPLETE" }
        default { return $null }
    }
}

function Get-CompletionSignalFromJsonText {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Output
    )

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return $null
    }

    $candidates = @()
    $trimmed = $Output.Trim()

    if ($trimmed.StartsWith("{")) {
        $candidates += $trimmed
    }

    # Support markdown-wrapped JSON responses (```json ... ```)
    $fencedMatch = [regex]::Match($Output, '(?is)```json\s*(\{.*?\})\s*```')
    if ($fencedMatch.Success) {
        $candidates += $fencedMatch.Groups[1].Value
    }

    # Support mixed prose + JSON by taking the broad outer object slice.
    $firstBrace = $Output.IndexOf('{')
    $lastBrace = $Output.LastIndexOf('}')
    if ($firstBrace -ge 0 -and $lastBrace -gt $firstBrace) {
        $candidates += $Output.Substring($firstBrace, $lastBrace - $firstBrace + 1)
    }

    foreach ($candidate in $candidates | Select-Object -Unique) {
        try {
            $json = $candidate | ConvertFrom-Json -ErrorAction Stop

            if ($json.completion -and $json.completion.signal) {
                $signal = Resolve-LegacyCompletionSignal -Signal ([string]$json.completion.signal)
                if ($signal) {
                    return $signal
                }
            }

            if ($json.response_metadata -and $json.response_metadata.signal) {
                $signal = Resolve-LegacyCompletionSignal -Signal ([string]$json.response_metadata.signal)
                if ($signal) {
                    return $signal
                }
            }
        }
        catch {
            # Ignore malformed candidate, continue
        }
    }

    return $null
}

function Get-FinalJsonResponseText {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Output
    )

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return $null
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $trimmed = $Output.Trim()
    if ($trimmed.StartsWith("{") -and $trimmed.EndsWith("}")) {
        $candidates.Add($trimmed)
    }

    # Collect fenced JSON payloads in order and prefer the last valid one.
    $fencedMatches = [regex]::Matches($Output, '(?is)```json\s*(\{.*?\})\s*```')
    foreach ($m in $fencedMatches) {
        $candidates.Add([string]$m.Groups[1].Value)
    }

    # Collect balanced JSON objects from arbitrary text as fallback.
    $start = -1
    $depth = 0
    $inString = $false
    $escaping = $false

    for ($i = 0; $i -lt $Output.Length; $i++) {
        $ch = $Output[$i]

        if ($escaping) {
            $escaping = $false
            continue
        }

        if ($ch -eq '\\') {
            if ($inString) {
                $escaping = $true
            }
            continue
        }

        if ($ch -eq '"') {
            $inString = -not $inString
            continue
        }

        if ($inString) {
            continue
        }

        if ($ch -eq '{') {
            if ($depth -eq 0) {
                $start = $i
            }
            $depth++
            continue
        }

        if ($ch -eq '}') {
            if ($depth -gt 0) {
                $depth--
                if ($depth -eq 0 -and $start -ge 0) {
                    $len = $i - $start + 1
                    $candidates.Add($Output.Substring($start, $len))
                    $start = -1
                }
            }
            continue
        }
    }

    $valid = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in $candidates) {
        try {
            $parsed = $candidate | ConvertFrom-Json -ErrorAction Stop
            $hasSignal = $false
            if ($parsed.completion -and $parsed.completion.signal) {
                $hasSignal = [bool](Resolve-LegacyCompletionSignal -Signal ([string]$parsed.completion.signal))
            }
            elseif ($parsed.response_metadata -and $parsed.response_metadata.signal) {
                $hasSignal = [bool](Resolve-LegacyCompletionSignal -Signal ([string]$parsed.response_metadata.signal))
            }

            $valid.Add([pscustomobject]@{
                    Text      = $candidate.Trim()
                    HasSignal = $hasSignal
                })
        }
        catch {
            # Ignore invalid JSON snippets.
        }
    }

    if ($valid.Count -eq 0) {
        return $null
    }

    # Prefer the last valid JSON that carries completion.signal.
    for ($i = $valid.Count - 1; $i -ge 0; $i--) {
        if ($valid[$i].HasSignal) {
            return [string]$valid[$i].Text
        }
    }

    # Else return the last valid JSON object.
    return [string]$valid[$valid.Count - 1].Text
}

function Get-CompletionSignal {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Output,

        [Parameter(Mandatory = $false)]
        [switch]$AllowPlanningAlias
    )

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return $null
    }

    # First, try to parse JSON payloads (pure JSON, fenced JSON, or mixed prose+JSON).
    $jsonSignal = Get-CompletionSignalFromJsonText -Output $Output
    if ($jsonSignal) {
        return $jsonSignal
    }

    # Fallback: Use regex pattern for old plain-text format with <promise> tags
    $pattern = Get-CompletionSignalPattern
    $signals = @(
        ($Output -split "`r`n|`n|`r") |
        ForEach-Object {
            if ($_ -match $pattern) {
                $Matches[1]
            }
        }
    )

    if ($signals.Count -eq 0) {
        return $null
    }

    if ($signals -contains "ALL_COMPLETE") {
        return "ALL_COMPLETE"
    }

    if ($signals -contains "TASK_COMPLETE") {
        return "TASK_COMPLETE"
    }

    if ($signals -contains "PLAN_COMPLETE") {
        return "PLAN_COMPLETE"
    }

    if ($AllowPlanningAlias -and $signals -contains "PLANNING_COMPLETE") {
        return "PLAN_COMPLETE"
    }

    return $null
}

function Set-CompletionResult {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Result,

        [Parameter(Mandatory = $true)]
        [string]$Signal
    )

    $Result.IsComplete = $true
    switch ($Signal) {
        "PLAN_COMPLETE" {
            $Result.NextMode = "building"
        }
        "TASK_COMPLETE" {
            $Result.NextMode = "continue"
        }
        "ALL_COMPLETE" {
            $Result.NextMode = "complete"
        }
    }
}

# ============================================================================
# DROID ADAPTER (Factory.ai)
# ============================================================================

class DroidAdapter {
    [string] FormatPrompt([string]$prompt) {
        # Droid expects raw prompt text
        return $prompt
    }

    [hashtable] ParseResponse([string]$output) {
        $result = @{
            Output     = $output
            IsComplete = $false
            NextMode   = $null
            Error      = $null
        }

        $lines = $output -split '\r?\n' | Where-Object { $_.Trim() -ne '' }
        $foundCompletion = $false
        $finalText = $null
        $isStreamJson = $false
        
        foreach ($line in $lines) {
            try {
                $event = $line | ConvertFrom-Json -ErrorAction Stop
                
                # Check if this is stream-json format (has .type field)
                if ($event.type) {
                    $isStreamJson = $true
                    
                    switch ($event.type) {
                        "system" {
                            $toolCount = if ($event.tools) { $event.tools.Count } else { 0 }
                            Emit-Log -Level "info" -Message "Session initialized: $($event.model) ($toolCount tools available)" -Component "droid"
                        }
                        "tool_call" {
                            $paramStr = ""
                            if ($event.parameters) {
                                $paramParts = @()
                                foreach ($prop in $event.parameters.PSObject.Properties) {
                                    $val = if ($prop.Value.ToString().Length -gt 50) { $prop.Value.ToString().Substring(0, 50) + "..." } else { $prop.Value }
                                    $paramParts += "$($prop.Name)=$val"
                                }
                                if ($paramParts.Count -gt 0) {
                                    $paramStr = " | " + ($paramParts -join ", ")
                                }
                            }
                            Emit-Log -Level "info" -Message "[TOOL] $($event.toolName)$paramStr" -Component "agent"
                        }
                        "tool_result" {
                            $resultPreview = if ($event.value -and $event.value.Length -gt 200) { 
                                $event.value.Substring(0, 200) + "..." 
                            }
                            elseif ($event.value) { 
                                $event.value 
                            }
                            else {
                                "(no output)"
                            }
                            $status = if ($event.isError) { "[ERROR]" } else { "[OK]" }
                            $level = if ($event.isError) { "warn" } else { "debug" }
                            Emit-Log -Level $level -Message "$status $resultPreview" -Component "agent"
                        }
                        "message" {
                            if ($event.role -eq "assistant" -and $event.text) {
                                Emit-Log -Level "debug" -Message "[THINKING] $($event.text)" -Component "agent"
                            }
                        }
                        "result" {
                            if ($event.is_error -or $event.subtype -eq "failure") {
                                $errorMsg = if ($event.result) { [string]$event.result } else { "Agent returned failure result (subtype=$($event.subtype))" }
                                $result.Error = $errorMsg
                                Emit-Log -Level "warn" -Message "Agent reported failure: $errorMsg" -Component "droid"
                            }
                            elseif ($event.result) {
                                $result.Output = [string]$event.result
                                $foundCompletion = $true
                                # Detect completion signal embedded in the result text
                                $innerSignal = Get-CompletionSignal -Output ([string]$event.result) -AllowPlanningAlias
                                if ($innerSignal) {
                                    Set-CompletionResult -Result $result -Signal $innerSignal
                                }
                            }
                        }
                        "completion" {
                            $finalText = $event.finalText
                            $foundCompletion = $true
                            
                            if ($event.durationMs -and $event.usage) {
                                $durationSec = [math]::Round($event.durationMs / 1000.0, 1)
                                $tokens = "in=$($event.usage.input_tokens) out=$($event.usage.output_tokens)"
                                if ($event.usage.cache_read_input_tokens -gt 0) {
                                    $tokens += " cached=$($event.usage.cache_read_input_tokens)"
                                }
                                Emit-Log -Level "info" -Message "Execution complete (${durationSec}s) Tokens: $tokens" -Component "agent"
                            }
                        }
                    }
                }
                # Legacy: completion_signal events (old json format)
                elseif ($event.type -eq 'completion_signal' -or $event.signal) {
                    $signalValue = if ($event.signal) { $event.signal } else { $event.data }
                    $signal = Resolve-LegacyCompletionSignal -Signal ([string]$signalValue)
                    if ($signal) {
                        Set-CompletionResult -Result $result -Signal $signal
                        $foundCompletion = $true
                        break
                    }
                }
            }
            catch {
                # Not JSON or parsing failed, continue
            }
        }

        # If stream-json format, use finalText as output
        if ($isStreamJson -and $finalText) {
            $result.Output = $finalText

            $signal = Get-CompletionSignal -Output $finalText -AllowPlanningAlias
            if ($signal) {
                Set-CompletionResult -Result $result -Signal $signal
            }
        }
        # Fallback: Check normalized output for exact completion signals.
        elseif (-not $foundCompletion) {
            $signal = Get-CompletionSignal -Output $output -AllowPlanningAlias
            if ($signal) {
                Set-CompletionResult -Result $result -Signal $signal
            }
        }

        return $result
    }

    [bool] DetectCompletion([string]$output) {
        # Check JSON event stream
        $lines = $output -split '\r?\n' | Where-Object { $_.Trim() -ne '' }
        foreach ($line in $lines) {
            try {
                $event = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($event.type -eq 'completion_signal' -or $event.signal) {
                    if (Resolve-LegacyCompletionSignal -Signal ([string](if ($event.signal) { $event.signal } else { $event.data }))) {
                        return $true
                    }
                }
            }
            catch { }
        }

        return [bool](Get-CompletionSignal -Output $output -AllowPlanningAlias)
    }

    [string[]] BuildArgs([object]$config) {
        return $this.BuildArgs($config, $false)
    }

    [string[]] BuildArgs([object]$config, [bool]$verbose) {
        # Modern: Adapter builds args
        $args = @("exec", "--skip-permissions-unsafe")
        
        if ($config.model) {
            $args += @("--model", $config.model)
        }
        
        # Adapter controls output format based on verbose mode
        $format = if ($verbose) { "stream-json" } else { "json" }
        $args += @("--output-format", $format)
        
        if ($verbose) {
            Emit-Log -Level "debug" -Message "Verbose mode: using stream-json output format" -Component "droid"
        }
        
        return $args
    }
}

# ============================================================================
# CLAUDE ADAPTER (Anthropic)
# ============================================================================

class ClaudeAdapter {
    [string] FormatPrompt([string]$prompt) {
        # Claude accepts raw text in interactive mode
        # Could wrap in JSON for structured input if needed
        return $prompt
    }

    [hashtable] ParseResponse([string]$output) {
        $result = @{
            Output     = $output
            IsComplete = $false
            NextMode   = $null
            Error      = $null
        }

        $signal = Get-CompletionSignal -Output $output -AllowPlanningAlias
        if ($signal) {
            Set-CompletionResult -Result $result -Signal $signal
        }

        return $result
    }

    [bool] DetectCompletion([string]$output) {
        return [bool](Get-CompletionSignal -Output $output -AllowPlanningAlias)
    }

    [string[]] BuildArgs([object]$config) {
        return $this.BuildArgs($config, $false)
    }

    [string[]] BuildArgs([object]$config, [bool]$verbose) {
        # Modern: Adapter builds args
        $args = @("-p")  # Pipe mode
        
        if ($config.model) {
            $args += @("--model", $config.model)
        }
        
        $args += @("--output-format", "text")
        
        return $args
    }
}

# ============================================================================
# CODEX ADAPTER (OpenAI)
# ============================================================================

class CodexAdapter {
    [string] FormatPrompt([string]$prompt) {
        # Codex expects plain text via stdin
        return $prompt
    }

    [hashtable] ParseResponse([string]$output) {
        $result = @{
            Output     = $output
            IsComplete = $false
            NextMode   = $null
            Error      = $null
        }

        $signal = Get-CompletionSignal -Output $output -AllowPlanningAlias
        if ($signal) {
            Set-CompletionResult -Result $result -Signal $signal
        }

        return $result
    }

    [bool] DetectCompletion([string]$output) {
        return [bool](Get-CompletionSignal -Output $output -AllowPlanningAlias)
    }

    [string[]] BuildArgs([object]$config) {
        return $this.BuildArgs($config, $false)
    }

    [string[]] BuildArgs([object]$config, [bool]$verbose) {
        # Modern: Adapter builds args
        # NOTE: danger-full-access is required because v0.98.0 research preview ignores workspace-write config/flags
        # See .felix/README.md - Codex Sandbox Configuration for details
        # CRITICAL: exec subcommand MUST come AFTER other flags (at start), not at end
        $args = @(
            "exec",
            "-C", ".",
            "-s", "danger-full-access",
            "--color", "never",
            "-"
        )
        
        return $args
    }
}

# ============================================================================
# GEMINI ADAPTER (Google)
# ============================================================================

class GeminiAdapter {
    [string] FormatPrompt([string]$prompt) {
        # Gemini accepts plain text
        return $prompt
    }

    [hashtable] ParseResponse([string]$output) {
        $result = @{
            Output     = $output
            IsComplete = $false
            NextMode   = $null
            Error      = $null
        }

        $signal = Get-CompletionSignal -Output $output -AllowPlanningAlias
        if ($signal) {
            Set-CompletionResult -Result $result -Signal $signal
        }

        return $result
    }

    [bool] DetectCompletion([string]$output) {
        return [bool](Get-CompletionSignal -Output $output -AllowPlanningAlias)
    }

    [string[]] BuildArgs([object]$config) {
        return $this.BuildArgs($config, $false)
    }

    [string[]] BuildArgs([object]$config, [bool]$verbose) {
        # Modern: Adapter builds args
        $args = @()
        
        if ($config.model) {
            $args += @("-m", $config.model)
        }
        else {
            $args += @("-m", "auto")
        }
        
        $args += @("--approval-mode=auto_edit", "--output-format", "json")
        
        return $args
    }
}

# ============================================================================
# COPILOT ADAPTER (GitHub Copilot CLI)
# ============================================================================

class CopilotAdapter {
    [string] FormatPrompt([string]$prompt) {
        # Copilot CLI accepts the prompt directly via -p in programmatic mode.
        return $prompt
    }

    [hashtable] ParseResponse([string]$output) {
        $result = @{
            Output     = $output
            IsComplete = $false
            NextMode   = $null
            Error      = $null
        }

        if ($output -match 'Model\s+"[^"]+"\s+from\s+--model\s+flag\s+is\s+not\s+available') {
            $result.Error = ($matches[0]).Trim()
            return $result
        }

        $finalJson = Get-FinalJsonResponseText -Output $output
        if ($finalJson) {
            if ($finalJson -ne $output) {
                Emit-Log -Level "info" -Message "Using extracted final JSON payload from mixed stream output" -Component "agent"
            }
            $result.Output = $finalJson
        }

        $signal = Get-CompletionSignal -Output $result.Output -AllowPlanningAlias
        if ($signal) {
            Set-CompletionResult -Result $result -Signal $signal
        }

        return $result
    }

    [bool] DetectCompletion([string]$output) {
        return [bool](Get-CompletionSignal -Output $output -AllowPlanningAlias)
    }

    [string[]] BuildArgs([object]$config) {
        return $this.BuildArgs($config, $false)
    }

    [string[]] BuildArgs([object]$config, [bool]$verbose) {
        $args = @("--autopilot", "-s", "--no-color")

        $allowAll = $true
        if ($config.PSObject.Properties["allow_all"]) {
            $allowAll = [bool]$config.allow_all
        }
        if ($allowAll) {
            $args += "--yolo"
        }

        $noAskUser = $true
        if ($config.PSObject.Properties["no_ask_user"]) {
            $noAskUser = [bool]$config.no_ask_user
        }
        if ($noAskUser) {
            $args += "--no-ask-user"
        }

        if ($config.PSObject.Properties["max_autopilot_continues"] -and $config.max_autopilot_continues) {
            $args += @("--max-autopilot-continues", [string]$config.max_autopilot_continues)
        }

        if ($config.PSObject.Properties["custom_agent"] -and -not [string]::IsNullOrWhiteSpace([string]$config.custom_agent)) {
            $args += @("--agent", [string]$config.custom_agent)
        }

        if ($config.model) {
            $args += @("--model", $config.model)
        }

        return $args
    }
}

# ============================================================================
# ADAPTER FACTORY
# ============================================================================

function Get-AgentDefaults {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AdapterType
    )

    switch ($AdapterType.ToLower()) {
        "droid" {
            return @{
                adapter           = "droid"
                executable        = "droid"
                model             = "claude-opus-4-5-20251101"
                working_directory = "."
                environment       = @{}
            }
        }
        "claude" {
            return @{
                adapter           = "claude"
                executable        = "claude"
                model             = "sonnet"
                working_directory = "."
                environment       = @{}
            }
        }
        "codex" {
            return @{
                adapter           = "codex"
                executable        = "codex"
                model             = "gpt-5.2-codex"
                working_directory = "."
                environment       = @{}
            }
        }
        "gemini" {
            return @{
                adapter           = "gemini"
                executable        = "gemini"
                model             = "auto"
                working_directory = "."
                environment       = @{}
            }
        }
        "copilot" {
            return @{
                adapter                 = "copilot"
                executable              = "copilot"
                model                   = ""
                working_directory       = "."
                environment             = @{}
                allow_all               = $true
                no_ask_user             = $true
                max_autopilot_continues = 10
                custom_agent            = ""
            }
        }
        default {
            return @{
                adapter           = $AdapterType
                executable        = $AdapterType
                model             = ""
                working_directory = "."
                environment       = @{}
            }
        }
    }
}

function Get-AgentAdapter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AdapterType
    )

    switch ($AdapterType.ToLower()) {
        "droid" {
            return [DroidAdapter]::new()
        }
        "claude" {
            return [ClaudeAdapter]::new()
        }
        "codex" {
            return [CodexAdapter]::new()
        }
        "gemini" {
            return [GeminiAdapter]::new()
        }
        "copilot" {
            return [CopilotAdapter]::new()
        }
        default {
            Write-Error "Unknown adapter type: $AdapterType. Supported: droid, claude, codex, gemini, copilot"
            return $null
        }
    }
}

function Get-AgentInvocation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AdapterType,

        [Parameter(Mandatory = $true)]
        $Config,

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $false)]
        [bool]$VerboseMode = $false
    )

    $adapter = Get-AgentAdapter -AdapterType $AdapterType
    if (-not $adapter) {
        return $null
    }

    $formattedPrompt = $adapter.FormatPrompt($Prompt)
    $arguments = @($adapter.BuildArgs($Config, $VerboseMode))
    $promptMode = "stdin"

    # Use stdin prompt transport for all adapters, including Copilot.
    # This avoids Windows command-line length limits when prompts are large.

    return @{
        Adapter         = $adapter
        FormattedPrompt = $formattedPrompt
        Arguments       = $arguments
        PromptMode      = $promptMode
    }
}
