param(
    [Parameter(Mandatory = $true)]
    [hashtable]$HookData,
    
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    
    [Parameter(Mandatory = $true)]
    $PluginConfig
)

# Extract webhook URL from config
$webhookUrl = $PluginConfig.config.webhook_url

if (-not $webhookUrl) {
    Write-Verbose "[slack-notifier] No webhook URL configured, skipping notification"
    return @{ Success = $true }
}

# Build Slack message based on LLM execution result
$mode = $HookData.Mode
$reqId = $HookData.CurrentRequirement.id
$reqTitle = $HookData.CurrentRequirement.title
$exitCode = $HookData.ExitCode

$color = if ($exitCode -eq 0) { "good" } else { "danger" }
$status = if ($exitCode -eq 0) { " Success" } else { " Failed" }

$message = @{
    attachments = @(
        @{
            color = $color
            title = "Felix Agent - LLM Execution Complete"
            fields = @(
                @{ title = "Requirement"; value = "$reqId - $reqTitle"; short = $false }
                @{ title = "Mode"; value = $mode.ToUpper(); short = $true }
                @{ title = "Status"; value = $status; short = $true }
                @{ title = "Run ID"; value = $RunId; short = $false }
            )
            footer = "Felix Slack Notifier"
            ts = [int][double]::Parse((Get-Date -UFormat %s))
        }
    )
} | ConvertTo-Json -Depth 10

try {
    if ($PluginConfig.config.notify_on_success -or ($exitCode -ne 0 -and $PluginConfig.config.notify_on_failure)) {
        $response = Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $message -ContentType 'application/json'
        Write-Verbose "[slack-notifier] Notification sent successfully"
    }
    
    return @{ Success = $true }
}
catch {
    Write-Warning "[slack-notifier] Failed to send Slack notification: $_"
    return @{ Success = $false; ErrorMessage = $_.Exception.Message }
}
