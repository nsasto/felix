Set-StrictMode -Version Latest

function Sync-Felix3WorktreeHarnessFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$WorktreeProjectPath,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )
    foreach ($relativeDirectory in @('.opencode/agents', '.opencode/skills')) {
        $sourceDirectory = Join-Path $ProjectPath $relativeDirectory
        if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) { continue }
        foreach ($sourceFile in Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse -Force) {
            if (($sourceFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $relativeToRepository = [IO.Path]::GetRelativePath($RepositoryRoot, $sourceFile.FullName)
            if ($relativeToRepository -eq '..' -or $relativeToRepository.StartsWith('..' + [IO.Path]::DirectorySeparatorChar, [StringComparison]::Ordinal)) { continue }
            $repositoryPath = $relativeToRepository.Replace('\', '/')
            $null = & git -C $RepositoryRoot ls-files --error-unmatch -- $repositoryPath 2>$null
            $isTracked = $LASTEXITCODE -eq 0
            if ($isTracked) { continue }

            $relativeToProject = [IO.Path]::GetRelativePath($ProjectPath, $sourceFile.FullName)
            $destination = Join-Path $WorktreeProjectPath $relativeToProject
            $destinationDirectory = Split-Path -Parent $destination
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $destination -Force
        }
    }
}

function New-Felix3Worktree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$RunId,
        [string]$ExistingPath
    )
    if ($ExistingPath) {
        if (-not (Test-Path -LiteralPath $ExistingPath -PathType Container)) { throw "Felix 3 run worktree is missing: $ExistingPath" }
        $worktreePath = (Resolve-Path -LiteralPath $ExistingPath).Path
        $repoRootResult = & git -C $ProjectPath rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $repoRootResult) {
            $repoRoot = [IO.Path]::GetFullPath([string]$repoRootResult)
            Sync-Felix3WorktreeHarnessFiles -ProjectPath $ProjectPath -WorktreeProjectPath $worktreePath -RepositoryRoot $repoRoot
        }
        return $worktreePath
    }
    $repoRootResult = & git -C $ProjectPath rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $repoRootResult) { throw 'Felix 3 worktree execution requires ProjectPath to be inside a Git repository. Set execution.worktree.enabled to false to use the current checkout.' }
    $repoRoot = [IO.Path]::GetFullPath([string]$repoRootResult)
    $projectFullPath = [IO.Path]::GetFullPath($ProjectPath)
    $projectRelativePath = [IO.Path]::GetRelativePath($repoRoot, $projectFullPath)
    if ($projectRelativePath -eq '..' -or $projectRelativePath.StartsWith('..' + [IO.Path]::DirectorySeparatorChar, [StringComparison]::Ordinal)) { throw 'ProjectPath must be inside the Git repository root.' }
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try { $pathHash = ([BitConverter]::ToString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($repoRoot))) -replace '-', '').Substring(0, 10).ToLowerInvariant() }
    finally { $sha256.Dispose() }
    $repoName = [IO.Path]::GetFileName($repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    $worktreeRoot = Join-Path (Split-Path -Parent $repoRoot) ('.{0}-felix3-worktrees-{1}' -f $repoName, $pathHash)
    New-Item -ItemType Directory -Path $worktreeRoot -Force | Out-Null
    $worktreePath = [IO.Path]::GetFullPath((Join-Path $worktreeRoot $RunId))
    if (Test-Path -LiteralPath $worktreePath) { throw "Felix 3 worktree destination already exists: $worktreePath" }
    $branch = 'felix3/' + ($RunId -replace '[^A-Za-z0-9._/-]', '-')
    $output = & git -C $ProjectPath worktree add -b $branch $worktreePath HEAD 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Could not create Felix 3 worktree: $($output -join ' ')" }
    $worktreeProjectPath = if ($projectRelativePath -eq '.') { $worktreePath } else { Join-Path $worktreePath $projectRelativePath }
    $worktreeProjectPath = [IO.Path]::GetFullPath($worktreeProjectPath)
    Sync-Felix3WorktreeHarnessFiles -ProjectPath $ProjectPath -WorktreeProjectPath $worktreeProjectPath -RepositoryRoot $repoRoot
    return $worktreeProjectPath
}
