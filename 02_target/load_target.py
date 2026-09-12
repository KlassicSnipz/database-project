import os

import psycopg2
from dotenv import load_dotenv

# Chunk 1 — find where the files are, relative to this script.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)

# Chunk 2 — read DB credentials from .env (never hardcode passwords).
load_dotenv(os.path.join(ROOT_DIR, ".env"))

DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")

if not all([DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD]):
    raise RuntimeError("Missing DB_* variables — check .env in the project root.")

# Chunk 3 — open ONE transaction (autocommit OFF is the point of this chapter:
# commit only happens at the very end, only if validation passes). Everything
# below — schema, dims, fact, validation — runs inside it.
conn = psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
                        user=DB_USER, password=DB_PASSWORD)
conn.autocommit = False

cur = conn.cursor()

for sql_file in ("target_schema.sql", "load_target.sql"):
    with open(os.path.join(SCRIPT_DIR, sql_file), encoding="utf-8") as f:
        sql = f.read()
    cur.execute(sql)
    print(f"[chunk 3] {sql_file} executed (inside the open transaction)")

# Chunk 4 — run validate_target.sql in the same transaction and check it.
with open(os.path.join(SCRIPT_DIR, "validate_target.sql"), encoding="utf-8") as f:
    validate_sql = f.read()

cur.execute(validate_sql)
report = cur.fetchall()

print("=" * 60)
print("[chunk 4] validation report (check | entity | stage | target | note):")
all_pass = True

for check_name, entity, stage_val, target_val, note in report:
    print(f"[chunk 4] {check_name:15} | {entity:28} | {str(stage_val):12} | {str(target_val):12} | {note}")
    matches_rule = (
        (check_name == "row_count" and stage_val is not None and stage_val == target_val)
        or (check_name == "fact_key_check" and target_val == 0)
        or (check_name == "sum_check" and stage_val == target_val)
    )
    if not matches_rule:
        all_pass = False
        print(f"[chunk 4] ** FAILED: {check_name} / {entity} **")

# Chunk 5 — COMMIT only if every check passed; otherwise ROLLBACK.
if all_pass:
    conn.commit()
    print("=" * 60)
    print("[done] COMMITTED — all validations passed, target loaded")
else:
    conn.rollback()
    print("=" * 60)
    print("[done] ROLLED BACK — validation failed, target unchanged")

conn.close()
