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
    return @{ ShouldRetry = $false }
}

$reqId = $HookData.CurrentRequirement.id
$reqTitle = $HookData.CurrentRequirement.title
$retryCount = $HookData.RetryCount
$validationResult = $HookData.ValidationResult

# Build failed commands summary
$failedCommands = $validationResult.failed_commands | ForEach-Object {
    "• [$($_.type)] ``$($_.command)`` (exit: $($_.exit_code))"
}

$message = @{
    attachments = @(
        @{
            color = "danger"
            title = "🚨 Felix - Backpressure Validation Failed"
            fields = @(
                @{ title = "Requirement"; value = "$reqId - $reqTitle"; short = $false }
                @{ title = "Retry Count"; value = "$retryCount"; short = $true }
                @{ title = "Run ID"; value = $RunId; short = $true }
                @{ title = "Failed Commands"; value = ($failedCommands -join "`n"); short = $false }
            )
            footer = "Felix Slack Notifier"
            ts = [int][double]::Parse((Get-Date -UFormat %s))
        }
    )
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $message -ContentType 'application/json' | Out-Null
    Write-Verbose "[slack-notifier] Backpressure failure notification sent"
}
catch {
    Write-Warning "[slack-notifier] Failed to send notification: $_"
}

return @{ ShouldRetry = $false }
