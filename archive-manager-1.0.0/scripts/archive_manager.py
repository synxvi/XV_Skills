"""List archived Codex sessions with summaries, allow interactive deletion."""
import json
import os
import glob

ARCHIVED_DIR = os.path.expanduser("~/.codex/archived_sessions")
MAX_USER_MSGS = 3
MAX_MSG_LEN = 80


def parse_session(filepath):
    meta = {
        "file": os.path.basename(filepath),
        "path": filepath,
        "size": os.path.getsize(filepath),
        "timestamp": "unknown",
        "cwd": "unknown",
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
                if otype == "session_meta":
                    meta["timestamp"] = payload.get("timestamp", "unknown")
                    meta["cwd"] = payload.get("cwd", "unknown")
                elif otype == "event_msg" and payload.get("type") == "user_message":
                    msg = (payload.get("message") or "").strip()
                    if msg and not msg.startswith("# Files mentioned by the user"):
                        clean = msg.replace("\n", " ").replace("\r", "")
                        meta["user_messages"].append(clean)
    except Exception as e:
        meta["error"] = str(e)
    return meta


def human_size(nbytes):
    for unit in ("B", "KB", "MB", "GB"):
        if nbytes < 1024:
            return f"{nbytes:.1f} {unit}"
        nbytes /= 1024
    return f"{nbytes:.1f} TB"


def truncate(s, maxlen):
    return s[: maxlen - 1] + "..." if len(s) > maxlen else s


def list_sessions():
    files = sorted(glob.glob(os.path.join(ARCHIVED_DIR, "*.jsonl")))
    if not files:
        return []
    sessions = [parse_session(f) for f in files]
    sessions.sort(key=lambda s: s["timestamp"], reverse=True)
    return sessions


def display_sessions(sessions):
    print()
    print("=" * 72)
    print("  Archived Sessions")
    print("=" * 72)
    if not sessions:
        print("  No archived sessions found.")
        print("=" * 72)
        return
    for i, s in enumerate(sessions, start=1):
        ts = s["timestamp"]
        if ts != "unknown" and len(ts) >= 10:
            ts_display = ts[:10] + " " + ts[11:16] if len(ts) > 15 else ts
        else:
            ts_display = ts
        cwd_short = s["cwd"]
        if len(cwd_short) > 50:
            cwd_short = "..." + cwd_short[-48:]
        print(f"\n  [{i}] {ts_display}  |  {human_size(s['size'])}")
        print(f"      Path: {cwd_short}")
        msgs = s["user_messages"]
        if msgs:
            shown = msgs[:MAX_USER_MSGS]
            for j, m in enumerate(shown):
                print(f"      Msg{j+1}: {truncate(m, MAX_MSG_LEN)}")
            remaining = len(msgs) - len(shown)
            if remaining > 0:
                print(f"      ... {remaining} more messages")
        else:
            print("      Msg: (no user messages)")
    print("\n" + "=" * 72)


def delete_sessions(sessions, indices):
    deleted = []
    for idx in indices:
        if 1 <= idx <= len(sessions):
            s = sessions[idx - 1]
            try:
                os.remove(s["path"])
                deleted.append(s["file"])
            except OSError as e:
                print(f"  X Delete failed [{idx}]: {e}")
        else:
            print(f"  X Invalid index: {idx}")
    return deleted


def parse_selection(text, max_val):
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


def main():
    sessions = list_sessions()
    display_sessions(sessions)
    if not sessions:
        return
    print("\n  Enter index to delete (e.g. 1,3 or 2-5 or all)")
    print("  Enter q to quit")
    while True:
        try:
            raw = input("\n  > ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n  Cancelled.")
            break
        if not raw or raw.lower() == "q":
            print("  Bye.")
            break
        indices = parse_selection(raw, len(sessions))
        if not indices:
            print("  No valid index found, try again.")
            continue
        names = [sessions[i - 1]["file"] for i in indices]
        print(f"\n  Will delete {len(indices)} session(s):")
        for n in names:
            print(f"    - {truncate(n, 60)}")
        try:
            confirm = input("  Confirm? (y/N): ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\n  Cancelled.")
            break
        if confirm in ("y", "yes"):
            deleted = delete_sessions(sessions, indices)
            if deleted:
                print(f"  OK Deleted {len(deleted)} session(s).")
            sessions = list_sessions()
            if sessions:
                display_sessions(sessions)
            else:
                print("\n  All sessions deleted.")
                break
        else:
            print("  Cancelled.")


if __name__ == "__main__":
    main()
