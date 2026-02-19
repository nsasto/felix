# Process batch upload file manually
$batchFile = Get-ChildItem .felix\outbox\*batch*.jsonl | Select-Object -First 1
if (-not $batchFile) {
    Write-Host "No batch upload file found"
    exit
}

$data = Get-Content $batchFile.FullName -Raw | ConvertFrom-Json
$runId = $data.run_id
$files = $data.files

# Get API key
$config = Get-Content .felix\config.json -Raw | ConvertFrom-Json
$apiKey = $config.sync.api_key
$baseUrl = $config.sync.base_url

Write-Host "Processing batch upload for run: $runId"
Write-Host "Files: $($files.Count)"

# Build manifest (same format as test script)
$manifest = @()
foreach ($file in $files) {
    $manifest += @{
        path = $file.path
        sha256 = $file.sha256
        size_bytes = $file.size_bytes
        content_type = $file.content_type
    }
}

Write-Host "Manifest:"
$manifest | ConvertTo-Json | Write-Host

# Build multipart body (EXACTLY like test script)
$boundary = [System.Guid]::NewGuid().ToString()
$LF = "`r`n"
$bodyBytes = [System.Collections.Generic.List[byte]]::new()

$addString = {
    param([string]$str)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($str)
    $bodyBytes.AddRange($bytes)
}

# Add manifest
$manifestJson = $manifest | ConvertTo-Json -Depth 10 -Compress
& $addString "--$boundary$LF"
& $addString 'Content-Disposition: form-data; name="manifest"'
& $addString "$LF$LF"
& $addString $manifestJson
& $addString $LF

# Add files  
foreach ($file in $files) {
    $fileBytes = [System.IO.File]::ReadAllBytes($file.local_path)
    & $addString "--$boundary$LF"
    & $addString "Content-Disposition: form-data; name=`"files`"; filename=`"$($file.path)`"$LF"
    & $addString "Content-Type: $($file.content_type)$LF$LF"
    $bodyBytes.AddRange($fileBytes)
    & $addString $LF
}

& $addString "--$boundary--$LF"

$body = $bodyBytes.ToArray()

Write-Host "Body size: $($body.Length) bytes"

# Send request
$url = "$baseUrl/api/runs/$runId/files"
$headers = @{
    "Content-Type" = "multipart/form-data; boundary=$boundary"
    "Authorization" = "Bearer $apiKey"
}

try {
    $response = Invoke-WebRequest -Method POST -Uri $url -Headers $headers -Body $body -UseBasicParsing
    Write-Host "[SUCCESS] Status: $($response.StatusCode)"
    $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 5
    
    # Delete batch file on success
    Remove-Item $batchFile.FullName -Force
    Write-Host "Deleted batch file: $($batchFile.Name)"
}
catch {
    Write-Host "[FAILED] $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
        Write-Host "Status: $statusCode"
        
        $responseStream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($responseStream)
        $responseBody = $reader.ReadToEnd()
        $reader.Close()
        
        Write-Host "Response:"
        Write-Host $responseBody
    }
}
