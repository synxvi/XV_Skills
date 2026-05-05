# CC-Switch Skills Manager - Migrate Agent-Native Skill to cc-switch
# Moves an agent-native skill into cc-switch storage and registers in DB.
# Does NOT touch the agent dir -- use sync-links.ps1 after to replace with junction.

param(
    [Parameter(Mandatory=$true)]
    [string]$Directory,
    [Parameter(Mandatory=$true)]
    [ValidateSet('claude','codex','agents')]
    [string]$Source,
    [string]$CcSwitchDir = "$env:USERPROFILE\.cc-switch",
    [string]$ClaudeDir   = "$env:USERPROFILE\.claude\skills",
    [string]$CodexDir    = "$env:USERPROFILE\.codex\skills",
    [string]$AgentsDir   = "$env:USERPROFILE\.agents\skills",
    [string]$Name,
    [string]$Description = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillsDir = Join-Path $CcSwitchDir 'skills'
$dbPath    = Join-Path $CcSwitchDir 'cc-switch.db'

# CRITICAL #3: 路径注入防护 — 禁止路径遍历和特殊字符
# 允许: 字母、数字、连字符(-)、下划线(_)、点(.)
# 禁止: 路径分隔符和文件系统特殊字符
if ($Directory -match '[\\/:*?<>|]') {
    Write-Error "Invalid directory name (contains disallowed chars): $Directory"; exit 1
}
if ($Directory -match '\.\.' -or $Directory -match '^[\\/]') {
    Write-Error "Invalid directory name (path traversal detected): $Directory"; exit 1
}

if ($Source -eq 'claude')      { $srcDir = Join-Path $ClaudeDir $Directory }
elseif ($Source -eq 'codex')   { $srcDir = Join-Path $CodexDir $Directory }
else                           { $srcDir = Join-Path $AgentsDir $Directory }

if (-not (Test-Path $srcDir)) {
    Write-Error "Source not found: $srcDir"; exit 1
}

# MEDIUM #9: 检查目标是否已存在（包括 junction link）
$dstDir = Join-Path $skillsDir $Directory
if (Test-Path $dstDir) {
    $existingItem = Get-Item -LiteralPath $dstDir -Force -EA SilentlyContinue
    if ($existingItem.LinkType) {
        Write-Error "Destination already exists as a link: $dstDir -> $($existingItem.Target)"
    } else {
        Write-Error "Destination already exists in cc-switch: $dstDir"
    }
    Write-Output "  Remove it manually and retry if intended."
    exit 1
}

# HIGH #5: 更健壮的 SKILL.md frontmatter 解析
$skillMd = Join-Path $srcDir 'SKILL.md'
if ((Test-Path $skillMd) -and (-not $Name -or -not $Description)) {
    try {
        $lines = Get-Content $skillMd -TotalCount 30 -Encoding UTF8 -ErrorAction Stop
        $inFront = $false; $front = ''
        $prevKey = ''
        foreach ($l in $lines) {
            if ($l -eq '---') { if ($inFront) { break } else { $inFront = $true; continue } }
            if ($inFront) {
                if ($l -match '^[a-zA-Z_]+:') {
                    $front += $l + "`n"
                    $prevKey = ($l -split ':', 2)[0].Trim()
                } elseif ($l -match '^\s+' -and $prevKey) {
                    $trimmed = $l.TrimStart()
                    if ($trimmed -and $trimmed -ne '>' -and $trimmed -ne '|') {
                        $front += "  $trimmed`n"
                    }
                }
            }
        }
        if ($front -and -not $Name -and ($front -match 'name:\s*(.+)')) {
            $Name = $matches[1].Trim().Trim('"').Trim("'")
        }
        if ($front -and -not $Description -and ($front -match 'description:\s*(.+)')) {
            $Description = $matches[1].Trim().Trim('"').Trim("'")
        }
    } catch {
        Write-Warning "Failed to parse SKILL.md frontmatter: $($_.Exception.Message)"
    }
}
if (-not $Name) { $Name = $Directory }

Write-Output "Migrating: $Directory"
Write-Output "  Source:      $srcDir"
Write-Output "  Destination: $dstDir"
Write-Output "  Name:        $Name"
$descPreview = if ($Description.Length -gt 80) { $Description.Substring(0, 80) + '...' } else { $Description }
Write-Output "  Description: $descPreview"

if ($DryRun) {
    Write-Output "[DRY RUN] Would copy and register."
    exit 0
}

# Step 1: Copy to cc-switch storage
Copy-Item -LiteralPath $srcDir -Destination $dstDir -Recurse -Force
Write-Output "  Copied to cc-switch storage."

# Step 2: Register in DB
$enCla   = if ($Source -eq 'claude') { 1 } else { 0 }
$enCodex = if ($Source -in @('codex','agents')) { 1 } else { 0 }

$dbwritePy = Join-Path $scriptDir 'dbwrite.py'
# HIGH #12: try-finally 确保环境变量清理
try {
    $env:CCS_MIGRATE_DESC = $Description
    python $dbwritePy $dbPath $Directory $Name $enCla $enCodex
} finally {
    Remove-Item Env:\CCS_MIGRATE_DESC -ErrorAction SilentlyContinue
}

Write-Output "  Migration complete."
Write-Output "  Next: run sync-links.ps1 to replace copies with junction links."

