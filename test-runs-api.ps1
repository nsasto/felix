$reqId = "ec11315f-db18-4ac9-8e6d-e4e71ac13318"
$url = "http://localhost:8080/api/agents/runs?requirement_id=$reqId&limit=5"

Write-Host "Testing URL: $url" -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
    Write-Host "SUCCESS!" -ForegroundColor Green
    Write-Host "Runs returned: $($response.runs.Count)" -ForegroundColor Yellow
    $response | ConvertTo-Json -Depth 3
} catch {
    Write-Host "ERROR!" -ForegroundColor Red
    Write-Host "Status: $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Red
    Write-Host "Message: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) {
        Write-Host "Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}
