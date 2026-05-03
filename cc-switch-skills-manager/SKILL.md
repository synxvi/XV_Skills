---
name: cc-switch-skills-manager
description: >
  Manage skills across cc-switch, Claude, and Codex agent directories.
  Scans all skill locations, identifies agent-native vs cc-switch-managed skills,
  reports mismatches, and converts copies into junction links with a single source of truth in cc-switch.
  Use when: auditing skills, migrating agent-created skills to cc-switch, syncing agent directories,
  or resolving copy/link mismatches.
---

# CC-Switch Skills Manager

Manage skills across cc-switch, Claude, and Codex with a single source of truth.

## Core Principles

1. **cc-switch is the single source** for all managed skills.
2. **Agent directories** (`.claude/skills`, `.agents/skills`) hold **junction links**, not copies.
3. **Agent-native skills** (not in cc-switch DB) are **NEVER touched** by this tool.
4. All destructive operations require **explicit user confirmation**.

## Quick Start

```powershell
# 1. Scan all skill locations
powershell -File {baseDir}/scripts/scan.ps1 -Compact

# 2. Scan as JSON (for agent consumption)
powershell -File {baseDir}/scripts/scan.ps1
```

## Scan Output Legend

| Marker | Meaning | Action |
|--------|---------|--------|
| `[NATIVE]` | Skill exists only in agent dir, NOT in cc-switch DB | Ask user: migrate to cc-switch? |
| `[COPY]` | In cc-switch DB + agent dir as real copy | Convert to junction link |
| `[LINK]` | In cc-switch DB + agent dir as junction link | Already synced, no action |
| `[CCS]` | Only in cc-switch, no agent link | Normal for agent-specific or disabled skills |
| `[?]` | Unknown state | Review manually |

## Workflow

### Step 1: Scan

Run the scan to get current state. Present the summary table to the user.

```powershell
powershell -File {baseDir}/scripts/scan.ps1 -Compact
```

The output shows:
- Total skill count
- Breakdown by status (Native / Linked / Copies / CCS-only)
- Per-skill location matrix (ccswitch / claude / agents)

### Step 2: Present Findings

Present findings to user grouped by status:

1. **[NATIVE] agent-native skills** -- highlight these FIRST, they are at risk of accidental deletion
   - Ask user: "This skill is only in {agent} and not managed by cc-switch. Migrate to cc-switch?"
   - If yes: run migrate.ps1
   - If no: leave it, note it as explicitly excluded

2. **[COPY] has-copies** -- suggest conversion to junction links
   - Show any content diffs if SKILL.md differs between agent copy and cc-switch
   - Ask user: "Convert copies to junction links? (keeps cc-switch as source)"
   - If yes: run sync-links.ps1

3. **[LINK] linked** -- already synced, just report

4. **[CCS] ccswitch-only** -- no action needed

### Step 3: Migrate (if needed)

For native skills the user wants to manage via cc-switch:

```powershell
# Migrate from Claude
powershell -File {baseDir}/scripts/migrate.ps1 -Directory <skill-dir> -Source claude

# Migrate from Codex
powershell -File {baseDir}/scripts/migrate.ps1 -Directory <skill-dir> -Source agents

# Preview without changes
powershell -File {baseDir}/scripts/migrate.ps1 -Directory <skill-dir> -Source agents -DryRun
```

This copies the skill into cc-switch storage and registers it in the DB.
Default: enables the skill for the source agent only.

**After migration, determine if the skill is universal or agent-specific, then update DB enable flags accordingly.**

#### Skill Scope Classification

Read the migrated skill's `SKILL.md` content and classify its scope:

| Scope | Criteria | DB Flags |
|-------|----------|----------|
| **Universal** | Uses only generic tools (Bash, Read, Write, Edit, Grep, Glob), no agent-specific paths/APIs/concepts | Enable for ALL agents |
| **Agent-specific** | References agent-exclusive concepts, paths, or tools | Enable for SOURCE agent only |

**Agent-specific signals to check:**

| Agent | Signals |
|-------|---------|
| Claude | `~/.claude/`, `.claude/skills/`, `.claude/sessions/`, `settings.json`, `CLAUDE.md`, Claude Code CLI, `Anthropic SDK`, `claude-api`, `claude-desktop` |
| Codex | `~/.codex/`, `.codex/`, OpenAI API, `openai` SDK, GPT-specific |
| Opencode | `~/.opencode/`, opencode-specific configs |
| Gemini | `~/.gemini/`, Gemini API, Google AI |

**Universal signals** (safe for all agents):
- Standard filesystem operations (rm, ls, cp, grep, sed, awk)
- Generic Bash commands (git, npm, docker, curl)
- Language/framework patterns (Python, TypeScript, Rust, etc.)
- General productivity tools (file management, text processing, search)

#### Classification Workflow

1. Read the SKILL.md of the migrated skill
2. Check for agent-specific signals listed above
3. Determine scope:
   - If ANY agent-specific signal found → **agent-specific**
   - If only universal signals found → **universal**
4. Update DB enable flags:

```bash
# Universal skill: enable for all agents
python -c "
import sqlite3
db = '<cc-switch-db-path>'
conn = sqlite3.connect(db)
conn.execute(\"UPDATE skills SET enabled_claude=1, enabled_codex=1, enabled_opencode=1 WHERE directory='<skill-dir>'\")
conn.commit()
conn.close()
"

# Agent-specific skill: only source agent (already set by migrate.ps1, no extra action needed)
```

5. Run `sync-links.ps1` to create junction links for all enabled agents

#### Examples

| Skill | Scope | Reasoning |
|-------|-------|-----------|
| `session-cleaner` | **Universal** | Uses only Bash/Grep on `~/.claude/session-data/` — but the concept (cleaning session files) is universally applicable once adapted. However it references `.claude/sessions/` → **Claude-specific** |
| `git-essentials` | **Universal** | Only uses `git` commands, no agent-specific paths |
| `claude-api` | **Claude-specific** | References `anthropic` SDK, Claude-specific caching/token concepts |
| `frontend-patterns` | **Universal** | React/Next.js patterns, no agent dependencies |
| `springboot-tdd` | **Universal** | JUnit/MockMvc patterns, no agent dependencies |

### Step 4: Sync Links (if needed)

Replace agent copies with junction links:

```powershell
# Sync both Claude and Codex
powershell -File {baseDir}/scripts/sync-links.ps1

# Sync only Claude
powershell -File {baseDir}/scripts/sync-links.ps1 -Target claude

# Preview without changes
powershell -File {baseDir}/scripts/sync-links.ps1 -DryRun

# Force even if content differs
powershell -File {baseDir}/scripts/sync-links.ps1 -Force
```

Safety features:
- **Never touches agent-native skills** (skips any dir not in cc-switch DB)
- **Content diff check** before converting (warns if SKILL.md differs)
- **Backup** created before each conversion (in cc-switch/skill-backups/)
- **Auto-restore** if junction creation fails

### Step 5: Verify

Run scan again to confirm all `[COPY]` are now `[LINK]`:

```powershell
powershell -File {baseDir}/scripts/scan.ps1 -Compact
```

## Agent-Specific Skills

Some skills are designed for a specific agent (e.g., `claude-api` for Claude, `opencode-controller` for Opencode).
These should only appear in the target agent's directory.

The scan output shows per-agent enable flags (`claude_en`, `codex_en`, `openc_en`).
When migrating, the skill is enabled for the source agent by default.
Use cc-switch UI or direct DB update to change enable flags.

## Safety Rules

| Action | agent-native | managed (DB) |
|--------|-------------|-------------|
| Scan   | Report only | Report |
| Delete | **NEVER** | Only via cc-switch UI |
| Migrate| Only with user OK | N/A |
| Link   | **SKIP** | Replace copy with junction |

## Troubleshooting

**Junction creation fails:**
- Windows requires Developer Mode or admin for symlinks. Junctions work without elevation.
- If junction fails, the script restores from backup automatically.

**Content mismatch warning:**
- Agent has a modified version that differs from cc-switch.
- Use `-Force` to overwrite, or manually review and update cc-switch first.

**Skills keep reappearing after deletion:**
- Check if cc-switch is running and auto-syncing.
- Disable auto-sync before manual cleanup.
