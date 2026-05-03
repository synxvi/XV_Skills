import sqlite3, sys

# CRITICAL #1: WAL 模式 + 超时
db = sys.argv[1]
try:
    conn = sqlite3.connect(db, timeout=30.0)
    conn.execute('PRAGMA journal_mode=WAL')
    cur = conn.cursor()
    cur.execute("SELECT directory FROM skills")
    for r in cur.fetchall():
        sys.stdout.buffer.write((r[0] + '\n').encode('utf-8'))
    conn.close()
except Exception as e:
    sys.stderr.write(f"link_dbread error: {e}\n")
    sys.exit(1)
