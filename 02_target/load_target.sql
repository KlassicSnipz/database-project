-- 02_target — load the star schema from stage.
-- Dims first (parents), then the fact. Nothing here modifies stage: it is
-- the source of truth and is only ever SELECTed.
--
-- Every cast that changes TEXT into a real type uses NULLIF(x, '') first so
-- an empty staging cell becomes NULL instead of a cast error.

-- 1. customer_dim — one row per customer_id (1:1 from the customers source).
INSERT INTO target.customer_dim
SELECT  nextval('target.customer_key_seq')      AS customer_key,
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state
FROM stage.olist_customers_raw;

-- 2. product_dim — one row per product_id, joined to the category translation
-- so it carries both names.
-- ~610 products have a NULL category and 2 Portuguese categories have no
-- English translation. Decision: LEFT JOIN keeps every product; "unknown
-- category" is represented as NULL in product_category_name /
-- product_category_name_english rather than a fake 'UNKNOWN' row — NULL is
-- queryable as "no known category" without polluting the dimension with data
-- that is not facts... and no product row is ever dropped (the fact joins on
-- product_id, which always exists).
INSERT INTO target.product_dim
SELECT  nextval('target.product_key_seq')       AS product_key,
        p.product_id,
        p.product_category_name,
        t.product_category_name_english
FROM stage.olist_products_raw p
LEFT JOIN stage.olist_category_translation_raw t
       ON t.product_category_name = p.product_category_name;

-- 3. seller_dim — one row per seller_id (1:1 from the sellers source).
INSERT INTO target.seller_dim
SELECT  nextval('target.seller_key_seq')        AS seller_key,
        seller_id,
        seller_zip_code_prefix,
        seller_city,
        seller_state
FROM stage.olist_sellers_raw;

-- 4. sales_transactions_fact — grain: one row per order item.
-- Every fact row must find all three dimension keys. These are INNER JOINs on
-- purpose: if any lookup missed (bad id, missing dim row, dup business id),
-- the statement either errors on the FK or yields fewer fact rows than
-- staging has items — either way validate + the runner fail loudly instead of
-- quietly inserting a NULL/unmatched key.
INSERT INTO target.sales_transactions_fact
SELECT  nextval('target.sales_trans_key_seq')   AS sales_trans_key,
        o.order_id,
        i.order_item_id,
        c.customer_key,
        p.product_key,
        s.seller_key,
        o.order_status,
        o.order_purchase_timestamp::TIMESTAMP,
        o.order_approved_at::TIMESTAMP,
        o.order_delivered_carrier_date::TIMESTAMP,
        o.order_delivered_customer_date::TIMESTAMP,
        o.order_estimated_delivery_date::TIMESTAMP,
        i.price::NUMERIC(10, 2),
        i.freight_value::NUMERIC(10, 2)
FROM stage.olist_order_items_raw i
JOIN stage.olist_orders_raw            o ON o.order_id = i.order_id
JOIN target.customer_dim               c ON c.customer_id   = o.customer_id
JOIN target.product_dim                p ON p.product_id    = i.product_id
JOIN target.seller_dim                 s ON s.seller_id     = i.seller_id;
