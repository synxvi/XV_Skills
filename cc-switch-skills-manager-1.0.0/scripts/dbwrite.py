import sqlite3, sys, time, os

db = sys.argv[1]
dir_name = sys.argv[2]
name = sys.argv[3]
# HIGH #4: 仅从环境变量读取，移除 sys.argv 回退（避免 GBK 编码损坏）
desc = os.environ.get('CCS_MIGRATE_DESC', '')
# argv: db, dir_name, name, en_cla, en_cod (desc via CCS_MIGRATE_DESC env var)
en_cla = int(sys.argv[4]) if len(sys.argv) > 4 else 0
en_cod = int(sys.argv[5]) if len(sys.argv) > 5 else 0

# CRITICAL #1: WAL 模式 + 超时
try:
    conn = sqlite3.connect(db, timeout=30.0)
    conn.execute('PRAGMA journal_mode=WAL')
    cur = conn.cursor()
    cur.execute("INSERT OR REPLACE INTO skills (id,name,directory,description,enabled_claude,enabled_codex,enabled_gemini,enabled_opencode,enabled_hermes,installed_at) VALUES (?,?,?,?,?,?,?,?,?,?)",
        ('local:'+dir_name, name, dir_name, desc, en_cla, en_cod, 0, 0, 0, int(time.time()*1000)))
    conn.commit()
    conn.close()
except Exception as e:
    sys.stderr.write(f"dbwrite error: {e}\n")
    sys.exit(1)

sys.stdout.buffer.write(f'DB registered: {name} (claude={en_cla} codex={en_cod})\n'.encode('utf-8'))
