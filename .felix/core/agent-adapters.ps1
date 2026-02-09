# Agent Adapters - Multi-Agent Support for Felix
# Provides adapter pattern for different LLM CLIs (Droid, Claude, Codex, Gemini)

$ErrorActionPreference = "Stop"

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
                    $signal = if ($event.signal) { $event.signal } else { $event.data }
                    if ($signal -match 'PLANNING_COMPLETE') {
                        $result.IsComplete = $true
                        $result.NextMode = "building"
                        $foundCompletion = $true
                        break
                    }
                    elseif ($signal -match 'TASK_COMPLETE') {
                        $result.IsComplete = $true
                        $result.NextMode = "continue"
                        $foundCompletion = $true
                        break
                    }
                    elseif ($signal -match 'ALL_COMPLETE') {
                        $result.IsComplete = $true
                        $result.NextMode = "complete"
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
            
            # Check finalText for completion signals
            if ($finalText -match '(?s)<promise>\s*PLANNING_COMPLETE\s*</promise>') {
                $result.IsComplete = $true
                $result.NextMode = "building"
            }
            elseif ($finalText -match '(?s)<promise>\s*TASK_COMPLETE\s*</promise>') {
                $result.IsComplete = $true
                $result.NextMode = "continue"
            }
            elseif ($finalText -match '(?s)<promise>\s*ALL_COMPLETE\s*</promise>') {
                $result.IsComplete = $true
                $result.NextMode = "complete"
            }
        }
        # Fallback: Check for XML completion signals (backward compatibility)
        elseif (-not $foundCompletion) {
            if ($output -match '(?s)<promise>\s*PLANNING_COMPLETE\s*</promise>') {
                $result.IsComplete = $true
                $result.NextMode = "building"
            }
            elseif ($output -match '(?s)<promise>\s*TASK_COMPLETE\s*</promise>') {
                $result.IsComplete = $true
                $result.NextMode = "continue"
            }
            elseif ($output -match '(?s)<promise>\s*ALL_COMPLETE\s*</promise>') {
                $result.IsComplete = $true
                $result.NextMode = "complete"
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
                    return $true
                }
            }
            catch { }
        }
        
        # Fallback: XML signals
        return $output -match '(?s)<promise>\s*(PLANNING_COMPLETE|TASK_COMPLETE|ALL_COMPLETE)\s*</promise>'
    }

    [string[]] BuildArgs([object]$config) {
        return $this.BuildArgs($config, $false)
    }

    [string[]] BuildArgs([object]$config, [bool]$verbose) {
        # Legacy: If args provided in config, use them (backward compat)
        if ($config.args -and $config.args.Count -gt 0) {
            Emit-Log -Level "warn" -Message "Using legacy 'args' from agents.json - consider removing, adapter controls args now" -Component "config"
            return $config.args
        }
        
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

        # Try parsing JSON output first
        try {
            $json = $output | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($json.status -eq "complete") {
                $result.IsComplete = $true
                $result.NextMode = "complete"
            }
            elseif ($json.next_phase -eq "building") {
                $result.IsComplete = $true
                $result.NextMode = "building"
            }
        }
        catch {
            # Fallback: Look for text markers
            if ($output -match '(?i)(planning\s+complete|ready\s+to\s+build)') {
                $result.IsComplete = $true
                $result.NextMode = "building"
            }
            elseif ($output -match '(?i)(all\s+tasks?\s+complete|requirement\s+met)') {
                $result.IsComplete = $true
                $result.NextMode = "complete"
            }
        }

        return $result
    }

    [bool] DetectCompletion([string]$output) {
        # Check for completion markers
        if ($output -match '"status"\s*:\s*"complete"') { return $true }
        if ($output -match '(?i)(planning\s+complete|all\s+tasks?\s+complete|requirement\s+met)') { return $true }
        return $false
    }

    [string[]] BuildArgs([object]$config) {
        return $this.BuildArgs($config, $false)
    }

    [string[]] BuildArgs([object]$config, [bool]$verbose) {
        # Legacy: If args provided in config, use them
        if ($config.args -and $config.args.Count -gt 0) {
            Emit-Log -Level "warn" -Message "Using legacy 'args' from agents.json - consider removing, adapter controls args now" -Component "config"
            return $config.args
        }
        
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

        # Codex uses diff-based workflow
        # Look for "Applied changes" or "No changes needed"
        if ($output -match '(?i)(applied\s+\d+\s+change|changes?\s+applied|committed)') {
            # Changes were made, check if planning or building
            if ($output -match '(?i)plan\s+created') {
                $result.IsComplete = $true
                $result.NextMode = "building"
            }
            else {
                # Assume building iteration complete
                $result.IsComplete = $true
                $result.NextMode = "building"
            }
        }
        elseif ($output -match '(?i)(no\s+changes?\s+needed|already\s+complete|task\s+complete)') {
            $result.IsComplete = $true
            $result.NextMode = "complete"
        }

        return $result
    }

    [bool] DetectCompletion([string]$output) {
        if ($output -match '(?i)(applied|committed|no\s+changes?\s+needed|complete)') { return $true }
        return $false
    }

    [string[]] BuildArgs([object]$config) {
        return $this.BuildArgs($config, $false)
    }

    [string[]] BuildArgs([object]$config, [bool]$verbose) {
        # Legacy: If args provided in config, use them
        if ($config.args -and $config.args.Count -gt 0) {
            Emit-Log -Level "warn" -Message "Using legacy 'args' from agents.json - consider removing, adapter controls args now" -Component "config"
            return $config.args
        }
        
        # Modern: Adapter builds args
        $args = @(
            "-C", ".",
            "-s", "workspace-write",
            "-a", "never",
            "exec",
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

        # Gemini supports JSON streaming
        try {
            # Try parsing as JSON
            $json = $output | ConvertFrom-Json -ErrorAction SilentlyContinue
            
            if ($json.phase_complete) {
                $result.IsComplete = $true
                $result.NextMode = if ($json.next_phase) { $json.next_phase } else { "building" }
            }
            elseif ($json.status -eq "done") {
                $result.IsComplete = $true
                $result.NextMode = "complete"
            }
        }
        catch {
            # Fallback: Text pattern matching
            if ($output -match '(?i)(phase\s+complete|ready\s+for\s+next)') {
                $result.IsComplete = $true
                $result.NextMode = "building"
            }
            elseif ($output -match '(?i)(all\s+done|task\s+complete|requirements?\s+met)') {
                $result.IsComplete = $true
                $result.NextMode = "complete"
            }
        }

        return $result
    }

    [bool] DetectCompletion([string]$output) {
        if ($output -match '"phase_complete"\s*:\s*true') { return $true }
        if ($output -match '(?i)(phase\s+complete|all\s+done|task\s+complete)') { return $true }
        return $false
    }

    [string[]] BuildArgs([object]$config) {
        return $this.BuildArgs($config, $false)
    }

    [string[]] BuildArgs([object]$config, [bool]$verbose) {
        # Legacy: If args provided in config, use them
        if ($config.args -and $config.args.Count -gt 0) {
            Emit-Log -Level "warn" -Message "Using legacy 'args' from agents.json - consider removing, adapter controls args now" -Component "config"
            return $config.args
        }
        
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
# ADAPTER FACTORY
# ============================================================================

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
        default {
            Write-Error "Unknown adapter type: $AdapterType. Supported: droid, claude, codex, gemini"
            return $null
        }
    }
}
