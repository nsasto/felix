param(
    [Parameter(Mandatory = $true)]
    [hashtable]$HookData,
    
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    
    [Parameter(Mandatory = $true)]
    $PluginConfig
)

# Calculate iteration duration
$startTimeStr = Get-PluginTransientState -PluginName "metrics-collector" -RunId $RunId -Key "iteration_start_time"
if ($startTimeStr) {
    $startTime = [DateTime]::Parse($startTimeStr)
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    # Collect all metrics for this iteration
    $metrics = @{
        iteration = Get-PluginTransientState -PluginName "metrics-collector" -RunId $RunId -Key "iteration_number"
        requirement_id = $HookData.CurrentRequirement.id
        mode = $HookData.State.last_mode
        outcome = $HookData.Outcome
        duration_seconds = [math]::Round($duration, 2)
        llm_exit_code = Get-PluginTransientState -PluginName "metrics-collector" -RunId $RunId -Key "llm_exit_code"
        llm_output_size = Get-PluginTransientState -PluginName "metrics-collector" -RunId $RunId -Key "llm_output_size"
        timestamp = (Get-Date).ToString("o")
    }
    
    # Append metrics to persistent log
    $metricsLog = Get-PluginPersistentState -PluginName "metrics-collector" -Key "metrics"
    if (-not $metricsLog) {
        $metricsLog = @()
    }
    
    $metricsLog += $metrics
    Set-PluginPersistentState -PluginName "metrics-collector" -Key "metrics" -Value $metricsLog
    
    Write-Verbose "[metrics-collector] Iteration completed in $duration seconds"
    
    # Also write to run directory for per-run analysis
    $runMetricsPath = Join-Path "runs" $RunId "metrics.json"
    if (Test-Path (Split-Path $runMetricsPath)) {
        $metrics | ConvertTo-Json -Depth 5 | Set-Content $runMetricsPath
    }
}

return @{ ShouldContinue = $true }
