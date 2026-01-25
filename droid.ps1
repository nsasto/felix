#!/usr/bin/env pwsh
# Mock droid exec for testing Felix agent
# Takes prompt from stdin, outputs mock LLM response

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

# Read prompt from stdin
$prompt = [Console]::In.ReadToEnd()

# Mock response - for testing, assume completion after first iteration
$output = @"
Mock LLM Response: Processing the prompt...

Based on the context, I have implemented the necessary changes for S-0001.

<promise>COMPLETE</promise>
"@

Write-Host $output