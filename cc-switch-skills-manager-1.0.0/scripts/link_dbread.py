import sqlite3, json, sys

# CRITICAL #1: WAL 模式 + 超时
db = sys.argv[1]
try:
    conn = sqlite3.connect(db, timeout=30.0)
    conn.execute('PRAGMA journal_mode=WAL')
    cur = conn.cursor()
    cur.execute("SELECT directory, enabled_claude, enabled_codex, enabled_opencode FROM skills")
    result = {}
    for r in cur.fetchall():
        result[r[0]] = {
            "claude": bool(r[1]),
            "codex": bool(r[2]),
            "opencode": bool(r[3])
        }
    conn.close()
except Exception as e:
    sys.stderr.write(f"link_dbread error: {e}\n")
    sys.exit(1)

# MEDIUM #17: 强制 UTF-8 输出
out = json.dumps(result, ensure_ascii=False)
sys.stdout.buffer.write(out.encode('utf-8'))
sys.stdout.buffer.write(b'\n')
