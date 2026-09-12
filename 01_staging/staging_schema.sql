CREATE SCHEMA IF NOT EXISTS stage;

CREATE TABLE IF NOT EXISTS stage.olist_customers_raw (
    customer_id TEXT,
    customer_unique_id TEXT,
    customer_zip_code_prefix TEXT,
    customer_city TEXT,
    customer_state TEXT
);

CREATE TABLE IF NOT EXISTS stage.olist_geolocation_raw (
    geolocation_zip_code_prefix TEXT,
    geolocation_lat TEXT,
    geolocation_lng TEXT,
    geolocation_city TEXT,
    geolocation_state TEXT
);

CREATE TABLE IF NOT EXISTS stage.olist_orders_raw (
    order_id TEXT,
    customer_id TEXT,
    order_status TEXT,
    order_purchase_timestamp TEXT,
    order_approved_at TEXT,
    order_delivered_carrier_date TEXT,
    order_delivered_customer_date TEXT,
    order_estimated_delivery_date TEXT
);

CREATE TABLE IF NOT EXISTS stage.olist_order_items_raw (
    order_id TEXT,
    order_item_id TEXT,
    product_id TEXT,
    seller_id TEXT,
    shipping_limit_date TEXT,
    price TEXT,
    freight_value TEXT
);

CREATE TABLE IF NOT EXISTS stage.olist_order_payments_raw (
    order_id TEXT,
    payment_sequential TEXT,
    payment_type TEXT,
    payment_installments TEXT,
    payment_value TEXT
);

CREATE TABLE IF NOT EXISTS stage.olist_order_reviews_raw (
    review_id TEXT,
    order_id TEXT,
    review_score TEXT,
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date TEXT,
    review_answer_timestamp TEXT
);

CREATE TABLE IF NOT EXISTS stage.olist_products_raw (
    product_id TEXT,
    product_category_name TEXT,
    product_name_lenght TEXT,
    product_description_lenght TEXT,
    product_photos_qty TEXT,
    product_weight_g TEXT,
    product_length_cm TEXT,
    product_height_cm TEXT,
    product_width_cm TEXT
);

CREATE TABLE IF NOT EXISTS stage.olist_sellers_raw (
    seller_id TEXT,
    seller_zip_code_prefix TEXT,
    seller_city TEXT,
    seller_state TEXT
);

CREATE TABLE IF NOT EXISTS stage.olist_category_translation_raw (
    product_category_name TEXT,
    product_category_name_english TEXT
);

-- Reset raw tables before loading, so the loader is safe to re-run
-- (the loader appends, so tables must start empty each run).
TRUNCATE TABLE stage.olist_customers_raw;
TRUNCATE TABLE stage.olist_geolocation_raw;
TRUNCATE TABLE stage.olist_orders_raw;
TRUNCATE TABLE stage.olist_order_items_raw;
TRUNCATE TABLE stage.olist_order_payments_raw;
TRUNCATE TABLE stage.olist_order_reviews_raw;
TRUNCATE TABLE stage.olist_products_raw;
TRUNCATE TABLE stage.olist_sellers_raw;
TRUNCATE TABLE stage.olist_category_translation_raw;
