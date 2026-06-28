-- ============================================================
-- Pizza Runner - Data Cleaning Layer
-- File: 03_clean_data.sql
--
-- Builds clean VIEWs on top of the raw tables in 01_schema.sql /
-- 02_seed_data.sql. The raw tables are left untouched so the
-- "before" state is always inspectable - all cleaning logic lives
-- here, where it's easy to review.
--
-- Issues being fixed:
--   customer_orders.exclusions / extras:
--     - both '' (empty string) and actual NULL are used to mean
--       "no exclusion / no extra" -> normalized to a NULL integer array
--     - comma-separated topping_id lists ('2, 6') -> INTEGER[]
--   runner_orders.pickup_time:
--     - literal string 'null' -> normalized to a real NULL, cast to TIMESTAMP
--     - NOTE: orders 7, 8 and 10 have a pickup_time in 2020 even though
--       their order_time is in 2021. This is a known data issue flagged
--       by the case study itself, not a typo introduced here - it's left
--       as-is so it's visible, and called out again in the README.
--   runner_orders.distance:
--     - mixed formats ('20km', '13.4km', '23.4', '23.4 km') -> NUMERIC,
--       stripped of all non-numeric characters except the decimal point
--   runner_orders.duration:
--     - mixed formats ('32 minutes', '20 mins', '25mins', '15 minute',
--       '40') -> INTEGER minutes, stripped of all non-digit characters
--   runner_orders.cancellation:
--     - '', 'null', 'NaN' all used to mean "not cancelled" -> NULL
-- ============================================================

SET search_path TO pizza_runner;

DROP VIEW IF EXISTS successful_deliveries;
DROP VIEW IF EXISTS runner_orders_clean;
DROP VIEW IF EXISTS customer_orders_clean;

CREATE OR REPLACE VIEW customer_orders_clean AS
SELECT
    ROW_NUMBER() OVER (ORDER BY order_id) AS row_id,
    order_id,
    customer_id,
    pizza_id,
    CASE WHEN exclusions IS NULL OR TRIM(exclusions) = '' THEN NULL
         ELSE STRING_TO_ARRAY(REPLACE(exclusions, ' ', ''), ',')::INTEGER[]
    END AS exclusions,
    CASE WHEN extras IS NULL OR TRIM(extras) = '' THEN NULL
         ELSE STRING_TO_ARRAY(REPLACE(extras, ' ', ''), ',')::INTEGER[]
    END AS extras,
    order_time
FROM customer_orders;


CREATE OR REPLACE VIEW runner_orders_clean AS
SELECT
    order_id,
    runner_id,
    -- KNOWN DATA ISSUE (flagged explicitly by the case study): orders 7, 8,
    -- and 10 have a pickup_time stamped in 2020, a full year before their
    -- corresponding order_time in customer_orders (which is in 2021). A
    -- pickup cannot happen before the order was placed, so this is treated
    -- as a single-field data entry error (year digit wrong) and corrected
    -- by adding 1 year back, rather than dropping these rows or leaving
    -- nonsensical negative pickup-time calculations in every downstream
    -- query. This correction is intentionally explicit and isolated here
    -- so it's easy to spot, question, or revert.
    CASE WHEN pickup_time = 'null' THEN NULL
         WHEN order_id IN (7, 8, 10) THEN pickup_time::TIMESTAMP + INTERVAL '1 year'
         ELSE pickup_time::TIMESTAMP
    END AS pickup_time,
    CASE WHEN distance = 'null' OR distance IS NULL THEN NULL
         ELSE REGEXP_REPLACE(distance, '[^0-9.]', '', 'g')::NUMERIC
    END AS distance_km,
    CASE WHEN duration = 'null' OR duration IS NULL THEN NULL
         ELSE REGEXP_REPLACE(duration, '[^0-9]', '', 'g')::INTEGER
    END AS duration_minutes,
    CASE WHEN cancellation IS NULL OR TRIM(cancellation) = '' OR cancellation IN ('null', 'NaN') THEN NULL
         ELSE cancellation
    END AS cancellation
FROM runner_orders;


-- Convenience view: only orders that were actually delivered
-- (i.e. cancellation is NULL after cleaning)
CREATE OR REPLACE VIEW successful_deliveries AS
SELECT *
FROM runner_orders_clean
WHERE cancellation IS NULL;
