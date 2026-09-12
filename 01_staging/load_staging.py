import os

import pandas as pd
import psycopg2
from sqlalchemy import create_engine
from dotenv import load_dotenv

# Chunk 1 — find where the files are, relative to this script.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
DATA_DIR = os.path.join(ROOT_DIR, "Datasets")

# Chunk 2 — read DB credentials from .env (never hardcode passwords).
load_dotenv(os.path.join(ROOT_DIR, ".env"))

DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")

if not all([DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD]):
    raise RuntimeError("Missing DB_* variables — check .env in the project root.")

print(f"[chunk 2] target: {DB_USER}@{DB_HOST}:{DB_PORT}/{DB_NAME}")

# Chunk 3 — run staging_schema.sql: creates the `stage` schema,
with open(os.path.join(SCRIPT_DIR, "staging_schema.sql"), encoding="utf-8") as f:
    schema_sql = f.read()

conn = psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
                        user=DB_USER, password=DB_PASSWORD)
conn.autocommit = True
conn.cursor().execute(schema_sql)
conn.close()

print("[chunk 3] staging_schema.sql executed — tables created and emptied")

# Chunk 4 — one SQLAlchemy engine for the loading, and an explicit
engine = create_engine(
    f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)

CSV_TO_TABLE = {
    "olist_customers_dataset.csv": "olist_customers_raw",
    "olist_geolocation_dataset.csv": "olist_geolocation_raw",
    "olist_orders_dataset.csv": "olist_orders_raw",
    "olist_order_items_dataset.csv": "olist_order_items_raw",
    "olist_order_payments_dataset.csv": "olist_order_payments_raw",
    "olist_order_reviews_dataset.csv": "olist_order_reviews_raw",
    "olist_products_dataset.csv": "olist_products_raw",
    "olist_sellers_dataset.csv": "olist_sellers_raw",
    "product_category_name_translation.csv": "olist_category_translation_raw",
}

# Chunk 5 — for each CSV: read it as raw text, tidy the column names,
for fname, table_name in CSV_TO_TABLE.items():
    df = pd.read_csv(
        os.path.join(DATA_DIR, fname),
        dtype=str,
        encoding="utf-8-sig",
        keep_default_na=False,
        na_values=[""],
    )

    # lowercase snake_case column names, e.g. "Order ID" -> "order_id"
    df.columns = (
        df.columns.str.strip().str.lower()
        .str.replace(" ", "_", regex=False)
        .str.replace("-", "_", regex=False)
    )

    db_table = f"stage.{table_name}"

    df.to_sql(table_name, engine, schema="stage",
              if_exists="append", index=False)

    db_count = pd.read_sql(f"SELECT COUNT(*) AS n FROM {db_table}", engine)["n"][0]
    status = "PASS" if db_count == len(df) else "FAIL"

    print(f"[chunk 5] {fname}: {len(df)} rows -> {db_table} — {status}")

engine.dispose()
print("[done] staging load complete")
