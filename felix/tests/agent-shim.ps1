param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"

$prompt = [Console]::In.ReadToEnd()
$promptLen = if ($null -eq $prompt) { 0 } else { $prompt.Length }

$cwd = (Get-Location).Path
$envValue = $env:FELIX_AGENT_TEST

Write-Output "__AGENT_SHIM__=1"
Write-Output "__AGENT_CWD__=$cwd"
Write-Output "__AGENT_ENV__=$envValue"
Write-Output "__AGENT_PROMPT_LEN__=$promptLen"
Write-Output "**Task Completed:** Smoke test agent invocation"
Write-Output "<promise>ALL_REQUIREMENTS_MET</promise>"

exit 0
