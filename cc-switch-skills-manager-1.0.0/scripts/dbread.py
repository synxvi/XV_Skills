import sqlite3, json, sys, os

# CRITICAL #1: WAL 模式 + 超时，防止并发锁定
db = sys.argv[1]
try:
    conn = sqlite3.connect(db, timeout=30.0)
    conn.execute('PRAGMA journal_mode=WAL')
    cur = conn.cursor()
    cur.execute("SELECT name,directory,description,enabled_claude,enabled_codex,enabled_opencode FROM skills")
    result = {}
    for r in cur.fetchall():
        result[r[1]] = {"name":r[0],"directory":r[1],"desc":(r[2] or "")[:100],"claude":r[3],"codex":r[4],"opencode":r[5]}
    conn.close()
except Exception as e:
    sys.stderr.write(f"dbread error: {e}\n")
    sys.exit(1)

# MEDIUM #17: 强制 UTF-8 输出，避免 Windows GBK 编码问题
out = json.dumps(result, ensure_ascii=False)
sys.stdout.buffer.write(out.encode('utf-8'))
sys.stdout.buffer.write(b'\n')
