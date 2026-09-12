-- 02_target — star schema (assignment's Country/Customer/Product/Sales pattern)
-- built on top of the staging layer (stage is the source; it is never modified).
--
-- Conventions follow 01_staging: SQL lives in .sql files (executed by the
-- Python runner), everything is lower-case snake_case, and the whole schema
-- is dropped and rebuilt from scratch so re-running is always clean.
--
-- Surrogate keys follow the lecture:
--   Oracle:    seq.NEXTVAL / SELECT seq.NEXTVAL FROM dual
--   Postgres:  nextval('seq')  — no dual table needed (Postgres has no dual),
--              IDs and zip prefixes stay TEXT (zip prefixes keep meaningful
--              leading zeros); counts become INTEGER; timestamps TIMESTAMP;
--              price/freight NUMERIC(10,2).
--
-- Out of scope for this chapter (deliberately NOT built):
--   payments, reviews, geolocation, any date dimension.

DROP SCHEMA IF EXISTS target CASCADE;
CREATE SCHEMA target;

-- ---------------------------------------------------------------------------
-- Sequences — one per dimension plus one for the fact
-- (assignment style: CREATE SEQUENCE ... START 1; no IDENTITY, no serial)
-- ---------------------------------------------------------------------------

CREATE SEQUENCE target.customer_key_seq      START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE target.product_key_seq       START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE target.seller_key_seq        START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE target.sales_trans_key_seq   START WITH 1 INCREMENT BY 1;

-- ---------------------------------------------------------------------------
-- Dimension tables — surrogate key = PK, business id kept UNIQUE FK-able
-- ---------------------------------------------------------------------------

CREATE TABLE target.customer_dim (
    customer_key                    BIGINT PRIMARY KEY,
    customer_id                     TEXT UNIQUE NOT NULL,
    customer_unique_id              TEXT,
    customer_zip_code_prefix        TEXT,
    customer_city                   TEXT,
    customer_state                  TEXT
);

-- "Unknown category" is represented as NULLs in both name columns
-- (see load_target.sql for the reasoning).
CREATE TABLE target.product_dim (
    product_key                     BIGINT PRIMARY KEY,
    product_id                      TEXT UNIQUE NOT NULL,
    product_category_name           TEXT,
    product_category_name_english   TEXT
);

CREATE TABLE target.seller_dim (
    seller_key                      BIGINT PRIMARY KEY,
    seller_id                       TEXT UNIQUE NOT NULL,
    seller_zip_code_prefix          TEXT,
    seller_city                     TEXT,
    seller_state                    TEXT
);

-- ---------------------------------------------------------------------------
-- Fact table — grain = one row per order item (order_id + order_item_id)
-- ---------------------------------------------------------------------------

CREATE TABLE target.sales_transactions_fact (
    sales_trans_key                 BIGINT PRIMARY KEY,

    -- degenerate dimension keys straight from source
    order_id                        TEXT NOT NULL,
    order_item_id                   TEXT NOT NULL,

    -- dimension foreign keys (surrogate keys)
    customer_key                    BIGINT REFERENCES target.customer_dim (customer_key),
    product_key                     BIGINT REFERENCES target.product_dim (product_key),
    seller_key                      BIGINT REFERENCES target.seller_dim (seller_key),

    -- order facts carried over via the order_id
    order_status                    TEXT,
    order_purchase_timestamp        TIMESTAMP,
    order_approved_at               TIMESTAMP,
    order_delivered_carrier_date    TIMESTAMP,
    order_delivered_customer_date   TIMESTAMP,
    order_estimated_delivery_date   TIMESTAMP,

    -- item facts
    price                           NUMERIC(10, 2),
    freight_value                   NUMERIC(10, 2),

    UNIQUE (order_id, order_item_id)                -- the grain is exactly this pair
);
