# CC-Switch Skills Manager - Scan Script
param(
    [string]$CcSwitchDir = "$env:USERPROFILE\.cc-switch",
    [string]$ClaudeDir   = "$env:USERPROFILE\.claude\skills",
    [string]$CodexDir    = "$env:USERPROFILE\.codex\skills",
    [string]$AgentsDir   = "$env:USERPROFILE\.agents\skills",
    [switch]$Compact
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dbPath    = Join-Path $CcSwitchDir 'cc-switch.db'
$skillsDir = Join-Path $CcSwitchDir 'skills'

# HIGH #6: 自动检测可用的 Python 命令
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

function Get-DirSkills([string]$path) {
    if (-not (Test-Path $path)) { return @{} }
    $dirs = Get-ChildItem -LiteralPath $path -Directory -EA SilentlyContinue |
        Where-Object { $_.Name -ne '.system' -and $_.Name -notmatch '^\.' }
    $map = @{}
    foreach ($d in $dirs) {
        $hasSkillMd = (Test-Path (Join-Path $d.FullName 'SKILL.md'))
        # LOW #14: 跳过无 SKILL.md 的目录
        if (-not $hasSkillMd) { continue }
        $map[$d.Name] = @{
            path       = $d.FullName
            hasSkillMd = $true
            modified   = $d.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        }
    }
    return $map
}

function Get-DbSkills([string]$dbPath, [string]$scriptDir) {
    if (-not (Test-Path $dbPath)) { return @{} }
    $dbreadPy = Join-Path $scriptDir 'dbread.py'

    # MEDIUM #17: 设置 UTF-8 编码
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $jsonOut = & $script:pythonCmd $dbreadPy $dbPath 2>$null
    if ($LASTEXITCODE -ne 0) { return @{} }

    # HIGH #8: JSON 解析容错
    try {
        return ($jsonOut | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        Write-Warning "Failed to parse dbread.py output: $($_.Exception.Message)"
        return @{}
    }
}

$ccsw = Get-DirSkills $skillsDir
$clau = Get-DirSkills $ClaudeDir
$code = Get-DirSkills $CodexDir
$agen = Get-DirSkills $AgentsDir
$db   = Get-DbSkills $dbPath $scriptDir

$allDirs = [System.Collections.Generic.HashSet[string]]::new()
foreach ($k in $ccsw.Keys) { $allDirs.Add($k) | Out-Null }
foreach ($k in $clau.Keys) { $allDirs.Add($k) | Out-Null }
foreach ($k in $code.Keys) { $allDirs.Add($k) | Out-Null }
foreach ($k in $agen.Keys) { $allDirs.Add($k) | Out-Null }

$rows = @()
foreach ($dir in $allDirs) {
    if ($dir -eq '.system') { continue }
    $inDb = $db.PSObject.Properties.Name -contains $dir
    $dbI  = if ($inDb) { $db.$dir } else { $null }
    $inCC = $ccsw.ContainsKey($dir)
    $inCL = $clau.ContainsKey($dir)
    $inCD = $code.ContainsKey($dir)
    $inAG = $agen.ContainsKey($dir)

    $clLink = $null; $cdLink = $null; $agLink = $null
    if ($inCL) {
        $it = Get-Item -LiteralPath $clau[$dir].path -Force -EA SilentlyContinue
        $clLink = [bool]($it.LinkType)
    }
    if ($inCD) {
        $it = Get-Item -LiteralPath $code[$dir].path -Force -EA SilentlyContinue
        $cdLink = [bool]($it.LinkType)
    }
    if ($inAG) {
        $it = Get-Item -LiteralPath $agen[$dir].path -Force -EA SilentlyContinue
        $agLink = [bool]($it.LinkType)
    }

    if (-not $inDb) {
        $status = 'agent-native'
        $origin = @()
        if ($inCL -and $inAG) { $origin = @('claude','agents') }
        elseif ($inCL)        { $origin = @('claude') }
        elseif ($inCD)        { $origin = @('codex') }
        elseif ($inAG)        { $origin = @('agents') }
    } elseif ($inCC -and -not $inCL -and -not $inCD -and -not $inAG) {
        $status = 'ccswitch-only'; $origin = @()
    } elseif ($inCC -and (($inCL -and -not $clLink) -or ($inCD -and -not $cdLink) -or ($inAG -and -not $agLink))) {
        $status = 'has-copies'; $origin = @()
    } elseif ($inCC -and ($clLink -or $cdLink -or $agLink)) {
        $status = 'linked'; $origin = @()
    } else {
        $status = 'unknown'; $origin = @()
    }

    $rows += [ordered]@{
        dir        = $dir
        name       = if ($dbI) { $dbI.name } else { $dir }
        status     = $status
        origin     = $origin
        ccswitch   = $inCC
        claude     = $inCL
        codex      = $inCD
        agents     = $inAG
        claude_lnk = $clLink
        codex_lnk  = $cdLink
        agents_lnk = $agLink
        claude_en  = if ($dbI) { [int]$dbI.claude }   else { -1 }
        codex_en   = if ($dbI) { [int]$dbI.codex }    else { -1 }
        openc_en   = if ($dbI) { [int]$dbI.opencode } else { -1 }
    }
}

$prio = @{ 'agent-native'=0; 'has-copies'=1; 'linked'=2; 'ccswitch-only'=3; 'unknown'=9 }
$rows = $rows | Sort-Object { $prio[$_.status] }, { $_.dir }

if ($Compact) {
    $nN = @($rows | Where-Object { $_.status -eq 'agent-native'  }).Count
    $nL = @($rows | Where-Object { $_.status -eq 'linked'        }).Count
    $nC = @($rows | Where-Object { $_.status -eq 'has-copies'    }).Count
    $nO = @($rows | Where-Object { $_.status -eq 'ccswitch-only' }).Count
    Write-Output "=== CC-SWITCH SKILLS SCAN ==="
    Write-Output "Total:$($rows.Count)  Native:$nN  Linked:$nL  Copies:$nC  CCS-only:$nO"
    Write-Output ''
    $fmt = '{0,-45} {1,-6} {2,-6} {3,-6} {4,-6}'
    Write-Output ($fmt -f 'DIRECTORY','CCSW','CLAUDE','CODEX','AGENTS')
    Write-Output ('-' * 75)
    foreach ($r in $rows) {
        $cc = if ($r.ccswitch) {'Y'} else {'-'}
        $cl = if ($r.claude)   {'Y'} else {'-'}
        $cd = if ($r.codex)    {'Y'} else {'-'}
        $ag = if ($r.agents)   {'Y'} else {'-'}
        $tag = switch ($r.status) {
            'agent-native'  {'[NATIVE]'}
            'has-copies'    {'[COPY]  '}
            'linked'        {'[LINK]  '}
            'ccswitch-only' {'[CCS]   '}
            default         {'[?]     '}
        }
        Write-Output ($fmt -f "$tag $($r.dir)", $cc, $cl, $cd, $ag)
    }
} else {
    $report = @{ timestamp=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); skills=$rows }
    $report | ConvertTo-Json -Depth 6 -Compress
}
