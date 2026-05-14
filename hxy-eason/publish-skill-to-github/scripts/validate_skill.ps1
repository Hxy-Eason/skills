param(
  [Parameter(Mandatory = $true)]
  [string]$SkillPath,

  [switch]$Json,

  [int64]$MaxFileBytes = 5242880
)

$ErrorActionPreference = "Stop"

function Add-Finding {
  param(
    [string]$Severity,
    [string]$Code,
    [string]$Message,
    [string]$Path = ""
  )

  $script:Findings += [pscustomobject]@{
    severity = $Severity
    code = $Code
    message = $Message
    path = $Path
  }
}

function Convert-ToRelativePath {
  param([string]$BasePath, [string]$Path)

  try {
    return [System.IO.Path]::GetRelativePath($BasePath, $Path)
  } catch {
    return $Path
  }
}

function Test-TextFile {
  param([string]$Path)

  $textExtensions = @(
    ".md", ".txt", ".json", ".yaml", ".yml", ".ps1", ".psm1", ".js", ".mjs", ".cjs",
    ".ts", ".tsx", ".jsx", ".css", ".scss", ".html", ".xml", ".csv", ".toml", ".ini",
    ".py", ".sh", ".bat", ".cmd"
  )
  return $textExtensions -contains ([System.IO.Path]::GetExtension($Path).ToLowerInvariant())
}

function Read-TextSafely {
  param([string]$Path)

  try {
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
  } catch {
    Add-Finding "high" "invalid-utf8" "Text file is not valid UTF-8." $Path
    return $null
  }
}

$Findings = @()
$resolvedSkillPath = $null

try {
  $resolvedSkillPath = (Resolve-Path -LiteralPath $SkillPath).Path
} catch {
  Add-Finding "high" "missing-skill-path" "Skill directory was not found: $SkillPath"
}

if ($resolvedSkillPath -and -not (Test-Path -LiteralPath $resolvedSkillPath -PathType Container)) {
  Add-Finding "high" "skill-path-not-directory" "SkillPath must be a directory." $resolvedSkillPath
}

$skillName = $null
$description = $null

if ($resolvedSkillPath) {
  $skillMd = Join-Path $resolvedSkillPath "SKILL.md"
  if (-not (Test-Path -LiteralPath $skillMd -PathType Leaf)) {
    Add-Finding "high" "missing-skill-md" "Required file SKILL.md is missing." $skillMd
  } else {
    $content = Read-TextSafely $skillMd
    if ($null -ne $content) {
      if ($content -notmatch '(?s)^---\s*\r?\n(.*?)\r?\n---') {
        Add-Finding "high" "missing-frontmatter" "SKILL.md is missing YAML frontmatter." $skillMd
      } else {
        $frontmatter = $Matches[1]
        $nameMatch = [regex]::Match($frontmatter, '(?m)^name:\s*(.+?)\s*$')
        $descriptionMatch = [regex]::Match($frontmatter, '(?m)^description:\s*(.+?)\s*$')

        if (-not $nameMatch.Success) {
          Add-Finding "high" "missing-name" "Frontmatter is missing the name field." $skillMd
        } else {
          $skillName = $nameMatch.Groups[1].Value.Trim().Trim('"').Trim("'")
          if ($skillName -notmatch '^[a-z0-9][a-z0-9-]{0,62}[a-z0-9]$|^[a-z0-9]$') {
            Add-Finding "high" "invalid-name" "Skill name must use lowercase letters, digits, and hyphens, max 64 chars." $skillMd
          }
        }

        if (-not $descriptionMatch.Success) {
          Add-Finding "high" "missing-description" "Frontmatter is missing the description field." $skillMd
        } else {
          $description = $descriptionMatch.Groups[1].Value.Trim().Trim('"').Trim("'")
          if ($description.Length -lt 20) {
            Add-Finding "medium" "short-description" "Description is short and may not trigger reliably." $skillMd
          }
        }
      }
    }
  }

  if ($skillName) {
    $folderName = Split-Path -Leaf $resolvedSkillPath
    if ($folderName -ne $skillName) {
      Add-Finding "high" "folder-name-mismatch" "Folder name must match frontmatter name. Folder: $folderName; name: $skillName." $resolvedSkillPath
    }
  }

  $ignoredDirectoryNames = @(".git")
  $blockedDirectoryNames = @("node_modules", ".next", "dist", "build", "coverage", ".cache", "__pycache__", ".pytest_cache", ".turbo", ".vercel")
  $blockedFileNames = @(".env", ".env.local", ".env.development", ".env.production", ".npmrc", ".pypirc")
  $blockedExtensions = @(".pem", ".key", ".p12", ".pfx", ".crt", ".cer", ".der", ".sqlite", ".db")
  $secretPatterns = @(
    'ghp_[A-Za-z0-9_]{20,}',
    'github_pat_[A-Za-z0-9_]{20,}',
    'sk-[A-Za-z0-9]{20,}',
    '-----BEGIN (RSA |DSA |EC |OPENSSH |)?PRIVATE KEY-----',
    '(?i)(api[_-]?key|secret|token|password)\s*[:=]\s*\S{8,}'
  )
  $mojibakePatterns = @(
    ([string][char]0xFFFD),
    '\u00C3[\x80-\xBF]',
    '\u00C2[\x80-\xBF]'
  )

  $items = Get-ChildItem -LiteralPath $resolvedSkillPath -Force -Recurse
  foreach ($item in $items) {
    $relativePath = Convert-ToRelativePath -BasePath $resolvedSkillPath -Path $item.FullName
    $pathParts = $relativePath -split '[\\/]+'

    if ($item.PSIsContainer) {
      if ($ignoredDirectoryNames -contains $item.Name) {
        Add-Finding "medium" "ignored-directory" "Directory will be ignored during publish: $relativePath" $item.FullName
      } elseif ($blockedDirectoryNames -contains $item.Name) {
        Add-Finding "high" "blocked-directory" "Blocked cache, build, or repository directory: $relativePath" $item.FullName
      }
      continue
    }

    if ($blockedFileNames -contains $item.Name.ToLowerInvariant()) {
      Add-Finding "high" "blocked-file" "Blocked sensitive config file: $relativePath" $item.FullName
    }

    if ($blockedExtensions -contains ([System.IO.Path]::GetExtension($item.FullName).ToLowerInvariant())) {
      Add-Finding "high" "blocked-extension" "Blocked key, certificate, or database-like file: $relativePath" $item.FullName
    }

    $skipIgnoredFile = $false
    foreach ($part in $pathParts) {
      if ($ignoredDirectoryNames -contains $part) {
        $skipIgnoredFile = $true
        break
      }
      if ($blockedDirectoryNames -contains $part) {
        Add-Finding "high" "blocked-path" "File is inside a blocked directory: $relativePath" $item.FullName
        break
      }
    }
    if ($skipIgnoredFile) { continue }

    if ($item.Length -gt $MaxFileBytes) {
      Add-Finding "high" "large-file" "File exceeds size limit $MaxFileBytes bytes: $relativePath" $item.FullName
    }

    if (Test-TextFile $item.FullName) {
      $text = Read-TextSafely $item.FullName
      if ($null -eq $text) { continue }

      foreach ($pattern in $secretPatterns) {
        if ($text -match $pattern) {
          Add-Finding "high" "secret-like-text" "Possible secret or token was found: $relativePath" $item.FullName
          break
        }
      }

      foreach ($pattern in $mojibakePatterns) {
        if ($text -match $pattern) {
          Add-Finding "high" "mojibake-risk" "Possible mojibake or replacement character was found: $relativePath" $item.FullName
          break
        }
      }
    }
  }
}

$hasHigh = @($Findings | Where-Object { $_.severity -eq "high" }).Count -gt 0
$result = [pscustomobject]@{
  ok = -not $hasHigh
  skillPath = $resolvedSkillPath
  skillName = $skillName
  description = $description
  findings = $Findings
}

if ($Json) {
  $result | ConvertTo-Json -Depth 6
} else {
  if ($result.ok) {
    Write-Host "Validation passed: $($result.skillName)"
  } else {
    Write-Host "Validation failed: blocking findings were found." -ForegroundColor Red
  }

  foreach ($finding in $Findings) {
    $prefix = "[$($finding.severity)] $($finding.code)"
    if ($finding.path) {
      Write-Host "$prefix - $($finding.message) ($($finding.path))"
    } else {
      Write-Host "$prefix - $($finding.message)"
    }
  }
}

if ($hasHigh) {
  exit 1
}

exit 0
