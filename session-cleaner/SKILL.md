---
name: session-cleaner
description: View, manage and delete archived Claude Code sessions. List all sessions with summaries, delete by index number, with active session protection.
---

# Session Cleaner

管理 Claude Code 归档对话：查看摘要、按序号删除，自动跳过活跃会话。

## When to Activate

- 用户想查看历史对话记录
- 用户想清理/删除归档的对话
- 用户输入 `/session-cleaner`
- 用户提到"清理对话"、"删除会话"、"归档管理"等关键词

## 执行流程

### Step 0: 检测活跃会话（保护机制）

**必须在扫描之前执行**，提取所有活跃会话对应的项目名，用于排除保护。

```bash
active_projects=""
active_files=""
for sf in "$HOME/.claude/sessions/"*.json; do
  [ -f "$sf" ] || continue
  cwd=$(grep -o '"cwd":"[^"]*"' "$sf" | head -1 | sed 's/"cwd":"//;s/"$//')
  if [ -n "$cwd" ]; then
    pname=$(echo "$cwd" | sed 's|\\|/|g' | sed 's|/*$||' | sed 's|.*/||' | tr '[:upper:]' '[:lower:]')
    active_projects="$active_projects|$pname|"
  fi
done
echo "活跃会话项目: $active_projects"
```

将 `active_projects` 保存为变量，在 Step 1 中用于过滤。

### Step 1: 扫描并列出所有会话（排除活跃会话）

运行以下 Bash 命令扫描 `~/.claude/session-data/` 目录中的所有 `.tmp` 文件，提取每个会话的元信息和摘要。

**关键保护逻辑**：从文件名中提取项目名，如果与活跃会话项目名匹配则标记为 `[活跃]`，删除时自动跳过。

```bash
session_dir="$HOME/.claude/session-data"
files=($(ls -t "$session_dir"/*.tmp 2>/dev/null))

if [ ${#files[@]} -eq 0 ]; then
  echo "没有找到任何会话记录。"
  exit 0
fi

echo "=== Claude Code 会话列表 ==="
echo ""

i=1
active_count=0
deletable_count=0
for f in "${files[@]}"; do
  filename=$(basename "$f")

  # 从文件名提取项目名: 2026-05-02-ob-sync-plugin-session.tmp -> ob-sync-plugin
  file_project=$(echo "$filename" | sed 's/^[0-9-]*-//' | sed 's/-session\.tmp$//' | tr '[:upper:]' '[:lower:]')

  # 检查是否为活跃会话
  is_active=""
  case "$active_projects" in
    *"|$file_project|"*) is_active="yes" ;;
  esac

  # 提取元信息
  date=$(grep -m1 '^\*\*Date:\*\*' "$f" | sed 's/\*\*Date:\*\* //')
  project=$(grep -m1 '^\*\*Project:\*\*' "$f" | sed 's/\*\*Project:\*\* //')
  updated=$(grep -m1 '^\*\*Last Updated:\*\*' "$f" | sed 's/\*\*Last Updated:\*\* //')

  # 提取任务摘要（Tasks 部分前3行，清理 XML 标签、IDE 消息和多余空白）
  tasks=$(sed -n '/^### Tasks$/,/^### /{ /^### /d; p; }' "$f" | head -3 | sed 's/^- //' | sed 's/<[^>]*>//g' | grep -v 'The user opened the file' | grep -v 'This may or may not be related' | grep -v 'current_note' | sed 's/^  *//' | sed 's/  */ /g' | tr '\n' ' | ' | head -c 200)

  if [ -n "$is_active" ]; then
    echo "[$i] $date $updated | 项目: $project  [活跃 - 受保护]"
    active_count=$((active_count + 1))
  else
    echo "[$i] $date $updated | 项目: $project"
    deletable_count=$((deletable_count + 1))
  fi
  echo "    摘要: $tasks"
  echo "    文件: $filename"
  echo ""

  i=$((i + 1))
done

echo "共 $((i-1)) 个会话记录（$active_count 个活跃受保护，$deletable_count 个可删除）"
```

将输出以格式化的列表形式展示给用户。**活跃会话标记为 `[活跃 - 受保护]`，在 Step 3-5 中必须跳过这些序号。**

### Step 2: 询问用户操作

使用 `AskUserQuestion` 工具询问用户：

- 问题："请输入要删除的会话序号（支持 `1,3,5` 多选、`1-3` 范围、或 `all` 全部删除，活跃会话会自动跳过），输入 `0` 或留空取消"
- 提供选项说明

### Step 3: 解析用户输入

解析用户输入的序号，支持以下格式：
- 单个序号：`3`
- 多个序号：`1,3,5`
- 范围：`1-3`（删除第1到第3个）
- 全部：`all`
- 取消：`0` 或空

**过滤活跃会话**：如果用户选择的序号包含活跃会话，自动跳过并提示用户"会话 [X] 为活跃会话，已跳过"。

### Step 4: 确认删除

列出即将删除的会话详情（不含活跃会话），再次确认：

```
即将删除以下会话（活跃会话已自动跳过）：
[2] 2026-04-30 ob-sync-plugin - 参考这个插件的页面设计...
[5] 2026-04-27 ob-sync-plugin - ...

跳过的活跃会话：
[1] 2026-05-02 ob-sync-plugin [活跃]

确认删除？(y/n)
```

### Step 5: 执行删除

```bash
# 对每个选中的非活跃文件执行删除
rm -f "$HOME/.claude/session-data/<选中的文件名>"
```

### Step 6: 报告结果

展示删除结果：
- 成功删除的会话数量和列表
- 跳过的活跃会话（如有）
- 剩余会话数量

## 注意事项

- **活跃会话保护**：通过 `~/.claude/sessions/*.json` 中提取活跃项目名，与 `.tmp` 文件名匹配来自动跳过
- 删除操作不可逆，必须二次确认
- 不要删除 `compaction-log.txt` 文件
- 优先按时间倒序排列（最近的在前）
- 当 `sessions/` 目录为空时（无活跃会话），所有会话均可删除
