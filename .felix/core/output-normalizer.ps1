$script:FelixOutputNoisePatterns = @(
    '^Loading personal and system profiles took .*',
    '^PowerShell\s+\d+(\.\d+)*$',
    '^Windows PowerShell$',
    '^Copyright \(C\) Microsoft Corporation\..*',
    '^Install the latest PowerShell for new features.*'
)

function Remove-AnsiEscapeSequences {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    return ($Text -replace ([string][char]27 + '\[[0-9;?]*[ -/]*[@-~]'), '')
}

function Remove-AgentWrapperNoise {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $start = 0
    $end = $Lines.Count - 1

    while ($start -le $end) {
        $line = $Lines[$start]
        if ([string]::IsNullOrWhiteSpace($line)) {
            $start++
            continue
        }

        $isNoise = $false
        foreach ($pattern in $script:FelixOutputNoisePatterns) {
            if ($line -match $pattern) {
                $isNoise = $true
                break
            }
        }

        if (-not $isNoise) {
            break
        }

        $start++
    }

    while ($end -ge $start -and [string]::IsNullOrWhiteSpace($Lines[$end])) {
        $end--
    }

    if ($start -gt $end) {
        return @()
    }

    return $Lines[$start..$end]
}

function Normalize-AgentOutput {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Output,

        [Parameter(Mandatory = $false)]
        [string]$AdapterType = ""
    )

    if ($null -eq $Output) {
        return ""
    }

    $normalized = $Output -replace "`r`n", "`n" -replace "`r", "`n"
    if ($normalized.Length -gt 0 -and $normalized[0] -eq [char]0xFEFF) {
        $normalized = $normalized.Substring(1)
    }

    $normalized = Remove-AnsiEscapeSequences -Text $normalized
    $lines = @($normalized -split "`n")
    $lines = Remove-AgentWrapperNoise -Lines $lines

    return ($lines -join "`n")
}