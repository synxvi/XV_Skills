---
name: claude-session-cleaner
description: "扫描并清理 Claude Code 会话数据：以表格展示所有会话统计，标识来源/日期/类型，支持按 ID 选择性清理或全部清理。"
version: "1.0.0"
---

# Claude Session Cleaner

扫描 `~/.claude/` 下所有会话数据，以表格形式展示统计信息，支持交互式选择清理。

## 使用场景

- 磁盘空间不足，需要清理历史会话数据
- 想要查看所有 Claude 对话记录的概览
- 批量清理特定项目或特定日期之前的会话

## 执行流程

### 第一步：扫描所有会话数据

运行以下脚本扫描 `~/.claude/` 目录：

```bash
node -e "
const fs = require('fs');
const path = require('path');

const claudeDir = path.join(process.env.HOME || process.env.USERPROFILE, '.claude');
const projectsDir = path.join(claudeDir, 'projects');
const sessionsDir = path.join(claudeDir, 'sessions');

const results = [];

// 1. 活跃会话（sessions/*.json）
if (fs.existsSync(sessionsDir)) {
  const sessionFiles = fs.readdirSync(sessionsDir).filter(f => f.endsWith('.json'));
  for (const f of sessionFiles) {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(sessionsDir, f), 'utf8'));
      results.push({
        id: data.sessionId || f.replace('.json',''),
        project: data.cwd || 'unknown',
        type: 'active',
        source: data.entrypoint || 'unknown',
        size: fs.statSync(path.join(sessionsDir, f)).size,
        date: data.startedAt ? new Date(data.startedAt).toISOString().split('T')[0] : 'unknown',
        pid: data.pid,
        path: path.join(sessionsDir, f),
        version: data.version || ''
      });
    } catch(e) {}
  }
}

// 2. 项目会话（projects/*）
if (fs.existsSync(projectsDir)) {
  const projectDirs = fs.readdirSync(projectsDir, {withFileTypes: true}).filter(d => d.isDirectory());
  for (const d of projectDirs) {
    const dirPath = path.join(projectsDir, d.name);

    // 主会话文件（非 agent- 开头的 .jsonl）
    const mainFiles = fs.readdirSync(dirPath).filter(f => f.endsWith('.jsonl') && !f.startsWith('agent-'));
    for (const f of mainFiles) {
      const fpath = path.join(dirPath, f);
      const stat = fs.statSync(fpath);
      const content = fs.readFileSync(fpath, 'utf8').trim();
      const lines = content.split('\n');
      let userMsgs = 0;
      let assistantMsgs = 0;
      for (const line of lines) {
        try {
          const obj = JSON.parse(line);
          if (obj.type === 'user') userMsgs++;
          if (obj.type === 'assistant') assistantMsgs++;
        } catch(e) {}
      }
      results.push({
        id: f.replace('.jsonl',''),
        project: d.name,
        type: 'main',
        source: 'claude-code',
        size: stat.size,
        date: stat.mtime.toISOString().split('T')[0],
        messages: userMsgs + assistantMsgs,
        userMsgs,
        assistantMsgs,
        path: fpath
      });
    }

    // 子代理文件（agent-*.jsonl）
    const agentFiles = fs.readdirSync(dirPath).filter(f => f.startsWith('agent-') && f.endsWith('.jsonl'));
    for (const f of agentFiles) {
      const fpath = path.join(dirPath, f);
      const stat = fs.statSync(fpath);
      results.push({
        id: f.replace('.jsonl',''),
        project: d.name,
        type: 'agent',
        source: 'subagent',
        size: stat.size,
        date: stat.mtime.toISOString().split('T')[0],
        path: fpath
      });
    }

    // 会话子目录中的子代理
    const subDirs = fs.readdirSync(dirPath, {withFileTypes: true}).filter(sd => sd.isDirectory());
    for (const sd of subDirs) {
      const subAgentDir = path.join(dirPath, sd.name, 'subagents');
      if (!fs.existsSync(subAgentDir)) continue;
      const subAgentFiles = fs.readdirSync(subAgentDir).filter(f => f.endsWith('.jsonl'));
      for (const f of subAgentFiles) {
        const fpath = path.join(subAgentDir, f);
        const stat = fs.statSync(fpath);
        results.push({
          id: f.replace('.jsonl',''),
          project: d.name,
          type: 'sub-agent',
          source: sd.name.substring(0,12) + '...',
          size: stat.size,
          date: stat.mtime.toISOString().split('T')[0],
          path: fpath,
          parentSession: sd.name
        });
      }

      // meta.json 文件
      const metaFiles = fs.readdirSync(subAgentDir).filter(f => f.endsWith('.meta.json'));
      for (const f of metaFiles) {
        const fpath = path.join(subAgentDir, f);
        results.push({
          id: f.replace('.meta.json',''),
          project: d.name,
          type: 'meta',
          source: 'subagent-meta',
          size: fs.statSync(fpath).size,
          date: fs.statSync(fpath).mtime.toISOString().split('T')[0],
          path: fpath,
          parentSession: sd.name
        });
      }
    }

    // sessions-index.json
    const idxPath = path.join(dirPath, 'sessions-index.json');
    if (fs.existsSync(idxPath)) {
      results.push({
        id: 'sessions-index',
        project: d.name,
        type: 'index',
        source: 'session-index',
        size: fs.statSync(idxPath).size,
        date: fs.statSync(idxPath).mtime.toISOString().split('T')[0],
        path: idxPath
      });
    }
  }
}

// 输出 JSON
console.log(JSON.stringify(results, null, 2));
"
```

### 第二步：格式化表格展示

根据扫描结果，按以下格式展示表格：

```markdown
## Claude 会话数据统计

**扫描路径：** `~/.claude/`
**总大小：** {total_size}
**会话总数：** {total_count}

### 活跃会话（当前运行）

| # | ID | 项目 | 来源 | 大小 | 日期 | PID |
|---|-----|------|------|------|------|-----|
| 1 | xxx | path | desktop-3p/vscode | 1.2KB | 2026-05-04 | 1234 |

### 主会话（完整对话上下文）

| # | ID | 项目 | 用户消息 | 助手消息 | 大小 | 日期 |
|---|-----|------|----------|----------|------|------|
| 1 | xxx | Claude-Space | 36 | 36 | 805KB | 2026-05-04 |

### 子代理调用记录

| # | ID | 项目 | 类型 | 大小 | 日期 |
|---|-----|------|------|------|------|
| 1 | agent-xxx | Obsidian-Vault | agent | 2KB | 2026-05-04 |

### 会话索引

| # | ID | 项目 | 大小 | 日期 |
|---|-----|------|------|------|
| 1 | sessions-index | Design-pattern | 4KB | 2026-01-30 |
```

### 第三步：提供清理选项

向用户展示以下选项：

```
请选择清理方式：
1. 按 ID 选择性清理（输入 ID，逗号分隔）
2. 按项目清理（输入项目名称）
3. 按日期清理（清理此日期之前的会话）
4. 按类型清理（agent / sub-agent / main / index / meta）
5. 清理全部（保留当前活跃会话）
6. 退出
```

### 第四步：执行清理

根据用户选择执行清理：

1. **按 ID 清理：** 匹配表格中的 ID，删除对应文件
2. **按项目清理：** 删除指定项目目录下的所有文件
3. **按日期清理：** 删除修改日期早于指定日期的文件
4. **按类型清理：** 删除指定类型的所有文件
5. **全部清理：** 删除所有非活跃会话文件

清理前显示将删除的文件列表，确认后执行。

### 第五步：确认与报告

```markdown
## 清理完成

- 删除文件数：{count}
- 释放空间：{size}
- 保留文件数：{remaining}
```

## 安全规则

- **永远不删除活跃会话**（`sessions/*.json` 中 PID 对应进程仍在运行的）
- 清理前必须二次确认
- 不删除 `sessions-index.json` 除非用户明确要求
- 提供 dry-run 模式：先展示会删除什么，不实际执行

## 输出格式

始终以中文输出，使用 Markdown 表格格式，ID 使用完整 UUID（不截断），方便用户复制粘贴。
