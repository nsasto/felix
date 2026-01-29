param(
    [Parameter(Mandatory = $true)]
    [hashtable]$HookData,
    
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    
    [Parameter(Mandatory = $true)]
    $PluginConfig
)

# Record iteration start time
$startTime = Get-Date

Set-PluginTransientState -PluginName "metrics-collector" -RunId $RunId -Key "iteration_start_time" -Value ($startTime.ToString("o"))
Set-PluginTransientState -PluginName "metrics-collector" -RunId $RunId -Key "iteration_number" -Value $HookData.Iteration

Write-Verbose "[metrics-collector] Iteration $($HookData.Iteration) started at $startTime"

return @{ ContinueIteration = $true }
