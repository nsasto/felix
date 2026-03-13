
function Invoke-Tui {
    # Launch interactive Terminal UI dashboard
    $felixCliPath = Join-Path $RepoRoot "src\Felix.Cli"
    
    # Check if dotnet is available
    $dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $dotnetCmd) {
        Write-Host "[ERROR] dotnet CLI not found" -ForegroundColor Red
        Write-Host "" 
        Write-Host "The TUI requires .NET SDK to be installed." -ForegroundColor Yellow
        Write-Host "Download from: https://dotnet.microsoft.com/download" -ForegroundColor Cyan
        exit 1
    }
    
    # Check if Felix.Cli project exists
    if (-not (Test-Path $felixCliPath)) {
        Write-Host "[ERROR] Felix.Cli project not found at: $felixCliPath" -ForegroundColor Red
        exit 1
    }
    
    # Launch TUI dashboard
    & dotnet run --project $felixCliPath -- dashboard
    exit $LASTEXITCODE
}
