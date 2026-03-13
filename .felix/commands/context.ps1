
function Invoke-Context {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    
    # Load context-builder module
    . "$PSScriptRoot\..\core\context-builder.ps1"

    # Load dependencies
    . "$PSScriptRoot\..\core\config-loader.ps1"
    . "$PSScriptRoot\..\core\emit-event.ps1"

    # Load push/pull helpers
    . "$PSScriptRoot\context-push.ps1"
    . "$PSScriptRoot\context-pull.ps1"

    if (-not $Args -or $Args.Count -eq 0) {
        Write-Host ""
        Write-Host "Usage: felix context <build|show|push|pull> [options]" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Subcommands:" -ForegroundColor Yellow
        Write-Host "  build [options]       Analyze project and generate CONTEXT.md"
        Write-Host "  show                  Display current CONTEXT.md content"
        Write-Host "  push [options]        Upload README.md, CONTEXT.md, AGENTS.md to server"
        Write-Host "  pull [options]        Download README.md, CONTEXT.md, AGENTS.md from server"
        Write-Host ""
        Write-Host "Options for 'build':" -ForegroundColor Yellow
        Write-Host "  --include-hidden      Include hidden files/folders in analysis"
        Write-Host "  --force               Skip overwrite confirmation"
        Write-Host ""
        Write-Host "Options for 'push':" -ForegroundColor Yellow
        Write-Host "  --dry-run             Show what would be pushed without uploading"
        Write-Host "  --force               Re-upload even unchanged files"
        Write-Host ""
        Write-Host "Options for 'pull':" -ForegroundColor Yellow
        Write-Host "  --dry-run             Show what would be pulled without writing files"
        Write-Host "  --force               Overwrite local files not in manifest"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  felix context build"
        Write-Host "  felix context build --include-hidden"
        Write-Host "  felix context build --force"
        Write-Host "  felix context show"
        Write-Host "  felix context push"
        Write-Host "  felix context push --dry-run"
        Write-Host "  felix context pull"
        Write-Host "  felix context pull --force"
        Write-Host ""
        exit 0
    }
    
    $subCmd = $Args[0]
    
    switch ($subCmd) {
        "build" {
            # Parse flags
            $includeHidden = $false
            $force = $false
            
            for ($i = 1; $i -lt $Args.Count; $i++) {
                switch ($Args[$i]) {
                    "--include-hidden" { $includeHidden = $true }
                    "--force" { $force = $true }
                }
            }
            
            Write-Host ""
            Write-Host "=== Felix Context Builder ===" -ForegroundColor Cyan
            Write-Host "Project: $RepoRoot" -ForegroundColor Gray
            Write-Host ""
            
            # Load configuration
            $configPath = Join-Path $RepoRoot ".felix\config.json"
            $agentsFile = Join-Path $RepoRoot ".felix\agents.json"
            $config = Get-FelixConfig -ConfigFile $configPath
            $agentConfig = Get-AgentsConfiguration -AgentsJsonFile $agentsFile
            $paths = @{
                ProjectPath = $RepoRoot
                FelixDir    = Join-Path $RepoRoot ".felix"
                SpecsDir    = Join-Path $RepoRoot "specs"
                PromptsDir  = Join-Path $PSScriptRoot "..\prompts"
                AgentsFile  = Join-Path $RepoRoot "AGENTS.md"
            }
            
            # Execute builder
            $result = Invoke-ContextBuilder `
                -ProjectPath $RepoRoot `
                -IncludeHidden:$includeHidden `
                -Force:$force `
                -Config $config `
                -AgentConfig $agentConfig `
                -Paths $paths
            
            exit $result.ExitCode
        }
        
        "show" {
            $contextPath = Join-Path $RepoRoot "CONTEXT.md"
            if (-not (Test-Path $contextPath)) {
                Write-Host ""
                Write-Host "CONTEXT.md not found" -ForegroundColor Yellow
                Write-Host "Run 'felix context build' to generate it" -ForegroundColor Gray
                Write-Host ""
                exit 1
            }
            
            $content = Get-Content $contextPath -Raw
            Write-Host $content
        }
        
        "push" {
            $dryRun = $Args -contains "--dry-run"
            $force = $Args -contains "--force"
            Invoke-ContextPush -DryRun:$dryRun -Force:$force
        }

        "pull" {
            $dryRun = $Args -contains "--dry-run"
            $force = $Args -contains "--force"
            Invoke-ContextPull -DryRun:$dryRun -Force:$force
        }

        default {
            Write-Error "Unknown context subcommand: $subCmd"
            Write-Host "Usage: felix context <build|show|push|pull> [options]"
            Write-Host ""
            Write-Host "Options for 'build':"
            Write-Host "  --include-hidden    Include hidden files/folders in analysis"
            Write-Host "  --force             Skip overwrite confirmation"
            exit 1
        }
    }
}
