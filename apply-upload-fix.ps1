# Apply binary upload fix to http-client.ps1
$ErrorActionPreference = "Stop"

$file = '.felix/plugins/sync-http/http-client.ps1'
$lines = Get-Content $file

# Find the line with "try {" in the UploadBatchWithStatus method (around line 866)
$tryLineIndex = -1
for ($i = 860; $i -lt 880; $i++) {
    if ($lines[$i] -match '^\s+try \{$') {
        $tryLineIndex = $i
        break
    }
}

if ($tryLineIndex -eq -1) {
    Write-Host "ERROR: Could not find try block" -ForegroundColor Red
    exit 1
}

Write-Host "Found try block at line $($tryLineIndex + 1)" -ForegroundColor Cyan

# Find the matching closing brace for the try block
$braceCount = 0
$tryEndIndex = -1
for ($i = $tryLineIndex; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '\{') { $braceCount++ }
    if ($line -match '\}') { $braceCount-- }
    
    if ($i -gt $tryLineIndex -and $braceCount -eq 0 -and $line -match '^\s+\}$') {
        $tryEndIndex = $i
        break
    }
}

if ($tryEndIndex -eq -1) {
    Write-Host "ERROR: Could not find try block end" -ForegroundColor Red
    exit 1
}

Write-Host "Try block ends at line $($tryEndIndex + 1)" -ForegroundColor Cyan
Write-Host "Replacing lines $($tryLineIndex + 1) to $($tryEndIndex + 1)..." -ForegroundColor Yellow

# New try block content
$newTryBlock = @(
    '        try {',
    '            # Build multipart form data with binary files (not base64)',
    '            $boundary = [System.Guid]::NewGuid().ToString()',
    '            $contentType = "multipart/form-data; boundary=$boundary"',
    '            ',
    '            $LF = "`r`n"',
    '            $bodyBytes = [System.Collections.Generic.List[byte]]::new()',
    '            ',
    '            # Add manifest as JSON string field',
    '            $manifestJson = $manifest | ConvertTo-Json -Depth 10 -Compress',
    '            $bodyBytes.AddRange([System.Text.Encoding]::ASCII.GetBytes("--$boundary$LF"))',
    '            $bodyBytes.AddRange([System.Text.Encoding]::ASCII.GetBytes(''Content-Disposition: form-data; name="manifest"''))',
    '            $bodyBytes.AddRange([System.Text.Encoding]::ASCII.GetBytes("$LF$LF"))',
    '            $bodyBytes.AddRange([System.Text.Encoding]::ASCII.GetBytes($manifestJson))',
    '            $bodyBytes.AddRange([System.Text.Encoding]::ASCII.GetBytes($LF))',
    '            ',
    '            # Add each file as binary upload',
    '            foreach ($file in $validFiles) {',
    '                $fileBytes = [System.IO.File]::ReadAllBytes($file.local_path)',
    '                ',
    '                $bodyBytes.AddRange([System.Text.Encoding]::ASCII.GetBytes("--$boundary$LF"))',
    '                $bodyBytes.AddRange([System.Text.Encoding]::ASCII.GetBytes("Content-Disposition: form-data; name=`"files`"; filename=`"$($file.path)`"$LF"))',
    '                $bodyBytes.AddRange([System.Text.Encoding]::ASCII.GetBytes("Content-Type: $($file.content_type)$LF$LF"))',
    '                $bodyBytes.AddRange($fileBytes)',
    '                $bodyBytes.AddRange([System.Text.Encoding]::ASCII.GetBytes($LF))',
    '            }',
    '            ',
    '            $bodyBytes.AddRange([System.Text.Encoding]::ASCII.GetBytes("--$boundary--$LF"))',
    '            ',
    '            $body = $bodyBytes.ToArray()',
    '            ',
    '            $headers = @{',
    '                "Content-Type" = $contentType',
    '            }',
    '            if ($this.ApiKey) {',
    '                $headers["Authorization"] = "Bearer $($this.ApiKey)"',
    '            }',
    '            ',
    '            # Use Invoke-WebRequest for byte array body support',
    '            $params = @{',
    '                Method      = "POST"',
    '                Uri         = $url',
    '                Headers     = $headers',
    '                Body        = $body',
    '                TimeoutSec  = 120',
    '            }',
    '            ',
    '            $response = Invoke-WebRequest @params -UseBasicParsing',
    '            return @{',
    '                Success    = $true',
    '                StatusCode = $response.StatusCode',
    '                Error      = $null',
            '            }',
    '        }'
)

# Build new file content
$newLines = @()
$newLines += $lines[0..($tryLineIndex - 1)]  # Before try block
$newLines += $newTryBlock                     # New try block
$newLines += $lines[($tryEndIndex + 1)..($lines.Count - 1)]  # After try block

# Write back
$newLines | Set-Content $file -Encoding UTF8

Write-Host "SUCCESS: File updated! Lines replaced: $($tryEndIndex - $tryLineIndex + 1) -> $($newTryBlock.Count)" -ForegroundColor Green
