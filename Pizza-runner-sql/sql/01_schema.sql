-- ============================================================
-- Pizza Runner - Schema (raw, as provided by the case study)
-- File: 01_schema.sql
--
-- IMPORTANT: Several columns here are deliberately typed as VARCHAR/TEXT
-- even though they represent numbers (e.g. distance, duration) or
-- comma-separated ID lists (e.g. exclusions, extras, toppings). This is
-- intentional and matches the original case study's design: the dataset
-- is messy on purpose (blank strings, the literal text "null", mixed
-- units like "20km" vs "20" vs "23.4 km") and one of the core skills
-- this case study tests is cleaning that data BEFORE analysis, not
-- assuming a clean schema from the start.
--
-- The cleaned-up, properly-typed version used for analysis is built in
-- 02_clean_data.sql via temp tables / views, exactly as the original
-- case study recommends.
-- ============================================================

DROP SCHEMA IF EXISTS pizza_runner CASCADE;
CREATE SCHEMA pizza_runner;
SET search_path TO pizza_runner;

CREATE TABLE runners (
    runner_id INTEGER,
    registration_date DATE
);

CREATE TABLE customer_orders (
    order_id INTEGER,
    customer_id INTEGER,
    pizza_id INTEGER,
    exclusions VARCHAR(4),
    extras VARCHAR(4),
    order_time TIMESTAMP
);

CREATE TABLE runner_orders (
    order_id INTEGER,
    runner_id INTEGER,
    pickup_time VARCHAR(19),
    distance VARCHAR(7),
    duration VARCHAR(10),
    cancellation VARCHAR(23)
);

CREATE TABLE pizza_names (
    pizza_id INTEGER,
    pizza_name TEXT
);

CREATE TABLE pizza_recipes (
    pizza_id INTEGER,
    toppings TEXT
);

CREATE TABLE pizza_toppings (
    topping_id INTEGER,
    topping_name TEXT
);
