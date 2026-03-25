
#  spec.ps1 
# Entry point for `felix spec <subcommand>`
# Heavy sub-commands are split into dedicated files:
#   spec-fix.ps1  - Invoke-SpecFix (scan/rebuild requirements.json)
#   spec-pull.ps1 - Invoke-SpecPull (sync specs from server)

. "$PSScriptRoot\spec-fix.ps1"
. "$PSScriptRoot\spec-pull.ps1"
. "$PSScriptRoot\spec-push.ps1"

#  Dispatcher 

function Invoke-SpecCreate {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    if ($Args.Count -eq 0) {
        Write-Host ""
        Write-Host "Available subcommands:"
        Write-Host "  list                               List requirements and specs"
        Write-Host "  create [--quick] <description>   Create a new specification with auto-generated ID"
        Write-Host "  fix [--fix-duplicates]            Scan specs folder and fix requirements.json alignment"
        Write-Host "  delete <requirement-id>           Delete a specification and remove from requirements.json"
        Write-Host "  status <requirement-id> <status>  Update a requirement status in requirements.json"
        Write-Host "  pull [--dry-run] [--delete]       Download changed specs from server"
        Write-Host "  push [--dry-run] [--force]         Upload local spec files to server DB"
        Write-Host ""
        Write-Host "Flags:"
        Write-Host "  --quick, -q           Quick mode: minimal questions, makes reasonable assumptions"
        Write-Host "  --fix-duplicates, -f  Automatically rename duplicate spec files to next available ID"
        Write-Host "  --dry-run             Show what would change without writing files"
        Write-Host "  --delete              Also delete local specs that no longer exist on server"
        Write-Host "  --force               Pull: overwrite local files; Push: request create-if-missing + re-upload"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  felix spec list"
        Write-Host "  felix spec create `"Add user authentication`""
        Write-Host "  felix spec fix"
        Write-Host "  felix spec fix --fix-duplicates"
        Write-Host "  felix spec delete S-0042"
        Write-Host "  felix spec status S-0042 planned"
        Write-Host "  felix spec pull"
        Write-Host "  felix spec pull --dry-run"
        Write-Host "  felix spec push"
        Write-Host "  felix spec push --dry-run"
        exit 0
    }

    $subcommand = $Args[0]

    switch ($subcommand) {
        "list" {
            . "$PSScriptRoot\list.ps1"
            Invoke-List -Args $Args[1..($Args.Count - 1)]
            exit $LASTEXITCODE
        }

        "create" {
            $quickMode = $false
            $argsWithoutFlags = @()
            for ($i = 1; $i -lt $Args.Count; $i++) {
                if ($Args[$i] -eq "--quick" -or $Args[$i] -eq "-q") {
                    $quickMode = $true
                }
                else {
                    $argsWithoutFlags += $Args[$i]
                }
            }

            $description = if ($argsWithoutFlags.Count -gt 0) {
                $argsWithoutFlags -join " "
            }
            else {
                Read-Host "What feature do you want to build?"
            }

            if (-not $description -or $description.Trim() -eq "") {
                Write-Error "Description cannot be empty"
                exit 1
            }

            $description = $description.Trim()

            if ($Format -eq "json") {
                Write-Host "Warning: --format json is not supported for 'spec create'" -ForegroundColor Yellow
                Write-Host "   Spec builder requires interactive input (questions/answers)" -ForegroundColor Gray
                Write-Host "   Continuing with standard interactive mode..." -ForegroundColor Gray
                Write-Host ""
            }

            $requirementsFile = Join-Path $RepoRoot ".felix\requirements.json"
            $nextId = "S-0001"

            if (Test-Path $requirementsFile) {
                try {
                    $reqData = Get-Content $requirementsFile -Raw | ConvertFrom-Json
                    # Support both { requirements: [...] } and bare [...] formats
                    if ($reqData -is [array]) {
                        $existingIds = $reqData | ForEach-Object { $_.id }
                    }
                    else {
                        $existingIds = $reqData.requirements | ForEach-Object { $_.id }
                    }
                    $maxNum = 0
                    foreach ($id in $existingIds) {
                        if ($id -match '^S-(\d{4})$') {
                            $num = [int]$matches[1]
                            if ($num -gt $maxNum) { $maxNum = $num }
                        }
                    }
                    $nextId = "S-{0:D4}" -f ($maxNum + 1)
                }
                catch {
                    Write-Warning "Could not read requirements.json, using S-0001"
                }
            }

            if ($quickMode) {
                & "$PSScriptRoot\..\felix-agent.ps1" `
                    -ProjectPath $RepoRoot `
                    -SpecBuildMode:$true `
                    -QuickMode:$true `
                    -RequirementId $nextId `
                    -InitialPrompt $description `
                    -VerboseMode:$VerboseMode
            }
            else {
                & "$PSScriptRoot\..\felix-agent.ps1" `
                    -ProjectPath $RepoRoot `
                    -SpecBuildMode:$true `
                    -RequirementId $nextId `
                    -InitialPrompt $description `
                    -VerboseMode:$VerboseMode
            }

            exit $LASTEXITCODE
        }

        "fix" {
            $fixDuplicates = $false
            for ($i = 1; $i -lt $Args.Count; $i++) {
                if ($Args[$i] -eq "--fix-duplicates" -or $Args[$i] -eq "-f") {
                    $fixDuplicates = $true
                }
            }
            Invoke-SpecFix -FixDuplicates:$fixDuplicates
            exit $LASTEXITCODE
        }

        "delete" {
            if ($Args.Count -lt 2) {
                Write-Error "Usage: felix spec delete <requirement-id>"
                Write-Host "Example: felix spec delete S-0042"
                exit 1
            }
            Invoke-SpecDelete -RequirementId $Args[1]
            exit $LASTEXITCODE
        }

        "status" {
            if ($Args.Count -lt 3) {
                Write-Error "Usage: felix spec status <requirement-id> <status>"
                Write-Host "Example: felix spec status S-0042 planned"
                exit 1
            }
            Invoke-SpecStatus -RequirementId $Args[1] -Status $Args[2]
            exit $LASTEXITCODE
        }

        "pull" {
            $dryRun = $Args -contains "--dry-run"
            $deleteOrphans = $Args -contains "--delete"
            $force = $Args -contains "--force"
            Invoke-SpecPull -DryRun:$dryRun -Delete:$deleteOrphans -Force:$force
        }

        "push" {
            $dryRun = $Args -contains "--dry-run"
            $force = $Args -contains "--force"
            Invoke-SpecPush -DryRun:$dryRun -Force:$force
        }

        default {
            Write-Error "Unknown spec subcommand: $subcommand"
            Write-Host ""
            Write-Host "Available subcommands:"
            Write-Host "  list                               List requirements and specs"
            Write-Host "  create [--quick] <description>   Create a new specification with auto-generated ID"
            Write-Host "  fix [--fix-duplicates]            Scan specs folder and fix requirements.json alignment"
            Write-Host "  delete <requirement-id>           Delete a specification and remove from requirements.json"
            Write-Host "  status <requirement-id> <status>  Update a requirement status in requirements.json"
            Write-Host "  pull [--dry-run] [--delete]       Download changed specs from server"
            Write-Host "  push [--dry-run] [--force]         Upload local spec files to server DB"
            Write-Host ""
            exit 1
        }
    }
}

#  Invoke-SpecStatus 

function Invoke-SpecStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementId,

        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    if ($RequirementId -notmatch '^S-\d{4}$') {
        Write-Error 'Invalid requirement ID format. Expected S-NNNN (e.g., S-0001)'
        exit 1
    }

    $normalizedStatus = $Status.ToLower()
    if ($normalizedStatus -eq "in-progress") {
        $normalizedStatus = "in_progress"
    }

    $allowedStatuses = @("draft", "planned", "in_progress", "blocked", "complete", "done")
    if ($allowedStatuses -notcontains $normalizedStatus) {
        Write-Error "Invalid status '$Status'. Allowed: $($allowedStatuses -join ', ')"
        exit 1
    }

    . "$PSScriptRoot\..\core\state-manager.ps1"

    $requirementsFile = Join-Path $RepoRoot ".felix\requirements.json"
    if (-not (Test-Path $requirementsFile)) {
        Write-Error "requirements.json not found at $requirementsFile"
        exit 1
    }

    try {
        $state = Get-RequirementsState -RequirementsFile $requirementsFile
        $requirement = $state.requirements | Where-Object { $_.id -eq $RequirementId }
        if (-not $requirement) {
            Write-Error "Requirement $RequirementId not found in requirements.json"
            exit 1
        }

        $requirement.status = $normalizedStatus
        Save-RequirementsState -RequirementsFile $requirementsFile -State $state

        Write-Host ""
        Write-Host "[OK] Updated $RequirementId status to '$normalizedStatus'" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Error "Failed to update requirement status: $_"
        exit 1
    }
}

#  Invoke-SpecDelete 

function Invoke-SpecDelete {
    param([string]$RequirementId)

    if ($RequirementId -notmatch '^S-\d{4}$') {
        Write-Error 'Invalid requirement ID format. Expected S-NNNN (e.g., S-0001)'
        exit 1
    }

    $requirementsFile = Join-Path $RepoRoot ".felix\requirements.json"
    $specsDir = Join-Path $RepoRoot "specs"

    if (-not (Test-Path $requirementsFile)) {
        Write-Error "requirements.json not found at $requirementsFile"
        exit 1
    }

    try {
        $parsed = Get-Content $requirementsFile -Raw | ConvertFrom-Json
        # Normalize bare array format (legacy) to { requirements: [] } object
        if ($parsed -is [array]) {
            $requirementsData = [PSCustomObject]@{ requirements = $parsed }
        }
        else {
            $requirementsData = $parsed
        }
    }
    catch {
        Write-Error "Failed to parse requirements.json: $_"
        exit 1
    }

    $requirement = $requirementsData.requirements | Where-Object { $_.id -eq $RequirementId }
    if (-not $requirement) {
        Write-Error "Requirement $RequirementId not found in requirements.json"
        exit 1
    }

    $specFile = Get-ChildItem -Path $specsDir -Filter "$RequirementId*.md" -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "=== Delete Specification ===" -ForegroundColor Yellow
    Write-Host "ID:   $RequirementId" -ForegroundColor Cyan
    Write-Host "Path: $($requirement.spec_path)" -ForegroundColor Cyan
    if ($specFile) {
        Write-Host "File: $($specFile.Name)" -ForegroundColor Cyan
    }
    else {
        Write-Host "File: (not found)" -ForegroundColor Gray
    }
    Write-Host ""

    $confirmation = Read-Host "Are you sure you want to delete this spec? (yes/no)"
    if ($confirmation -ne "yes") {
        Write-Host "Deletion cancelled" -ForegroundColor Gray
        exit 0
    }

    if ($specFile) {
        try {
            Remove-Item $specFile.FullName -Force
            Write-Host "[OK] Deleted file: $($specFile.Name)" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to delete file: $_"
            exit 1
        }
    }

    $requirementsData.requirements = $requirementsData.requirements | Where-Object { $_.id -ne $RequirementId }

    try {
        $json = $requirementsData | ConvertTo-Json -Depth 10
        Set-Content -Path $requirementsFile -Value $json -Encoding UTF8
        Write-Host "[OK] Removed from requirements.json" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to update requirements.json: $_"
        exit 1
    }

    Write-Host ""
    Write-Host "[OK] Specification $RequirementId deleted successfully" -ForegroundColor Green
    Write-Host ""
}
