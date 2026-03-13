param(
    [Parameter(Mandatory = $true)]
    [hashtable]$HookData,
    
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    
    [Parameter(Mandatory = $true)]
    $PluginConfig
)

$webhookUrl = $PluginConfig.config.webhook_url

if (-not $webhookUrl) {
    return @{ OverrideResult = $false }
}

$reqId = $HookData.CurrentRequirement.id
$reqTitle = $HookData.CurrentRequirement.title
$passed = $HookData.ValidationPassed

$color = if ($passed) { "good" } else { "warning" }
$emoji = if ($passed) { "" } else { "" }

$message = @{
    attachments = @(
        @{
            color = $color
            title = "$emoji Felix - Requirement Validation Complete"
            fields = @(
                @{ title = "Requirement"; value = "$reqId - $reqTitle"; short = $false }
                @{ title = "Result"; value = $(if ($passed) { "PASSED" } else { "FAILED" }); short = $true }
                @{ title = "Run ID"; value = $RunId; short = $true }
            )
            footer = "Felix Slack Notifier"
            ts = [int][double]::Parse((Get-Date -UFormat %s))
        }
    )
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $message -ContentType 'application/json' | Out-Null
    Write-Verbose "[slack-notifier] Validation notification sent"
}
catch {
    Write-Warning "[slack-notifier] Failed to send notification: $_"
}

return @{ OverrideResult = $false }
