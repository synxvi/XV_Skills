---
name: archive-manager
description: List, review, and delete archived Codex Desktop conversations. Use when the user asks to view, manage, clean up, or permanently delete archived or old chat sessions.
---

# Archive Manager

Manage archived Codex Desktop sessions stored in ~/.codex/archived_sessions/.

## Usage

Run the bundled Python script to list all archived sessions interactively:

`ash
python <skill_dir>/scripts/archive_manager.py
`

The script will:
1. Scan ~/.codex/archived_sessions/ for .jsonl files
2. Display each session with: timestamp, size, working directory, and up to 3 user message previews
3. Prompt for selection to delete (supports 1,3 / 2-5 / all / q to quit)

## When to use

- User wants to see what conversations have been archived
- User wants to permanently delete archived conversations to free disk space
- User asks how to clean up old Codex sessions
