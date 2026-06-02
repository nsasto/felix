<#
.SYNOPSIS
Agent tool allowlist checker and per-tool audit (Phase F5, F6).

.DESCRIPTION
Provides Test-ToolAllowed and Emit-ToolCallEvent.
Allowlist config lives in .felix/config.json under the "tools" key:
  {
    "allow":   ["search.*", "navigate.*", "query.requirements"],
    "deny":    [],
    "default": "allow"
  }

Default-allow on v1->v2 upgrade. Use 'felix tool harden' to flip to deny.
Every call emits a kind=tool.call event for audit purposes.
#>

function Test-ToolAllowed {
    <#
    .SYNOPSIS
    Returns $true if the given tool name is allowed by the allowlist config.
    Also emits a kind=tool.call audit event.

    .PARAMETER ToolName
    The tool name to check (e.g. "navigate.references", "search.code").

    .PARAMETER Config
    The Felix config object. Reads Config.tools.allow/deny/default.

    .PARAMETER RunId
    Current run ID for event emission (optional).

    .PARAMETER Caller
    Name of the caller (e.g. "droid", "agent") for the audit event.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ToolName,

        [Parameter(Mandatory=$false)]
        $Config,

        [Parameter(Mandatory=$false)]
        [string]$RunId = "",

        [Parameter(Mandatory=$false)]
        [string]$Caller = "agent"
    )

    $tools       = if ($Config -and $Config.tools) { $Config.tools } else { $null }
    $allowList   = if ($tools -and $tools.allow)   { @($tools.allow)  } else { @() }
    $denyList    = if ($tools -and $tools.deny)    { @($tools.deny)   } else { @() }
    $defaultMode = if ($tools -and $tools.default) { $tools.default   } else { "allow" }

    $allowed = Test-AllowlistDecision `
        -ToolName $ToolName `
        -AllowList $allowList `
        -DenyList $denyList `
        -DefaultMode $defaultMode

    # Emit audit event (F6)
    Emit-ToolCallEvent `
        -ToolName $ToolName `
        -Allowed $allowed `
        -Caller $Caller `
        -RunId $RunId

    return $allowed
}

function Test-AllowlistDecision {
    <#
    .SYNOPSIS
    Pure decision logic -- does not emit events. Used by tests.
    #>
    param(
        [string]$ToolName,
        [string[]]$AllowList = @(),
        [string[]]$DenyList  = @(),
        [string]$DefaultMode = "allow"
    )

    # Deny list checked first
    foreach ($pattern in $DenyList) {
        if (Test-ToolGlob -ToolName $ToolName -Pattern $pattern) { return $false }
    }

    # Allow list checked second
    if ($AllowList.Count -gt 0) {
        foreach ($pattern in $AllowList) {
            if (Test-ToolGlob -ToolName $ToolName -Pattern $pattern) { return $true }
        }
        # Not in allow list -- fall through to default
        if ($DefaultMode -ieq "deny") { return $false }
        return $true   # default-allow even when allow list is present (audit only)
    }

    # No allow list: honour default
    return ($DefaultMode -ine "deny")
}

function Test-ToolGlob {
    <#
    .SYNOPSIS
    Matches a tool name against a glob pattern.
    Only * is supported (matches any chars including dot).
    #>
    param([string]$ToolName, [string]$Pattern)

    $regex = '^' + [regex]::Escape($Pattern).Replace('\*', '.*') + '$'
    return $ToolName -imatch $regex
}

function Emit-ToolCallEvent {
    <#
    .SYNOPSIS
    Writes a kind=tool.call entry to the event bus (F6).
    #>
    param(
        [string]$ToolName,
        [bool]$Allowed,
        [string]$Caller = "agent",
        [string]$RunId  = "",
        [hashtable]$Args = @{}
    )

    # Emit-Event is available when running inside the Felix agent loop
    if (Get-Command Emit-Event -ErrorAction SilentlyContinue) {
        $payload = [ordered]@{
            tool    = $ToolName
            args    = $Args
            allowed = $Allowed
            caller  = $Caller
        }
        Emit-Event -Kind "tool.call" -RunId $RunId -Payload $payload
    }
}
