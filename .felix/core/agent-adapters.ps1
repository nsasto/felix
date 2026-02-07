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
        # Parse Droid's response for completion signals
        $result = @{
            Output     = $output
            IsComplete = $false
            NextMode   = $null
            Error      = $null
        }

        # Try parsing JSON event stream first (--output-format json)
        $lines = $output -split '\r?\n' | Where-Object { $_.Trim() -ne '' }
        $foundCompletion = $false
        
        foreach ($line in $lines) {
            try {
                $event = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($event.type -eq 'completion_signal' -or $event.signal) {
                    $signal = if ($event.signal) { $event.signal } else { $event.data }
                    if ($signal -match 'PLANNING_COMPLETE') {
                        $result.IsComplete = $true
                        $result.NextMode = "building"
                        $foundCompletion = $true
                        break
                    }
                    elseif ($signal -match 'ALL_REQUIREMENTS_MET') {
                        $result.IsComplete = $true
                        $result.NextMode = "complete"
                        $foundCompletion = $true
                        break
                    }
                }
            }
            catch {
                # Not JSON, continue
            }
        }

        # Fallback: Check for XML completion signals (backward compatibility)
        if (-not $foundCompletion) {
            if ($output -match '(?s)<promise>\s*PLANNING_COMPLETE\s*</promise>') {
                $result.IsComplete = $true
                $result.NextMode = "building"
            }
            elseif ($output -match '(?s)<promise>\s*ALL_REQUIREMENTS_MET\s*</promise>') {
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
        return $output -match '(?s)<promise>\s*(PLANNING_COMPLETE|ALL_REQUIREMENTS_MET)\s*</promise>'
    }

    [string[]] BuildArgs([object]$config) {
        # Return agent args from config
        return $config.args
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
        # Claude args from config, ensure output format is set
        $args = @($config.args)
        
        # Add output format if not specified
        if ($args -notcontains "--output-format") {
            $args += @("--output-format", "text")
        }

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
        return $config.args
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
        $args = @($config.args)
        
        # Ensure JSON output for easier parsing
        if ($args -notcontains "--output-format") {
            $args += @("--output-format", "json")
        }

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
