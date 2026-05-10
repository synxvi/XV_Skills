"""列出归档的 Codex 会话，支持查看摘要、交互/命令行删除。"""
import argparse
import glob
import json
import os
import sys

ARCHIVED_DIR = os.path.expanduser("~/.codex/archived_sessions")
MAX_USER_MSGS = 3
MAX_MSG_LEN = 100


def parse_session(filepath):
    """解析单个归档 JSONL 文件，提取元信息和用户消息。"""
    meta = {
        "file": os.path.basename(filepath),
        "path": filepath,
        "size": os.path.getsize(filepath),
        "timestamp": "unknown",
        "cwd": "unknown",
        "model": "unknown",
        "user_messages": [],
    }
    try:
        with open(filepath, "r", encoding="utf-8") as fh:
            for line in fh:
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                otype = obj.get("type", "")
                payload = obj.get("payload", {})
                if not isinstance(payload, dict):
                    continue
                # 提取会话元信息
                if otype == "session_meta":
                    meta["timestamp"] = payload.get("timestamp", "unknown")
                    meta["cwd"] = payload.get("cwd", "unknown")
                # 提取模型信息
                elif otype == "turn_context":
                    if payload.get("model"):
                        meta["model"] = payload["model"]
                    if payload.get("cwd") and meta["cwd"] == "unknown":
                        meta["cwd"] = payload["cwd"]
                # 提取用户消息 — response_item 格式
                elif otype == "response_item":
                    if payload.get("role") == "user":
                        content = payload.get("content", [])
                        if isinstance(content, list):
                            for part in content:
                                if isinstance(part, dict) and part.get("type") == "input_text":
                                    text = (part.get("text") or "").strip()
                                    if text and not text.startswith("# AGENTS.md instructions"):
                                        clean = text.replace("\n", " ").replace("\r", "")
                                        meta["user_messages"].append(clean)
                                        break
                # 兼容旧格式: event_msg + user_message
                elif otype == "event_msg" and payload.get("type") == "user_message":
                    msg = (payload.get("message") or "").strip()
                    if msg and not msg.startswith("# Files mentioned by the user"):
                        clean = msg.replace("\n", " ").replace("\r", "")
                        meta["user_messages"].append(clean)
    except Exception as e:
        meta["error"] = str(e)
    return meta


def human_size(nbytes):
    """将字节数转换为人类可读的大小。"""
    for unit in ("B", "KB", "MB", "GB"):
        if nbytes < 1024:
            return f"{nbytes:.1f} {unit}"
        nbytes /= 1024
    return f"{nbytes:.1f} TB"


def truncate(s, maxlen):
    """截断字符串到指定长度。"""
    return s[: maxlen - 3] + "..." if len(s) > maxlen else s


def list_sessions():
    """列出所有归档会话并按时间降序排列。"""
    files = sorted(glob.glob(os.path.join(ARCHIVED_DIR, "*.jsonl")))
    if not files:
        return []
    sessions = [parse_session(f) for f in files]
    sessions.sort(key=lambda s: s["timestamp"], reverse=True)
    return sessions


def format_session_line(i, s):
    """格式化单个会话的摘要行。"""
    ts = s["timestamp"]
    if ts != "unknown" and len(ts) >= 10:
        ts_display = ts[:10] + " " + ts[11:16] if len(ts) > 15 else ts
    else:
        ts_display = ts
    cwd_short = s["cwd"]
    if len(cwd_short) > 50:
        cwd_short = "..." + cwd_short[-48:]
    model = s.get("model", "unknown")
    msgs = s["user_messages"]
    preview = truncate(msgs[0], MAX_MSG_LEN) if msgs else "(无用户消息)"
    return f"  [{i}] {ts_display} | {human_size(s['size'])} | {model} | {preview}"


def display_sessions(sessions):
    """以表格形式显示所有归档会话。"""
    print()
    print("=" * 72)
    print("  归档会话列表")
    print("=" * 72)
    if not sessions:
        print("  暂无归档会话。")
        print("=" * 72)
        return
    for i, s in enumerate(sessions, start=1):
        print(format_session_line(i, s))
    print("\n" + "=" * 72)


def delete_sessions(sessions, indices):
    """删除指定索引的会话文件。"""
    deleted = []
    for idx in indices:
        if 1 <= idx <= len(sessions):
            s = sessions[idx - 1]
            try:
                os.remove(s["path"])
                deleted.append(s["file"])
            except OSError as e:
                print(f"  ✗ 删除失败 [{idx}]: {e}")
        else:
            print(f"  ✗ 无效索引: {idx}")
    return deleted


def parse_selection(text, max_val):
    """解析用户输入的选择范围，支持 1,3 / 2-5 / all。"""
    text = text.strip().lower()
    if text == "all":
        return list(range(1, max_val + 1))
    indices = set()
    for part in text.split(","):
        part = part.strip()
        if "-" in part:
            try:
                a, b = part.split("-", 1)
                a, b = int(a.strip()), int(b.strip())
                indices.update(range(min(a, b), max(a, b) + 1))
            except ValueError:
                pass
        else:
            try:
                indices.add(int(part))
            except ValueError:
                pass
    return sorted(i for i in indices if 1 <= i <= max_val)


def cmd_list():
    """命令行模式：列出所有归档会话。"""
    sessions = list_sessions()
    display_sessions(sessions)
    return sessions


def cmd_delete(indices):
    """命令行模式：删除指定索引的会话。"""
    sessions = list_sessions()
    if not sessions:
        print("暂无归档会话。")
        return
    deleted = delete_sessions(sessions, indices)
    if deleted:
        print(f"\n  ✓ 已删除 {len(deleted)} 个会话。")
    else:
        print("\n  未删除任何会话。")


def cmd_delete_all():
    """命令行模式：删除全部归档会话。"""
    sessions = list_sessions()
    if not sessions:
        print("暂无归档会话。")
        return
    all_indices = list(range(1, len(sessions) + 1))
    deleted = delete_sessions(sessions, all_indices)
    if deleted:
        print(f"\n  ✓ 已删除全部 {len(deleted)} 个会话。")


def cmd_interactive():
    """交互模式：列出会话并等待用户选择删除。"""
    sessions = cmd_list()
    if not sessions:
        return
    print("\n  输入序号删除（如 1,3 或 2-5 或 all），q 退出")
    while True:
        try:
            raw = input("\n  > ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n  已取消。")
            break
        if not raw or raw.lower() == "q":
            print("  再见。")
            break
        indices = parse_selection(raw, len(sessions))
        if not indices:
            print("  未找到有效序号，请重试。")
            continue
        names = [sessions[i - 1]["file"] for i in indices]
        print(f"\n  将删除 {len(indices)} 个会话：")
        for n in names:
            print(f"    - {truncate(n, 60)}")
        try:
            confirm = input("  确认？(y/N): ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\n  已取消。")
            break
        if confirm in ("y", "yes"):
            deleted = delete_sessions(sessions, indices)
            if deleted:
                print(f"  ✓ 已删除 {len(deleted)} 个会话。")
            sessions = list_sessions()
            if sessions:
                display_sessions(sessions)
            else:
                print("\n  全部会话已删除。")
                break
        else:
            print("  已取消。")


def main():
    parser = argparse.ArgumentParser(
        description="管理 Codex Desktop 归档会话"
    )
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("list", help="列出所有归档会话")

    p_del = sub.add_parser("delete", help="删除指定会话（如 1,3 或 2-5）")
    p_del.add_argument("indices", help="要删除的序号，逗号分隔或范围，如 1,3 或 2-5")

    sub.add_parser("delete-all", help="删除全部归档会话")
    sub.add_parser("interactive", help="交互模式（默认）")

    args = parser.parse_args()

    if args.command == "list":
        cmd_list()
    elif args.command == "delete":
        indices = parse_selection(args.indices, 9999)
        if indices:
            cmd_delete(indices)
        else:
            print("无效的序号格式。")
    elif args.command == "delete-all":
        cmd_delete_all()
    else:
        cmd_interactive()


if __name__ == "__main__":
    main()
