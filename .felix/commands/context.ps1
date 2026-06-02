
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
        Write-Host "  build [options]       Analyze project and generate the primary configured context file"
        Write-Host "  show                  Display the primary configured context file"
        Write-Host "  push [options]        Upload README.md and configured context files to server"
        Write-Host "  pull [options]        Download README.md and configured context files from server"
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
            $agentsData = Get-AgentsConfiguration -AgentsJsonFile $agentsFile
            $agentId = if ($config.agent -and $null -ne $config.agent.agent_id -and -not [string]::IsNullOrWhiteSpace([string]$config.agent.agent_id)) {
                [string]$config.agent.agent_id
            }
            else {
                $firstAgent = $agentsData.agents | Select-Object -First 1
                if ($firstAgent.key) { [string]$firstAgent.key } else { [string]$firstAgent.id }
            }
            $agentConfig = Get-AgentConfig -AgentsData $agentsData -AgentId $agentId -ConfigFile $configPath
            $paths = Get-ProjectPaths -ProjectPath $RepoRoot

            if (-not $agentConfig) {
                exit 1
            }
            
            # Execute builder
            $result = Invoke-ContextBuilder `
                -ProjectPath $RepoRoot `
                -IncludeHidden:$includeHidden `
                -Force:$force `
                -VerboseMode:$VerboseMode `
                -Config $config `
                -AgentConfig $agentConfig `
                -Paths $paths
            
            exit $result.ExitCode
        }
        
        "show" {
            $paths = Get-ProjectPaths -ProjectPath $RepoRoot
            $contextPath = $paths.PrimaryContextFile
            if (-not (Test-Path $contextPath)) {
                Write-Host ""
                Write-Host "$($paths.ContextRelativePaths[0]) not found" -ForegroundColor Yellow
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

        "inspect" {
            # A5: context budget inspection report
            . "$PSScriptRoot\..\core\context-budgeter.ps1"
            . "$PSScriptRoot\..\core\agents-loader.ps1"
            . "$PSScriptRoot\..\core\config-loader.ps1"
            $configPath   = Join-Path $RepoRoot ".felix\config.json"
            $cfg          = Get-FelixConfig -ConfigFile $configPath
            $budgetTokens = if ($cfg -and $cfg.context -and $cfg.context.budget_tokens) { [int]$cfg.context.budget_tokens } else { 32000 }

            $felixDir    = Join-Path $RepoRoot ".felix"
            $agentsCtx   = Get-LayeredAgentsContext -StartPath $RepoRoot -RepoRoot $RepoRoot
            $contextFile = if ($cfg -and $cfg.context -and $cfg.context.file) {
                Join-Path $RepoRoot $cfg.context.file
            } else {
                Join-Path $felixDir "CONTEXT.md"
            }

            # Static on-disk sources; runtime sources (spec, plan, skills, memory) require
            # an active run context and will show 0 tokens here.
            $sources = @{
                layered_agents = if ($agentsCtx -and $agentsCtx.Blob) { $agentsCtx.Blob } else { "" }
                repo_map       = ""
                context_map    = (Get-Content $contextFile -Raw -ErrorAction SilentlyContinue) -as [string]
                spec           = ""
                plan           = ""
                skills         = ""
                memory         = ""
                extras         = ""
            }
            $report = Get-ContextInspectReport -Sources $sources -BudgetTokens $budgetTokens
            Write-Host $report
        }

        default {
            Write-Error "Unknown context subcommand: $subCmd"
            Write-Host "Usage: felix context <build|show|push|pull|inspect> [options]"
            Write-Host ""
            Write-Host "Options for 'build':"
            Write-Host "  --include-hidden    Include hidden files/folders in analysis"
            Write-Host "  --force             Skip overwrite confirmation"
            exit 1
        }
    }
}
