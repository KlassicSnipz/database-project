# Documentation: How `01_staging/load_staging.py` works

Everything explained in detail, as discussed — from the 1-minute view down to
each individual line and the three libraries it uses.

- The 5-chunk summary
- What each import is for
- Every chunk explained line by line (Chunks 4 & 5 in extra detail)
- Why we need SQLAlchemy at all (the psycopg2 / pandas / SQLAlchemy story)
- A chunk map table and what the script deliberately does NOT do

---

## Part 1 — The whole script in 5 compact steps

1. **Find paths** — locate the script itself, the project root, and `Datasets/` from there (works anywhere).
2. **Get credentials** — read host/port/db/user/password from `.env`; crash with a clear error if one is missing.
3. **Prepare the DB** — run `staging_schema.sql` through psycopg2: creates the `stage` schema + 9 all-TEXT tables and empties them (safe to re-run).
4. **Load each CSV** — for all 9: read as raw text (only empty cells become NULL), lowercase the headers, append rows into its `stage.*_raw` table.
5. **Verify & clean up** — `SELECT COUNT(*)` per table vs CSV row count → PASS/FAIL print, then close the connection.

---

## Part 2 — What the imports are for

```python
import os                                  # folders/paths ("/app/01_staging" etc.)
import pandas as pd                        # reads CSVs into table objects (DataFrames)
import psycopg2                            # connects to PostgreSQL directly
from sqlalchemy import create_engine       # the connection pandas uses to load tables
from dotenv import load_dotenv             # reads the .env file (passwords, host...)
```

---

## Part 3 — Chunk 1: find where the files are

```python
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
DATA_DIR = os.path.join(ROOT_DIR, "Datasets")
```

Line by line:

- `__file__` is the path of this very script, e.g. `/app/01_staging/load_staging.py`
- `os.path.dirname(...)` strips the file name and keeps the folder → `SCRIPT_DIR` = `/app/01_staging`
- `dirname` again, one level up → `ROOT_DIR` = `/app` (the project root)
- `os.path.join` glues paths safely → `DATA_DIR` = `/app/Datasets`, where the CSVs live

Why do it this way? The script asks itself "where am I?" and navigates relative to
that. It works no matter which folder you run it from, inside Docker or outside.
It never prints anything — it just sets up 3 path variables for later.

---

## Part 4 — Chunk 2: read DB credentials from `.env`

```python
load_dotenv(os.path.join(ROOT_DIR, ".env"))

DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")

if not all([DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD]):
    raise RuntimeError("Missing DB_* variables — check .env in the project root.")

print(f"[chunk 2] target: {DB_USER}@{DB_HOST}:{DB_PORT}/{DB_NAME}")
```

- `load_dotenv(...)` reads the project's `.env` file into memory. That is where the
  password lives — passwords must never be typed inside the code. Inside Docker,
  `.env` says `DB_HOST=db` (the container's name).
- `os.getenv("NAME")` returns the value of that variable (or `None` if missing).
- The `if not all([...])` is a safety check. `all([...])` is only True if **every**
  value exists. If one is missing → `raise RuntimeError` immediately stops the script
  with a clear message. Better crash early than fail mysteriously later.
- `print` just shows where it is going to connect, e.g. `postgres@db:5432/DatabaseProject`.

---

## Part 5 — Chunk 3: run `staging_schema.sql` (create + empty the tables)

```python
with open(os.path.join(SCRIPT_DIR, "staging_schema.sql"), encoding="utf-8") as f:
    schema_sql = f.read()

conn = psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
                        user=DB_USER, password=DB_PASSWORD)
conn.autocommit = True
conn.cursor().execute(schema_sql)
conn.close()

print("[chunk 3] staging_schema.sql executed — tables created and emptied")
```

- Open `staging_schema.sql` (same folder as the script) and read ALL of it into one
  text string. SQL lives in `.sql` files — never written inside Python strings.
- `psycopg2.connect(...)` opens a real connection to PostgreSQL using the 5
  credentials from chunk 2.
- `conn.autocommit = True` means "save every command immediately" (otherwise
  Postgres waits for a `COMMIT`).
- `conn.cursor().execute(schema_sql)` — a **cursor** is the pipe you send SQL
  through. It sends the whole SQL file at once: creates the `stage` schema, the
  9 all-TEXT tables, and `TRUNCATE`s them (emptying them so the load is safe to
  re-run — on run 2+ the tables already exist via `CREATE TABLE IF NOT EXISTS`,
  so without TRUNCATE the append would duplicate every row).
- `conn.close()` — done with this connection, close it cleanly.

---

## Part 6 — Chunk 4: loading engine + which CSV goes to which table

```python
engine = create_engine(
    f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)

CSV_TO_TABLE = {
    "olist_customers_dataset.csv": "olist_customers_raw",
    ...
}
```

- An SQLAlchemy **engine** is a reusable database handle that pandas requires for
  `to_sql` and `read_sql`. It is given a URL: driver + user + password + host +
  port + database. TWO KEY FACTS:
  1. It does **not connect yet** — it connects lazily, when first used.
  2. It **pools** connections behind the scenes (opens/reuses/closes them itself).
- `CSV_TO_TABLE` is a **dictionary** (key → value pairs): each CSV filename →
  the exact table name. Written explicitly, to match `staging_schema.sql` 100%
  in every situation — nothing can break from filename guessing.

---

## Part 7 — Chunk 5: the main loop, step by step

The loop runs once per CSV — 9 passes total.

```python
for fname, table_name in CSV_TO_TABLE.items():
```
Each pass: `fname` = filename like `"olist_orders_dataset.csv"`, `table_name`
= `"olist_orders_raw"`.

### Step A — read the CSV into memory

```python
df = pd.read_csv(
    os.path.join(DATA_DIR, fname),
    dtype=str,
    encoding="utf-8-sig",
    keep_default_na=False,
    na_values=[""],
)
```

- `pd.read_csv` reads the whole CSV into a DataFrame — an in-memory table (like
  an Excel sheet in RAM).
- `dtype=str`: every value becomes TEXT. No "smart" converting — numbers stay
  `"29.99"`, dates stay `"2017-10-02 10:56:00"`. Staging keeps raw data.
- `encoding="utf-8-sig"`: normal UTF-8, plus it strips a BOM (an invisible
  character) from the start of the translation CSV.
- `keep_default_na=False` + `na_values=[""]`: pandas normally turns `"N/A"`,
  `"NA"`, `"None"`, `"nan"`, ... into NULL. That would silently change the data.
  These two options mean ONLY truly empty cells become NULL. All text is kept
  exactly as written.

### Step B — tidy the column headers (not the data!)

```python
df.columns = (
    df.columns.str.strip().str.lower()
    .str.replace(" ", "_", regex=False)
    .str.replace("-", "_", regex=False)
)
```

Runs left to right on each header name:
1. `.str.strip()` — trim spaces at start/end
2. `.str.lower()` — ALL CAPS → lowercase
3. spaces → `_`
4. dashes → `_`

Example: `"Order ID"` → `"order_id"`. This matches the column names in
`staging_schema.sql` so the insert can't fail with "column not found".
The data rows below the header are never touched.

### Step C — build the full table name

```python
db_table = f"stage.{table_name}"
```

An **f-string**: put `f` before the quotes, and anything inside `{...}` is
replaced with the variable's value. Here `"stage."` + `table_name` →
`"stage.olist_orders_raw"`. Just string-building — used by Step D (the count)
and Step E (the print). The insert itself doesn't use it.

### Step D — load: insert the rows into Postgres

```python
df.to_sql(table_name, engine, schema="stage",
          if_exists="append", index=False)
```

- pandas generates the `INSERT` statements (one per row), hands them to the
  engine → SQLAlchemy (Postgres rules + batching) → psycopg2 (the wire) →
  Postgres physically inserts the rows.
- `schema="stage"` — lands in `stage.<table>`
- `if_exists="append"` — the table already exists (chunk 3 created it), so rows
  are appended. Chunk 3's TRUNCATE emptied it, so re-running can't duplicate.
- `index=False` — don't insert pandas' hidden row-number column.

### Step E — verify: count what actually landed

```python
db_count = pd.read_sql(f"SELECT COUNT(*) AS n FROM {db_table}", engine)["n"][0]
```

Read left to right:
- `f"SELECT COUNT(*) AS n FROM {db_table}"` — the f-string builds the query,
  e.g. `"SELECT COUNT(*) AS n FROM stage.olist_orders_raw"` (`AS n` names the
  number column `n`).
- `pd.read_sql(..., engine)` — pandas sends it through the engine; the result
  comes back as a tiny one-row DataFrame.
- `["n"]` — grabs the column named `n` (a one-element list).
- `[0]` — takes the first (only) value out → a plain number.
So `db_count` = how many rows are **actually in the database now**.

### Step F — compare and report

```python
status = "PASS" if db_count == len(df) else "FAIL"
print(f"[chunk 5] {fname}: {len(df)} rows -> {db_table} — {status}")
```

- `len(df)` = how many rows the CSV had.
- If DB count == CSV count → `"PASS"`, otherwise → `"FAIL"`.
- (`x if condition else y` is a one-line if/else.)
- One PASS/FAIL line prints per table, e.g.:
  `[chunk 5] olist_orders_dataset.csv: 99441 rows -> stage.olist_orders_raw — PASS`
- The loop then returns to the top for the next CSV pair.

### The last 2 lines

```python
engine.dispose()          # close the engine's pooled connections — clean up
print("[done] staging load complete")
```

---

## Part 8 — Why SQLAlchemy at all? (the three-library story)

### psycopg2 = the driver

A **driver** is a translator whose only job is: connect to one specific database
and faithfully relay conversations. Python and Postgres don't speak a common
language — Postgres talks a raw network protocol (bytes), Python talks objects.
psycopg2 sits in between:

```
You (Python): "here's my SQL text, run it"
    └─ psycopg2: packs it into Postgres wire-format bytes, sends them over the network
Postgres:     runs it, sends results back as bytes
    └─ psycopg2: unpacks them back into Python objects and hands them to you
```

Mental model: psycopg2 = the direct phone line to Postgres. Anything you say on
it must already be SQL that *you* wrote. It cannot read CSVs and it does not
turn Python objects into rows for you. Perfect for chunk 3, where we simply
read a finished `.sql` file and execute it.

### pandas = the CSV specialist

pandas reads tabular files into in-memory grids (DataFrames) and knows nothing
about databases. Its authors made a deliberate design decision: pandas will NOT
hardcode support for every database driver. It only accepts one standard kind of
database handle — an **SQLAlchemy engine**. Hand it a raw psycopg2 connection
and `df.to_sql()` errors out. That is the single reason SQLAlchemy exists in
this script: **pandas will not talk to psycopg2 directly.**

### SQLAlchemy = the bridge

SQLAlchemy is a layer built *on top of* drivers like psycopg2. `create_engine`
produces an engine from a URL:

```python
engine = create_engine(
    f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)
```

URL anatomy:

```
postgresql+psycopg2 :// postgres : postgres @ db : 5432 / DatabaseProject
└──────── a ────────┘           b        c      d   e           f
```

- **a — dialect + driver**: "PostgreSQL SQL rules, with the psycopg2 driver
  underneath." Each database has its own SQL flavour ("**dialect**": quoting,
  types, bulk-insert style). SQLAlchemy's dialect layer knows Postgres' rules,
  which is what keeps pandas 100% database-agnostic.
- **b — user**, **c — password**, **d — host (the db container's name on
  Docker's internal network)**, **e — port**, **f — database name**.

### The full pipeline for one table

```
CSV file
  └─ pandas: pd.read_csv → DataFrame (all text, raw values)
       └─ df.to_sql(...): "store this, your problem now"
            └─ SQLAlchemy: builds Postgres-flavoured INSERTs, manages batching
                 └─ psycopg2: sends the INSERTs over the wire
                      └─ Postgres: rows land in stage.<table>
```

`pd.read_sql(...)` in Step E is the same pipeline in reverse (query sent down,
rows brought back).

### Division of labour

| Tool | One-line job | Where |
|---|---|---|
| **psycopg2** | The PostgreSQL **driver** — send SQL text, bring back results | chunk 3: executes `staging_schema.sql` |
| **pandas** | The **CSV specialist** — read CSVs; load rows only when handed an SQLAlchemy engine | chunk 5: read, insert, COUNT |
| **SQLAlchemy** | The **bridge** — the engine handle pandas accepts, wrapping psycopg2 underneath; adds pooling + the PostgreSQL dialect | chunk 4: `create_engine(...)` |

Note: SQLAlchemy could do far more than this (an ORM that generates all your SQL
from Python classes). This project deliberately uses only its minimal corner
(`create_engine`) — our SQL already lives in `.sql` files, by convention.

---

## Part 9 — Chunk map (1-minute summary)

| Chunk | Job |
|---|---|
| 1 | Ask where the script lives; build paths to the CSVs |
| 2 | Read DB credentials from `.env`; crash early if any are missing |
| 3 | Run `staging_schema.sql` via psycopg2: schema + 9 TEXT tables created/emptied |
| 4 | Make the engine pandas will load through; map each CSV → its table |
| 5 | For each CSV: read raw text → tidy headers → insert → COUNT-check → PASS/FAIL |

## Part 10 — What it does NOT do (on purpose)

- No type conversions (dates/numbers stay text)
- No cleaning, no dedup, no validation of values
- No surrogate keys / warehouse modelling

That all happens in later phases. Staging is a faithful copy of the CSVs.
