-- 02_target — validation (run inside the loading transaction, before COMMIT).
-- One readable result set: reconcile counts vs stage, check fact dimension
-- keys, reconcile the sales total. The runner fails loudly if any of these
-- are wrong, so stage and target can never silently drift.

SELECT 'row_count' AS check_name, 'customer_dim' AS entity,
       (SELECT COUNT(*) FROM stage.olist_customers_raw) AS stage_rows,
       (SELECT COUNT(*) FROM target.customer_dim) AS target_rows,
       'one row per customer_id — 1:1' AS note

UNION ALL
SELECT 'row_count', 'product_dim',
       (SELECT COUNT(*) FROM stage.olist_products_raw),
       (SELECT COUNT(*) FROM target.product_dim),
       'one row per product_id — LEFT JOIN to translation keeps every product'

UNION ALL
SELECT 'row_count', 'seller_dim',
       (SELECT COUNT(*) FROM stage.olist_sellers_raw),
       (SELECT COUNT(*) FROM target.seller_dim),
       'one row per seller_id — 1:1'

UNION ALL
SELECT 'row_count', 'sales_transactions_fact',
       (SELECT COUNT(*) FROM stage.olist_order_items_raw),
       (SELECT COUNT(*) FROM target.sales_transactions_fact),
       'grain: one row per order item; counts must be equal or some lookup failed'

UNION ALL
SELECT 'fact_key_check', 'null_or_missing_dim_keys',
       NULL,
       (SELECT COUNT(*) FROM target.sales_transactions_fact
        WHERE customer_key IS NULL OR product_key IS NULL OR seller_key IS NULL),
       'must be 0 — INNER JOIN dim lookup missed if > 0'

UNION ALL
SELECT 'fact_key_check', 'unmatched_business_ids',
       NULL,
       (SELECT COUNT(*) FROM target.sales_transactions_fact f
        LEFT JOIN target.customer_dim c USING (customer_key)
        LEFT JOIN target.product_dim p USING (product_key)
        LEFT JOIN target.seller_dim s USING (seller_key)
        WHERE c.customer_key IS NULL OR p.product_key IS NULL OR s.seller_key IS NULL),
       'must be 0 — FKs make this impossible, counted as a double check'

UNION ALL
SELECT 'sum_check', 'SUM(price): fact vs stage',
       (SELECT SUM(NULLIF(price, '')::NUMERIC) FROM stage.olist_order_items_raw),
       (SELECT SUM(price) FROM target.sales_transactions_fact),
       'the fact total must match the staging total exactly'

ORDER BY check_name, entity;
