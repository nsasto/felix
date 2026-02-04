param(
    [Parameter(Mandatory = $true)]
    [hashtable]$HookData,
    
    [Parameter(Mandatory = $true)]
    [string]$RunId,
    
    [Parameter(Mandatory = $true)]
    $PluginConfig
)

# Record LLM execution metrics
$llmEndTime = Get-Date
Set-PluginTransientState -PluginName "metrics-collector" -RunId $RunId -Key "llm_end_time" -Value ($llmEndTime.ToString("o"))
Set-PluginTransientState -PluginName "metrics-collector" -RunId $RunId -Key "llm_exit_code" -Value $HookData.ExitCode

# Read output file to get size
$outputPath = $HookData.OutputPath
if (Test-Path $outputPath) {
    $outputSize = (Get-Item $outputPath).Length
    Set-PluginTransientState -PluginName "metrics-collector" -RunId $RunId -Key "llm_output_size" -Value $outputSize
}

Write-Verbose "[metrics-collector] LLM execution completed with exit code $($HookData.ExitCode)"

return @{ Success = $true }
