# CC-Switch Skills Manager - Sync Agent Links
# Replaces agent skill copies with junction links pointing to cc-switch storage.
# Only touches directories that exist in cc-switch AND in the agent dir as copies.
# Skips agent-native directories (not in cc-switch DB) -- never deletes those.

param(
    [string]$CcSwitchDir = "$env:USERPROFILE\.cc-switch",
    [string]$ClaudeDir   = "$env:USERPROFILE\.claude\skills",
    [string]$CodexDir    = "$env:USERPROFILE\.codex\skills",
    [string]$AgentsDir   = "$env:USERPROFILE\.agents\skills",
    [ValidateSet('claude','codex','agents','all')]
    [string]$Target = 'all',
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillsDir = Join-Path $CcSwitchDir 'skills'
$dbPath    = Join-Path $CcSwitchDir 'cc-switch.db'
$script:pythonCmd = $null
foreach ($cmd in @('python', 'python3', 'py')) {
    try {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) { $script:pythonCmd = $cmd; break }
    } catch { }
}
if (-not $script:pythonCmd) {
    Write-Error "Python not found in PATH. Install Python 3 or add to PATH."
    exit 1
}


function Get-DbSkillsWithFlags([string]$dbPath, [string]$scriptDir) {
    if (-not (Test-Path $dbPath)) { return @{} }
    $linkReadPy = Join-Path $scriptDir 'link_dbread.py'
    $jsonOut = & $script:pythonCmd $linkReadPy $dbPath 2>$null
    if ($LASTEXITCODE -ne 0) { return @{} }
    try {
        return ($jsonOut | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        Write-Warning "Failed to parse link_dbread.py output: $($_.Exception.Message)"
        return @{}
    }
}

$dbSkills = Get-DbSkillsWithFlags $dbPath $scriptDir

# 确定每个目标目录应包含的技能
function Get-ExpectedSkills([string]$agentType) {
    $expected = @{}
    foreach ($prop in $dbSkills.PSObject.Properties) {
        $name = $prop.Name
        $flags = $prop.Value
        $shouldInclude = $false
        switch ($agentType) {
            'claude' { $shouldInclude = [bool]$flags.claude }
            'codex'  { $shouldInclude = [bool]$flags.codex }
            'agents' { $shouldInclude = ([bool]$flags.claude -and [bool]$flags.codex) }
        }
        if ($shouldInclude) { $expected[$name] = $true }
    }
    return $expected
}

function Sync-AgentLinks([string]$agentDir, [string]$agentName, [hashtable]$expected) {
    if (-not (Test-Path $agentDir)) {
        Write-Output "  [$agentName] Directory not found: $agentDir -- creating"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $agentDir -Force | Out-Null
        }
    }

    $agentDirs = Get-ChildItem -LiteralPath $agentDir -Directory -EA SilentlyContinue |
        Where-Object { $_.Name -ne '.system' -and $_.Name -notmatch '^\.' }

    $converted = 0; $skipped = 0; $kept = 0; $created = 0; $removed = 0

    # Phase 1: 处理目录中已有的技能
    foreach ($d in $agentDirs) {
        $name = $d.Name

        # 检查是否应存在于该目录
        if ($name -notin $expected.Keys) {
            # 不应存在的技能 — 如果是 junction link，移除
            if ($d.LinkType) {
                Write-Output "  [$agentName] REMOVE (not expected): $name"
                if (-not $DryRun) {
                    Remove-Item -LiteralPath $d.FullName -Force -ErrorAction Stop
                    $removed++
                }
            } else {
                Write-Output "  [$agentName] KEEP (native, not expected): $name"
                $kept++
            }
            continue
        }

        # --- SAFETY: skip agent-native (not in cc-switch DB) ---
        if ($name -notin $dbSkills.PSObject.Properties.Name) {
            Write-Output "  [$agentName] KEEP (native):  $name"
            $kept++
            continue
        }

        # --- Already a link? ---
        if ($d.LinkType) {
            Write-Output "  [$agentName] SKIP (link):    $name"
            $skipped++
            continue
        }

        # --- Check cc-switch source exists ---
        $ccsSrc = Join-Path $skillsDir $name
        if (-not (Test-Path $ccsSrc)) {
            Write-Output "  [$agentName] WARN (no src):  $name -- cc-switch dir missing, keeping copy"
            $kept++
            continue
        }

        # --- Validate junction target matches source ---
        if (-not $Force) {
            $agentSkill = Join-Path $d.FullName 'SKILL.md'
            $ccsSkill   = Join-Path $ccsSrc     'SKILL.md'
            if ((Test-Path $agentSkill) -and (Test-Path $ccsSkill)) {
                # LOW #18: 先比较大小和修改时间，快速跳过相同文件
                $aItem = Get-Item $agentSkill
                $cItem = Get-Item $ccsSkill
                if ($aItem.Length -eq $cItem.Length -and $aItem.LastWriteTime -eq $cItem.LastWriteTime) {
                    # 文件可能相同，直接继续转换
                } else {
                    $aHash = (Get-FileHash $agentSkill -Algorithm MD5).Hash
                    $cHash = (Get-FileHash $ccsSkill   -Algorithm MD5).Hash
                    if ($aHash -ne $cHash) {
                        Write-Output "  [$agentName] DIFF (content mismatch): $name"
                        Write-Output "    Agent hash=$aHash  ccswitch hash=$cHash"
                        Write-Output "    Use -Force to overwrite, or manually reconcile first."
                        $kept++
                        continue
                    }
                }
            }
        }

        # --- Replace with junction ---
        Write-Output "  [$agentName] CONVERT:       $name -> junction"
        if (-not $DryRun) {
            # CRITICAL #2: 安全的两阶段替换 — 先备份到临时位置，失败可回滚
            $backupDir = Join-Path $CcSwitchDir "skill-backups\$(Get-Date -Format 'yyyyMMdd_HHmmss')_${agentName}_${name}"
            $backupOk = $false
            try {
                New-Item -ItemType Directory -Path (Split-Path $backupDir -Parent) -Force -EA SilentlyContinue | Out-Null
                Copy-Item -LiteralPath $d.FullName -Destination $backupDir -Recurse -Force -ErrorAction Stop
                $backupOk = $true
            } catch {
                Write-Warning "  [$agentName] Backup failed for $name : $($_.Exception.Message)"
                Write-Output "  [$agentName] Skipping conversion (backup is required for safety)"
                $kept++
                continue
            }

            try {
                # HIGH #7: TOCTOU 防护 — 重新确认源仍存在
                if (-not (Test-Path $ccsSrc)) {
                    throw "cc-switch source disappeared: $ccsSrc"
                }

                Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop
                cmd /c mklink /J "$($d.FullName)" "$ccsSrc" | Out-Null

                if (-not (Test-Path $d.FullName)) {
                    throw "Junction creation failed for $($d.FullName)"
                }
            } catch {
                Write-Error "  [$agentName] FAILED junction for $name! $($_.Exception.Message)"
                # CRITICAL #2: 自动回滚
                if ($backupOk -and -not (Test-Path $d.FullName)) {
                    Write-Output "  [$agentName] Restoring from backup..."
                    try {
                        Copy-Item -LiteralPath $backupDir -Destination $d.FullName -Recurse -Force -ErrorAction Stop
                        Write-Output "  [$agentName] Restore successful."
                    } catch {
                        Write-Error "  [$agentName] RESTORE ALSO FAILED! Backup at: $backupDir"
                    }
                }
                continue
            }
        }
        $converted++
    }

    # Phase 2: 创建缺失的 junction link
    foreach ($name in $expected.Keys) {
        $targetPath = Join-Path $agentDir $name
        if (Test-Path $targetPath) { continue }  # 已存在

        $ccsSrc = Join-Path $skillsDir $name
        if (-not (Test-Path $ccsSrc)) {
            Write-Output "  [$agentName] SKIP CREATE (no cc-switch src): $name"
            continue
        }

        Write-Output "  [$agentName] CREATE:        $name -> junction"
        if (-not $DryRun) {
            try {
                cmd /c mklink /J "$targetPath" "$ccsSrc" | Out-Null
                if (-not (Test-Path $targetPath)) {
                    throw "Junction creation failed for $targetPath"
                }
            } catch {
                Write-Error "  [$agentName] FAILED create junction for $name! $($_.Exception.Message)"
                continue
            }
        }
        $created++
    }

    Write-Output "  [$agentName] Done: converted=$converted  created=$created  removed=$removed  skipped=$skipped  kept=$kept"
}

Write-Output "=== CC-SWITCH LINK SYNC ==="
Write-Output "Mode: $(if ($DryRun) {'DRY RUN'} else {'LIVE'})"
Write-Output ''

if ($Target -in @('claude','all')) {
    Write-Output "--- Claude ---"
    $expectedClaude = Get-ExpectedSkills 'claude'
    Sync-AgentLinks $ClaudeDir 'claude' $expectedClaude
    Write-Output ''
}
if ($Target -in @('codex','all')) {
    Write-Output "--- Codex ---"
    $expectedCodex = Get-ExpectedSkills 'codex'
    Sync-AgentLinks $CodexDir 'codex' $expectedCodex
    Write-Output ''
}
if ($Target -in @('agents','all')) {
    Write-Output "--- Agents (universal) ---"
    $expectedAgents = Get-ExpectedSkills 'agents'
    Sync-AgentLinks $AgentsDir 'agents' $expectedAgents
    Write-Output ''
}

Write-Output "=== DONE ==="
