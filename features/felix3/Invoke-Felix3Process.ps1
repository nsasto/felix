Set-StrictMode -Version Latest

function Get-Felix3ProcessProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] }; return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Resolve-Felix3Executable {
    param([Parameter(Mandatory = $true)][string]$Executable)
    $command = Get-Command $Executable -CommandType Application -ErrorAction Stop | Select-Object -First 1
    if ($command.Source) { return [string]$command.Source }
    return [string]$command.Path
}

function ConvertTo-Felix3ArgumentString {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $quoted = foreach ($argument in $Arguments) {
        $value = [string]$argument
        if ($value -notmatch '[\s"]') { $value; continue }
        $escaped = $value -replace '(\\*)"', '$1$1\"'
        $escaped = $escaped -replace '(\\+)$', '$1$1'
        '"' + $escaped + '"'
    }
    return ($quoted -join ' ')
}

function Invoke-Felix3Process {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [Parameter(Mandatory)][string]$RawOutputPath,
        [Parameter(Mandatory)][string]$StderrPath,
        [scriptblock]$OnOutputLine,
        [scriptblock]$OnErrorLine,
        [string]$CancelTokenPath,
        [scriptblock]$OnProcessStart,
        [scriptblock]$OnProcessExit
    )
    if (-not $Process.Start()) { throw 'Harness process did not start.' }
    if ($OnProcessStart) { & $OnProcessStart $Process.Id }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $outWriter = New-Object System.IO.StreamWriter($RawOutputPath, $false, $encoding)
    $errWriter = New-Object System.IO.StreamWriter($StderrPath, $false, $encoding)
    $stdout = New-Object System.Text.StringBuilder
    $stderr = New-Object System.Text.StringBuilder
    try {
        $outTask = $Process.StandardOutput.ReadLineAsync()
        $errTask = $Process.StandardError.ReadLineAsync()
        $Process.StandardInput.Write($Prompt)
        $Process.StandardInput.Close()
        $outDone = $false; $errDone = $false; $cancelled = $false; $questionRequested = $false
        while (-not ($outDone -and $errDone)) {
            if (-not $cancelled -and $CancelTokenPath -and (Test-Path -LiteralPath $CancelTokenPath -PathType Leaf) -and -not $Process.HasExited) {
                $cancelled = $true
                try { $Process.Kill($true) } catch { try { & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null } catch { try { $Process.Kill() } catch { } } }
            }
            if (-not $outDone -and $outTask.IsCompleted) {
                $line = $outTask.GetAwaiter().GetResult()
                if ($null -eq $line) { $outDone = $true }
                else {
                    [void]$stdout.AppendLine($line); $outWriter.WriteLine($line); $outWriter.Flush()
                    if ($OnOutputLine) {
                        $control = & $OnOutputLine $line
                        if ($control -eq 'question.requested' -and -not $Process.HasExited) {
                            $questionRequested = $true
                            try { $Process.Kill($true) } catch { try { & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null } catch { try { $Process.Kill() } catch { } } }
                        }
                    }
                    $outTask = $Process.StandardOutput.ReadLineAsync()
                }
            }
            if (-not $errDone -and $errTask.IsCompleted) {
                $line = $errTask.GetAwaiter().GetResult()
                if ($null -eq $line) { $errDone = $true }
                else {
                    [void]$stderr.AppendLine($line); $errWriter.WriteLine($line); $errWriter.Flush()
                    if ($OnErrorLine) { & $OnErrorLine $line }
                    $errTask = $Process.StandardError.ReadLineAsync()
                }
            }
            if (-not ($outDone -and $errDone)) { Start-Sleep -Milliseconds 20 }
        }
        $Process.WaitForExit()
        if ($OnProcessExit) { & $OnProcessExit $Process.Id $cancelled }
        return [pscustomobject]@{ Stdout = $stdout.ToString(); Stderr = $stderr.ToString(); ExitCode = [int]$Process.ExitCode; Cancelled = $cancelled; QuestionRequested = $questionRequested }
    }
    finally { $outWriter.Dispose(); $errWriter.Dispose() }
}
