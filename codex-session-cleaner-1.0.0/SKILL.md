---
name: codex-session-cleaner
description: >
  查看、管理和删除 Codex Desktop 归档会话。当用户要求查看、清理或永久删除已归档的旧会话时使用。
---

# Codex Session Cleaner

管理 `~/.codex/archived_sessions/` 下的归档会话文件（`.jsonl`）。

## JSONL 格式说明

归档文件每行一个 JSON 对象，关键 `type` 字段：
- `session_meta` — 会话元信息（timestamp、cwd）
- `turn_context` — 轮次上下文（model、cwd）
- `response_item` — 消息记录，`payload.role == "user"` 为用户消息，`payload.content` 为数组，其中 `type == "input_text"` 的 `text` 字段为消息文本

## 用法

脚本路径：`<skill_dir>/scripts/session_cleaner.py`

### Agent 命令行模式（推荐）

```bash
# 列出所有归档会话
python <skill_dir>/scripts/session_cleaner.py list

# 删除指定会话（支持逗号分隔和范围）
python <skill_dir>/scripts/session_cleaner.py delete 1,3
python <skill_dir>/scripts/session_cleaner.py delete 2-5

# 删除全部归档
python <skill_dir>/scripts/session_cleaner.py delete-all
```

### 人类交互模式

```bash
python <skill_dir>/scripts/session_cleaner.py
# 或
python <skill_dir>/scripts/session_cleaner.py interactive
```

交互模式支持：`1,3` / `2-5` / `all` / `q` 退出

## 何时使用

- 用户想查看已归档的对话
- 用户想永久删除归档会话以释放空间
- 用户询问如何清理旧的 Codex 会话

## Agent 工作流

1. 先用 `list` 命令展示归档列表
2. 根据用户意图选择 `delete`（指定序号）或 `delete-all`
3. 删除后无需额外确认