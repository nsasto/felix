# Test script for debugging file upload to backend
param(
    [string]$RunId = "3488ffc8-eef0-48da-8129-7f8a13d25504",  # Use existing run
    [string]$BaseUrl = "http://localhost:8080"
)

$ErrorActionPreference = "Stop"

# Get API key from config
$configPath = ".felix\config.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$apiKey = $config.sync.api_key

Write-Host "Testing file upload to: $BaseUrl/api/runs/$RunId/files" -ForegroundColor Cyan
Write-Host "API Key: $($apiKey.Substring(0,15))..." -ForegroundColor Gray

# Create test files
$testDir = "test-upload-temp"
if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
New-Item -ItemType Directory -Path $testDir | Out-Null

$file1 = Join-Path $testDir "test1.txt"
$file2 = Join-Path $testDir "test2.md"
"Hello from test1" | Out-File $file1 -Encoding UTF8 -NoNewline
"# Test markdown" | Out-File $file2 -Encoding UTF8 -NoNewline

# Calculate SHA256
function Get-FileSha256 {
    param([string]$path)
    $hash = Get-FileHash -Path $path -Algorithm SHA256
    return $hash.Hash.ToLower()
}

$file1Hash = Get-FileSha256 $file1
$file2Hash = Get-FileSha256 $file2

Write-Host ""
Write-Host "Test files created:" -ForegroundColor Green
Write-Host "  $file1 (SHA256: $file1Hash)" -ForegroundColor Gray
Write-Host "  $file2 (SHA256: $file2Hash)" -ForegroundColor Gray

# Build manifest
$manifest = @(
    @{
        path = "test1.txt"
        sha256 = $file1Hash
        size_bytes = (Get-Item $file1).Length
        content_type = "text/plain"
    },
    @{
        path = "test2.md"
        sha256 = $file2Hash
        size_bytes = (Get-Item $file2).Length
        content_type = "text/markdown"
    }
)

Write-Host ""
Write-Host "Manifest:" -ForegroundColor Cyan
$manifest | ConvertTo-Json -Depth 5 | Write-Host -ForegroundColor Gray

# Build multipart form data with binary files
$boundary = [System.Guid]::NewGuid().ToString()
Write-Host ""
Write-Host "Boundary: $boundary" -ForegroundColor Gray

$LF = "`r`n"
$bodyBytes = [System.Collections.Generic.List[byte]]::new()

# Helper to add string to body
$addString = {
    param([string]$str)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($str)
    $bodyBytes.AddRange($bytes)
    Write-Host "  Added string: $($str.Replace($LF, '<CRLF>'))" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Building multipart body..." -ForegroundColor Cyan

# Add manifest field
$manifestJson = $manifest | ConvertTo-Json -Depth 10 -Compress
Write-Host "Adding manifest field..." -ForegroundColor Yellow
& $addString "--$boundary$LF"
& $addString 'Content-Disposition: form-data; name="manifest"'
& $addString "$LF$LF"
& $addString $manifestJson
& $addString $LF

# Add file1
Write-Host "Adding file1..." -ForegroundColor Yellow
$file1Bytes = [System.IO.File]::ReadAllBytes($file1)
& $addString "--$boundary$LF"
& $addString "Content-Disposition: form-data; name=`"files`"; filename=`"test1.txt`"$LF"
& $addString "Content-Type: text/plain$LF$LF"
$bodyBytes.AddRange($file1Bytes)
Write-Host "  Added $($file1Bytes.Length) bytes of file content" -ForegroundColor DarkGray
& $addString $LF

# Add file2
Write-Host "Adding file2..." -ForegroundColor Yellow
$file2Bytes = [System.IO.File]::ReadAllBytes($file2)
& $addString "--$boundary$LF"
& $addString "Content-Disposition: form-data; name=`"files`"; filename=`"test2.md`"$LF"
& $addString "Content-Type: text/markdown$LF$LF"
$bodyBytes.AddRange($file2Bytes)
Write-Host "  Added $($file2Bytes.Length) bytes of file content" -ForegroundColor DarkGray
& $addString $LF

# Close boundary
& $addString "--$boundary--$LF"

$body = $bodyBytes.ToArray()

Write-Host ""
Write-Host "Total body size: $($body.Length) bytes" -ForegroundColor Green

# Make request
$url = "$BaseUrl/api/runs/$RunId/files"
$headers = @{
    "Content-Type" = "multipart/form-data; boundary=$boundary"
    "Authorization" = "Bearer $apiKey"
}

Write-Host ""
Write-Host "Sending POST request to: $url" -ForegroundColor Cyan
Write-Host "Headers:" -ForegroundColor Gray
$headers.GetEnumerator() | ForEach-Object { 
    $value = if ($_.Key -eq "Authorization") { $_.Value.Substring(0,25) + "..." } else { $_.Value }
    Write-Host "  $($_.Key): $value" -ForegroundColor DarkGray
}

try {
    $response = Invoke-WebRequest -Method POST -Uri $url -Headers $headers -Body $body -UseBasicParsing
    
    Write-Host ""
    Write-Host "[SUCCESS]" -ForegroundColor Green
    Write-Host "Status: $($response.StatusCode)" -ForegroundColor Green
    Write-Host "Response:" -ForegroundColor Cyan
    $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 5 | Write-Host -ForegroundColor Gray
}
catch {
    Write-Host ""
    Write-Host "[FAILED]" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
        Write-Host "Status Code: $statusCode" -ForegroundColor Red
        
        try {
            $responseStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($responseStream)
            $responseBody = $reader.ReadToEnd()
            $reader.Close()
            
            Write-Host "Response Body:" -ForegroundColor Yellow
            Write-Host $responseBody -ForegroundColor Gray
            
            try {
                $responseBody | ConvertFrom-Json | ConvertTo-Json -Depth 5 | Write-Host -ForegroundColor Gray
            } catch {
                # Not JSON, already displayed raw
            }
        }
        catch {
            Write-Host "Could not read response body" -ForegroundColor Red
        }
    }
    
    if ($_.ErrorDetails) {
        Write-Host "Error Details:" -ForegroundColor Yellow
        Write-Host $_.ErrorDetails.Message -ForegroundColor Gray
    }
}
finally {
    # Cleanup
    Write-Host ""
    Write-Host "Cleaning up test files..." -ForegroundColor Gray
    Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
}
