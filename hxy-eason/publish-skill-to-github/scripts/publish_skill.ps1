param(
  [Parameter(Mandatory = $true)]
  [string]$SkillPath,

  [string]$RepoPath = "D:\skills\skills-repo",

  [string]$RemoteUrl = "https://github.com/Hxy-Eason/skills.git",

  [string]$Namespace = "hxy-eason",

  [ValidateSet("auto", "add", "update")]
  [string]$Mode = "auto",

  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Fail {
  param([string]$Message)
  Write-Host "Publish stopped: $Message" -ForegroundColor Red
  exit 1
}

function Run-Git {
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
  )

  & git -C $RepoPath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "git $($Arguments -join ' ') failed"
  }
}

function Get-CommandOrFail {
  param([string]$Name)

  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $command) {
    Fail "Command '$Name' was not found. Install it and add it to PATH."
  }
  return $command
}

function Convert-ToGitPath {
  param([string]$Path)
  return ($Path -replace "\\", "/")
}

function Get-RelativePathCompat {
  param(
    [string]$BasePath,
    [string]$Path
  )

  $baseFullPath = [System.IO.Path]::GetFullPath($BasePath)
  $targetFullPath = [System.IO.Path]::GetFullPath($Path)
  if (-not $baseFullPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
    $baseFullPath += [System.IO.Path]::DirectorySeparatorChar
  }

  $baseUri = [System.Uri]::new($baseFullPath)
  $targetUri = [System.Uri]::new($targetFullPath)
  $relativeUri = $baseUri.MakeRelativeUri($targetUri)
  $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString())
  return ($relativePath -replace "/", [System.IO.Path]::DirectorySeparatorChar)
}

function Copy-SkillForPublish {
  param(
    [string]$SourcePath,
    [string]$DestinationPath
  )

  $skipDirectoryNames = @(".git", "node_modules", ".next", "dist", "build", "coverage", ".cache", "__pycache__", ".pytest_cache", ".turbo", ".vercel")
  $skipFileNames = @(".env", ".env.local", ".env.development", ".env.production", ".npmrc", ".pypirc")
  $skipExtensions = @(".pem", ".key", ".p12", ".pfx", ".crt", ".cer", ".der", ".sqlite", ".db")

  if (Test-Path -LiteralPath $DestinationPath) {
    Remove-Item -LiteralPath $DestinationPath -Recurse -Force
  }
  New-Item -ItemType Directory -Path $DestinationPath | Out-Null

  $sourceRoot = (Get-Item -LiteralPath $SourcePath).FullName
  $items = Get-ChildItem -LiteralPath $sourceRoot -Force -Recurse
  foreach ($item in $items) {
    $relativePath = Get-RelativePathCompat -BasePath $sourceRoot -Path $item.FullName
    $pathParts = $relativePath -split '[\\/]+'
    $skip = $false

    foreach ($part in $pathParts) {
      if ($skipDirectoryNames -contains $part) {
        $skip = $true
        break
      }
    }
    if ($skip) { continue }

    $destinationItem = Join-Path $DestinationPath $relativePath
    if ($item.PSIsContainer) {
      if (-not (Test-Path -LiteralPath $destinationItem)) {
        New-Item -ItemType Directory -Path $destinationItem | Out-Null
      }
      continue
    }

    if ($skipFileNames -contains $item.Name.ToLowerInvariant()) { continue }
    if ($skipExtensions -contains ([System.IO.Path]::GetExtension($item.FullName).ToLowerInvariant())) { continue }

    $destinationParent = Split-Path -Parent $destinationItem
    if (-not (Test-Path -LiteralPath $destinationParent)) {
      New-Item -ItemType Directory -Path $destinationParent | Out-Null
    }
    Copy-Item -LiteralPath $item.FullName -Destination $destinationItem
  }
}

function Write-RecoveryHint {
  param(
    [string]$BranchName,
    [string]$PrUrl,
    [string]$TargetRelativePath
  )

  Write-Host ""
  Write-Host "Recovery hints:" -ForegroundColor Yellow
  Write-Host "- Repository: $RepoPath"
  Write-Host "- Temporary branch: $BranchName"
  Write-Host "- Target path: $TargetRelativePath"
  if ($PrUrl) {
    Write-Host "- PR: $PrUrl"
  }
  Write-Host "- Inspect status: git -C `"$RepoPath`" status --short --branch"
  Write-Host "- Return to main: git -C `"$RepoPath`" checkout main"
  Write-Host "- Delete local branch: git -C `"$RepoPath`" branch -D $BranchName"
  Write-Host "- Delete remote branch: git -C `"$RepoPath`" push origin --delete $BranchName"
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$validator = Join-Path $scriptRoot "validate_skill.ps1"
if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
  Fail "Validator script was not found: $validator"
}

$validationJson = & $validator -SkillPath $SkillPath -Json
if ($LASTEXITCODE -ne 0) {
  Write-Host $validationJson
  Fail "Source skill validation failed."
}

$validation = $validationJson | ConvertFrom-Json
$resolvedSkillPath = $validation.skillPath
$skillName = $validation.skillName
if (-not $skillName) {
  Fail "Could not read skill name from SKILL.md."
}

if ($Namespace -notmatch '^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$|^[a-z0-9]$') {
  Fail "Namespace must use lowercase letters, digits, and hyphens, max 64 chars."
}

$repoItem = Get-Item -LiteralPath $RepoPath -ErrorAction SilentlyContinue
if (-not $repoItem -or -not $repoItem.PSIsContainer) {
  Fail "Repository directory was not found: $RepoPath"
}

Get-CommandOrFail "git" | Out-Null
$ghCommand = Get-Command "gh" -ErrorAction SilentlyContinue
if (-not $DryRun) {
  if (-not $ghCommand) {
    Fail "Command 'gh' was not found. Install GitHub CLI and add it to PATH."
  }

  & gh auth status *> $null
  if ($LASTEXITCODE -ne 0) {
    Fail "GitHub CLI is not authenticated. Run gh auth login first."
  }
}

$remote = (& git -C $RepoPath remote get-url origin).Trim()
if ($LASTEXITCODE -ne 0) {
  Fail "Repository does not have an origin remote."
}
if ($remote -ne $RemoteUrl) {
  Fail "Origin remote mismatch. Current: '$remote'. Expected: '$RemoteUrl'."
}

$status = & git -C $RepoPath status --porcelain
if ($LASTEXITCODE -ne 0) {
  Fail "Could not read repository status."
}
if ($status) {
  Fail "Target repository has uncommitted changes. Clean it first: $RepoPath"
}

$targetRelativePath = Convert-ToGitPath (Join-Path $Namespace $skillName)
$targetPath = Join-Path $RepoPath (Join-Path $Namespace $skillName)
$trackedTarget = & git -C $RepoPath ls-tree --name-only HEAD -- $targetRelativePath
$existsInRepo = $null -ne $trackedTarget -and $trackedTarget.Trim().Length -gt 0

$effectiveMode = $Mode
if ($Mode -eq "auto") {
  $effectiveMode = if ($existsInRepo) { "update" } else { "add" }
}
if ($Mode -eq "add" -and $existsInRepo) {
  Fail "Target skill already exists; add mode is not allowed: $targetRelativePath"
}
if ($Mode -eq "update" -and -not $existsInRepo) {
  Fail "Target skill does not exist; update mode is not allowed: $targetRelativePath"
}

$branchName = "$effectiveMode-$Namespace-$skillName".ToLowerInvariant()
$commitTitle = if ($effectiveMode -eq "add") { "Add $targetRelativePath" } else { "Update $targetRelativePath" }
$prTitle = $commitTitle
$prBody = @"
Created by publish-skill-to-github.

- namespace: $Namespace
- skill: $skillName
- target: $targetRelativePath
- mode: $effectiveMode
"@

Write-Host "Publish plan:"
Write-Host "- skill: $skillName"
Write-Host "- source: $resolvedSkillPath"
Write-Host "- repo: $RepoPath"
Write-Host "- target: $targetRelativePath"
Write-Host "- branch: $branchName"
Write-Host "- mode: $effectiveMode"

if ($DryRun) {
  if (-not $ghCommand) {
    Write-Host "Dry run note: GitHub CLI was not found. Real publish will require gh auth login."
  }
  Write-Host "Dry run complete: repository and remote were not changed."
  exit 0
}

$prUrl = ""
try {
  $existingBranch = & git -C $RepoPath branch --list $branchName
  if ($existingBranch) {
    Fail "Local temporary branch already exists: $branchName"
  }

  Run-Git checkout main
  Run-Git fetch origin
  Run-Git pull --ff-only origin main

  $remoteBranch = & git -C $RepoPath ls-remote --heads origin $branchName
  if ($remoteBranch) {
    Fail "Remote temporary branch already exists: $branchName"
  }

  Run-Git checkout -b $branchName

  $namespacePath = Join-Path $RepoPath $Namespace
  if (-not (Test-Path -LiteralPath $namespacePath)) {
    New-Item -ItemType Directory -Path $namespacePath | Out-Null
  }

  Copy-SkillForPublish -SourcePath $resolvedSkillPath -DestinationPath $targetPath

  Run-Git add -- $targetRelativePath

  $changes = & git -C $RepoPath status --porcelain -- $targetRelativePath
  if (-not $changes) {
    Fail "Target directory has no changes to publish."
  }

  Run-Git commit -m $commitTitle
  Run-Git push -u origin $branchName

  $prUrl = (& gh pr create --repo "Hxy-Eason/skills" --base main --head $branchName --title $prTitle --body $prBody).Trim()
  if ($LASTEXITCODE -ne 0 -or -not $prUrl) {
    throw "gh pr create failed"
  }
  Write-Host "PR created: $prUrl"

  & gh pr merge $prUrl --merge --delete-branch
  if ($LASTEXITCODE -ne 0) {
    throw "gh pr merge failed"
  }

  Run-Git checkout main
  Run-Git pull --ff-only origin main

  $localBranchAfterMerge = & git -C $RepoPath branch --list $branchName
  if ($localBranchAfterMerge) {
    & git -C $RepoPath branch -D $branchName
    if ($LASTEXITCODE -ne 0) {
      throw "git branch -D $branchName failed"
    }
  }

  $finalStatus = & git -C $RepoPath status --porcelain
  if ($finalStatus) {
    Fail "Repository still has uncommitted changes after publishing."
  }

  Write-Host "Publish complete: $targetRelativePath was merged into main."
} catch {
  Write-Host "Publish failed: $($_.Exception.Message)" -ForegroundColor Red
  Write-RecoveryHint -BranchName $branchName -PrUrl $prUrl -TargetRelativePath $targetRelativePath
  exit 1
}
