<#
.SYNOPSIS
Git operations for Felix agent
#>

function Initialize-FeatureBranch {
    <#
    .SYNOPSIS
    Creates or switches to feature branch for requirement
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequirementId,

        [string]$BaseBranch = "main"
    )

    $branchName = "feature/$RequirementId"

    # Check if branch exists locally
    $existingBranch = git branch --list $branchName 2>&1
    if ($LASTEXITCODE -eq 0 -and $existingBranch) {
        Write-Verbose "Switching to existing branch: $branchName"
        git checkout $branchName 2>&1 | Out-Null
        return $branchName
    }

    # Check if branch exists remotely
    $remoteBranch = git ls-remote --heads origin $branchName 2>&1
    if ($LASTEXITCODE -eq 0 -and $remoteBranch) {
        Write-Verbose "Checking out remote branch: $branchName"
        git fetch origin $branchName 2>&1 | Out-Null
        git checkout -b $branchName "origin/$branchName" 2>&1 | Out-Null
        return $branchName
    }

    # Create new branch from base
    Write-Verbose "Creating new branch: $branchName from $BaseBranch"
    git checkout $BaseBranch 2>&1 | Out-Null
    git pull origin $BaseBranch 2>&1 | Out-Null
    git checkout -b $branchName 2>&1 | Out-Null

    return $branchName
}

function Get-GitState {
    <#
    .SYNOPSIS
    Captures current git state for guardrail checking
    #>
    param([string]$WorkingDir)

    if ($WorkingDir) {
        Push-Location $WorkingDir
    }
    
    try {
        return @{
            commitHash     = git rev-parse HEAD 2>&1
            branch         = git rev-parse --abbrev-ref HEAD 2>&1
            modifiedFiles  = @(git diff --name-only HEAD 2>&1)
            untrackedFiles = @(git ls-files --others --exclude-standard 2>&1)
            stagedFiles    = @(git diff --cached --name-only 2>&1)
        }
    }
    finally {
        if ($WorkingDir) {
            Pop-Location
        }
    }
}

function Test-GitChanges {
    <#
    .SYNOPSIS
    Checks if there are uncommitted changes
    #>
    param()

    $status = git status --porcelain 2>&1
    return ($null -ne $status -and $status.Length -gt 0)
}

function Get-CommitRulesConfig {
    <#
    .SYNOPSIS
    Reads and parses .git-commit-rules.json configuration
    #>
    param([string]$Path = ".git-commit-rules.json")

    if (-not (Test-Path $Path)) { return $null }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        return ($raw | ConvertFrom-Json)
    }
    catch {
        throw "Failed to read/parse $Path. Ensure it is valid JSON. $($_.Exception.Message)"
    }
}

function Normalize-CommitMessage {
    <#
    .SYNOPSIS
    Normalizes commit message whitespace and blank lines
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [psobject]$NormalizeOptions
    )

    if (-not $NormalizeOptions) { return $Message }

    $m = $Message

    if ($NormalizeOptions.trimTrailingWhitespace -eq $true) {
        $m = [regex]::Replace($m, "(?m)[ `t]+$", "")
    }

    if ($NormalizeOptions.trimLeadingBlankLines -eq $true) {
        $m = [regex]::Replace($m, "^(?:\r?\n)+", "")
    }

    if ($NormalizeOptions.trimTrailingBlankLines -eq $true) {
        $m = [regex]::Replace($m, "(?:\r?\n)+\z", "")
    }

    $maxBlanks = $NormalizeOptions.collapseBlankLinesMax
    if ($null -ne $maxBlanks -and $maxBlanks -is [int] -and $maxBlanks -ge 1) {
        $keep = "`r?`n"
        $rep = ""
        for ($i = 0; $i -lt $maxBlanks; $i++) { $rep += "`r`n" }
        # convert to pattern that means:  (newline) repeated (max+1) or more -> replace with max newlines
        $pattern = "(\r?\n){" + ($maxBlanks + 1) + ",}"
        $m = [regex]::Replace($m, $pattern, $rep)
    }

    if ($NormalizeOptions.ensureFinalNewline -eq $true) {
        if (-not $m.EndsWith("`n")) { $m += "`r`n" }
    }

    return $m
}

function Apply-CommitRules {
    <#
    .SYNOPSIS
    Applies commit message rules (rewrite + validate)
    
    .DESCRIPTION
    Processes commit message through configured rules:
    - regex-replace: rewrite or strip patterns
    - prepend/append: add text blocks
    - require: validation - message must match
    - denylist: validation - message must not match
    
    .OUTPUTS
    Hashtable with Message (string) and Errors (array)
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [psobject]$Config
    )

    if (-not $Config) { return @{ Message = $Message; Errors = @() } }

    $rules = $Config.rules
    if (-not $rules) { return @{ Message = $Message; Errors = @() } }

    $m = $Message
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($rule in $rules) {
        if ($null -ne $rule.enabled -and -not $rule.enabled) { continue }

        $type = [string]$rule.type
        $name = if ($rule.name) { [string]$rule.name } else { $type }

        switch ($type) {
            "regex-replace" {
                $pattern = [string]$rule.pattern
                $replacement = [string]$rule.replacement
                try {
                    $m = [regex]::Replace($m, $pattern, $replacement)
                }
                catch {
                    $errors.Add("Rule '$name' failed (invalid regex): $($_.Exception.Message)")
                }
            }

            "prepend" {
                $text = [string]$rule.text
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $textBlock = $text.TrimEnd()
                    if ([string]::IsNullOrWhiteSpace($m)) {
                        $m = $textBlock
                    }
                    else {
                        $m = $textBlock + "`r`n`r`n" + $m.TrimStart()
                    }
                }
            }

            "append" {
                $text = [string]$rule.text
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $textBlock = $text.TrimEnd()
                    if ([string]::IsNullOrWhiteSpace($m)) {
                        $m = $textBlock
                    }
                    else {
                        $m = $m.TrimEnd() + "`r`n`r`n" + $textBlock
                    }
                }
            }

            "require" {
                $pattern = [string]$rule.pattern
                try {
                    if (-not [regex]::IsMatch($m, $pattern)) {
                        $errors.Add("Rule '$name' failed: commit message must match pattern: $pattern")
                    }
                }
                catch {
                    $errors.Add("Rule '$name' failed (invalid regex): $($_.Exception.Message)")
                }
            }

            "denylist" {
                $pattern = [string]$rule.pattern
                try {
                    if ([regex]::IsMatch($m, $pattern)) {
                        $errors.Add("Rule '$name' failed: commit message matched denylist pattern: $pattern")
                    }
                }
                catch {
                    $errors.Add("Rule '$name' failed (invalid regex): $($_.Exception.Message)")
                }
            }

            default {
                $errors.Add("Unknown rule type '$type' in '$name'")
            }
        }
    }

    # optional normalize
    if ($Config.options -and $Config.options.normalize) {
        $m = Normalize-CommitMessage -Message $m -NormalizeOptions $Config.options.normalize
    }

    return @{ Message = $m; Errors = $errors.ToArray() }
}

function Invoke-GitCommit {
    <#
    .SYNOPSIS
    Commits changes with proper error handling and commit message rule enforcement
    
    .DESCRIPTION
    Applies rules from .git-commit-rules.json (if present) to rewrite/validate
    commit messages before committing. Strips unwanted content like Droid co-author
    lines and enforces message standards.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [switch]$Push
    )

    if (-not (Test-GitChanges)) {
        Write-Warning "No changes to commit"
        return $false
    }

    $cfg = Get-CommitRulesConfig -Path ".git-commit-rules.json"
    $result = Apply-CommitRules -Message $Message -Config $cfg

    if ($result.Errors.Count -gt 0) {
        $msg = "Commit message rejected by git-commit-rules:`n- " + ($result.Errors -join "`n- ")
        throw $msg
    }

    $finalMessage = $result.Message
    if ([string]::IsNullOrWhiteSpace($finalMessage)) {
        throw "Commit message became empty after applying git-commit-rules."
    }

    $tempMsg = Join-Path $env:TEMP ("gitmsg_" + [guid]::NewGuid().ToString("N") + ".txt")

    try {
        Set-Content -LiteralPath $tempMsg -Value $finalMessage -Encoding UTF8

        git add . 2>&1 | Out-Null
        git commit -F $tempMsg 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Git commit failed"
        }
    }
    finally {
        if (Test-Path $tempMsg) { Remove-Item -LiteralPath $tempMsg -Force | Out-Null }
    }

    if ($Push) {
        $branch = git rev-parse --abbrev-ref HEAD 2>&1
        git push origin $branch 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "Git push failed"
        }
    }

    return $true
}

function Invoke-GitRevert {
    <#
    .SYNOPSIS
    Reverts unauthorized changes (for planning mode guardrails)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$BeforeState,

        [string[]]$AllowedPatterns = @('runs/*', '.felix/state.json', '.felix/requirements.json')
    )

    $afterState = Get-GitState

    # Check for new commits
    if ($afterState.commitHash -ne $BeforeState.commitHash) {
        Write-Warning "Unauthorized commit detected - reverting"
        git reset --soft "$($BeforeState.commitHash)" 2>&1 | Out-Null
    }

    # Check for unauthorized file changes
    $allChanges = $afterState.modifiedFiles + $afterState.untrackedFiles
    foreach ($file in $allChanges) {
        $allowed = $false
        foreach ($pattern in $AllowedPatterns) {
            if ($file -like $pattern) {
                $allowed = $true
                break
            }
        }

        if (-not $allowed) {
            Write-Warning "Unauthorized change detected: $file - reverting"
            if (Test-Path $file) {
                # For tracked files, restore from HEAD
                if ($file -in $afterState.modifiedFiles) {
                    git checkout HEAD -- $file 2>&1 | Out-Null
                }
                # For untracked files, delete them
                else {
                    Remove-Item $file -Force 2>&1 | Out-Null
                }
            }
        }
    }
}

