-- ============================================================
-- Pizza Runner - Case Study Analysis
-- File: 04_analysis_queries.sql
--
-- All queries here run against the cleaned views defined in
-- 03_clean_data.sql (customer_orders_clean, runner_orders_clean,
-- successful_deliveries) - never the raw tables directly.
--
-- Every query in this file was written and verified against a live
-- PostgreSQL 16 instance loaded with Danny Ma's original Pizza Runner
-- dataset (8weeksqlchallenge.com/case-study-2), kept unmodified so the
-- data-cleaning step itself stays meaningful.
-- ============================================================

SET search_path TO pizza_runner;


-- ============================================================
-- SECTION A: PIZZA METRICS
-- ============================================================

-- A1. How many pizzas were ordered?
SELECT COUNT(*) AS pizzas_ordered
FROM customer_orders_clean;


-- A2. How many unique customer orders were made?
SELECT COUNT(DISTINCT order_id) AS unique_orders
FROM customer_orders_clean;


-- A3. How many successful orders were delivered by each runner?
SELECT runner_id, COUNT(*) AS successful_orders
FROM successful_deliveries
GROUP BY runner_id
ORDER BY runner_id;


-- A4. How many of each type of pizza was delivered?
SELECT pn.pizza_name, COUNT(*) AS delivered_count
FROM customer_orders_clean co
JOIN successful_deliveries sd ON sd.order_id = co.order_id
JOIN pizza_names pn ON pn.pizza_id = co.pizza_id
GROUP BY pn.pizza_name;


-- A5. How many Vegetarian and Meat Lovers were ordered by each customer?
SELECT co.customer_id, pn.pizza_name, COUNT(*) AS quantity
FROM customer_orders_clean co
JOIN pizza_names pn ON pn.pizza_id = co.pizza_id
GROUP BY co.customer_id, pn.pizza_name
ORDER BY co.customer_id;


-- A6. What was the maximum number of pizzas delivered in a single order?
SELECT co.order_id, COUNT(*) AS pizza_count
FROM customer_orders_clean co
JOIN successful_deliveries sd ON sd.order_id = co.order_id
GROUP BY co.order_id
ORDER BY pizza_count DESC
LIMIT 1;


-- A7. For each customer, how many delivered pizzas had at least 1 change
-- (an exclusion or extra), and how many had no changes?
SELECT
    co.customer_id,
    SUM(CASE WHEN co.exclusions IS NOT NULL OR co.extras IS NOT NULL THEN 1 ELSE 0 END) AS has_changes,
    SUM(CASE WHEN co.exclusions IS NULL AND co.extras IS NULL THEN 1 ELSE 0 END) AS no_changes
FROM customer_orders_clean co
JOIN successful_deliveries sd ON sd.order_id = co.order_id
GROUP BY co.customer_id
ORDER BY co.customer_id;


-- A8. How many pizzas were delivered that had both exclusions AND extras?
SELECT COUNT(*) AS pizzas_with_both
FROM customer_orders_clean co
JOIN successful_deliveries sd ON sd.order_id = co.order_id
WHERE co.exclusions IS NOT NULL AND co.extras IS NOT NULL;


-- A9. What was the total volume of pizzas ordered for each hour of the day?
SELECT
    EXTRACT(HOUR FROM order_time) AS hour_of_day,
    COUNT(*) AS pizza_count
FROM customer_orders_clean
GROUP BY hour_of_day
ORDER BY hour_of_day;


-- A10. What was the volume of orders for each day of the week?
SELECT
    TO_CHAR(order_time, 'Day') AS day_of_week,
    COUNT(DISTINCT order_id) AS order_count
FROM customer_orders_clean
GROUP BY TO_CHAR(order_time, 'Day'), EXTRACT(ISODOW FROM order_time)
ORDER BY EXTRACT(ISODOW FROM order_time);


-- ============================================================
-- SECTION B: RUNNER AND CUSTOMER EXPERIENCE
-- ============================================================

-- B1. How many runners signed up for each 1-week period (weeks start Friday,
-- matching 2021-01-01)?
SELECT
    DATE_TRUNC('week', registration_date)::date + 1 AS week_start,
    COUNT(*) AS runners_signed_up
FROM runners
GROUP BY 1
ORDER BY 1;


-- B2. What was the average time in minutes for each runner to arrive at HQ
-- to pick up the order? (joined at the order level, not the pizza-line-item
-- level, to avoid multi-pizza orders skewing the average)
SELECT
    rc.runner_id,
    ROUND(AVG(EXTRACT(EPOCH FROM (rc.pickup_time - co.order_time)) / 60)::numeric, 1) AS avg_pickup_minutes
FROM successful_deliveries rc
JOIN (SELECT DISTINCT order_id, order_time FROM customer_orders_clean) co
    ON co.order_id = rc.order_id
GROUP BY rc.runner_id
ORDER BY rc.runner_id;


-- B3. Is there a relationship between the number of pizzas in an order and
-- how long it takes to prepare (order_time -> pickup_time)?
WITH order_pizza_count AS (
    SELECT order_id, order_time, COUNT(*) AS pizza_count
    FROM customer_orders_clean
    GROUP BY order_id, order_time
)
SELECT
    opc.pizza_count,
    ROUND(AVG(EXTRACT(EPOCH FROM (sd.pickup_time - opc.order_time)) / 60)::numeric, 1) AS avg_prep_minutes
FROM successful_deliveries sd
JOIN order_pizza_count opc ON opc.order_id = sd.order_id
GROUP BY opc.pizza_count
ORDER BY opc.pizza_count;
-- Result: prep time increases steadily with pizza count (1 -> ~12 min,
-- 2 -> ~18 min, 3 -> ~29 min) - a clear, near-linear relationship.


-- B4. What was the average distance travelled for each customer?
SELECT
    co.customer_id,
    ROUND(AVG(sd.distance_km)::numeric, 1) AS avg_distance_km
FROM successful_deliveries sd
JOIN (SELECT DISTINCT order_id, customer_id FROM customer_orders_clean) co
    ON co.order_id = sd.order_id
GROUP BY co.customer_id
ORDER BY co.customer_id;


-- B5. What was the difference between the longest and shortest delivery
-- times for all orders?
SELECT MAX(duration_minutes) - MIN(duration_minutes) AS duration_range_minutes
FROM successful_deliveries;


-- B6. What was the average speed for each runner for each delivery, and is
-- there a trend?
SELECT
    runner_id,
    order_id,
    distance_km,
    duration_minutes,
    ROUND((distance_km / (duration_minutes / 60.0))::numeric, 1) AS speed_kmh
FROM successful_deliveries
ORDER BY runner_id, order_id;
-- Result: runner 2's speed varies widely across deliveries (35.1 -> 60.0 ->
-- 93.6 km/h), which is unrealistic for normal driving and likely reflects
-- either inconsistent/unreliable duration data or genuinely erratic
-- driving - worth flagging operationally rather than averaging away.


-- B7. What is the successful delivery percentage for each runner?
SELECT
    runner_id,
    COUNT(*) AS total_assigned,
    SUM(CASE WHEN cancellation IS NULL THEN 1 ELSE 0 END) AS successful,
    ROUND(100.0 * SUM(CASE WHEN cancellation IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS success_pct
FROM runner_orders_clean
GROUP BY runner_id
ORDER BY runner_id;


-- ============================================================
-- SECTION C: INGREDIENT OPTIMISATION
-- ============================================================

-- C1. What are the standard ingredients for each pizza?
SELECT pn.pizza_name, pt.topping_name
FROM pizza_recipes pr
JOIN pizza_names pn ON pn.pizza_id = pr.pizza_id
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(pr.toppings, ', ')::INTEGER[]) AS u(topping_id)
JOIN pizza_toppings pt ON pt.topping_id = u.topping_id
ORDER BY pn.pizza_name, pt.topping_name;


-- C2. What was the most commonly added extra?
SELECT pt.topping_name, COUNT(*) AS times_added
FROM customer_orders_clean co
CROSS JOIN LATERAL UNNEST(co.extras) AS u(topping_id)
JOIN pizza_toppings pt ON pt.topping_id = u.topping_id
WHERE co.extras IS NOT NULL
GROUP BY pt.topping_name
ORDER BY times_added DESC;


-- C3. What was the most common exclusion?
SELECT pt.topping_name, COUNT(*) AS times_excluded
FROM customer_orders_clean co
CROSS JOIN LATERAL UNNEST(co.exclusions) AS u(topping_id)
JOIN pizza_toppings pt ON pt.topping_id = u.topping_id
WHERE co.exclusions IS NOT NULL
GROUP BY pt.topping_name
ORDER BY times_excluded DESC;


-- C4. Generate an order item label for each row in customer_orders, e.g.
-- "Meat Lovers - Exclude Cheese, Bacon - Extra Mushroom, Peppers"
-- Uses customer_orders_clean.row_id (a synthetic row identifier) to
-- correctly distinguish duplicate line items within the same order -
-- multiple identical pizzas in one order have no other unique key.
WITH excl_names AS (
    SELECT co.row_id, STRING_AGG(pt.topping_name, ', ' ORDER BY pt.topping_name) AS excl_list
    FROM customer_orders_clean co
    CROSS JOIN LATERAL UNNEST(co.exclusions) AS u(topping_id)
    JOIN pizza_toppings pt ON pt.topping_id = u.topping_id
    GROUP BY co.row_id
),
extra_names AS (
    SELECT co.row_id, STRING_AGG(pt.topping_name, ', ' ORDER BY pt.topping_name) AS extra_list
    FROM customer_orders_clean co
    CROSS JOIN LATERAL UNNEST(co.extras) AS u(topping_id)
    JOIN pizza_toppings pt ON pt.topping_id = u.topping_id
    GROUP BY co.row_id
)
SELECT
    co.order_id,
    pn.pizza_name
        || COALESCE(' - Exclude ' || en.excl_list, '')
        || COALESCE(' - Extra ' || ex.extra_list, '') AS order_item_label
FROM customer_orders_clean co
JOIN pizza_names pn      ON pn.pizza_id = co.pizza_id
LEFT JOIN excl_names en  ON en.row_id = co.row_id
LEFT JOIN extra_names ex ON ex.row_id = co.row_id
ORDER BY co.row_id;


-- C5. Generate an alphabetically ordered, comma-separated ingredient list
-- for each pizza order, with a "2x" prefix for any ingredient that appears
-- twice (i.e. it's a base topping that was ALSO added as an extra).
WITH base_toppings AS (
    SELECT co.row_id, co.order_id, co.pizza_id, u.topping_id
    FROM customer_orders_clean co
    CROSS JOIN LATERAL UNNEST(
        STRING_TO_ARRAY((SELECT toppings FROM pizza_recipes pr WHERE pr.pizza_id = co.pizza_id), ', ')::INTEGER[]
    ) AS u(topping_id)
),
toppings_after_exclusions AS (
    SELECT bt.row_id, bt.order_id, bt.pizza_id, bt.topping_id
    FROM base_toppings bt
    JOIN customer_orders_clean co ON co.row_id = bt.row_id
    WHERE co.exclusions IS NULL OR NOT (bt.topping_id = ANY(co.exclusions))
),
toppings_with_extras AS (
    SELECT row_id, order_id, pizza_id, topping_id FROM toppings_after_exclusions
    UNION ALL
    SELECT co.row_id, co.order_id, co.pizza_id, u.topping_id
    FROM customer_orders_clean co
    CROSS JOIN LATERAL UNNEST(co.extras) AS u(topping_id)
    WHERE co.extras IS NOT NULL
),
topping_counts AS (
    SELECT row_id, order_id, pizza_id, topping_id, COUNT(*) AS qty
    FROM toppings_with_extras
    GROUP BY row_id, order_id, pizza_id, topping_id
)
SELECT
    tc.order_id,
    pn.pizza_name || ': ' || STRING_AGG(
        CASE WHEN tc.qty > 1 THEN tc.qty || 'x' || pt.topping_name ELSE pt.topping_name END,
        ', ' ORDER BY pt.topping_name
    ) AS ingredient_list
FROM topping_counts tc
JOIN pizza_names pn    ON pn.pizza_id = tc.pizza_id
JOIN pizza_toppings pt ON pt.topping_id = tc.topping_id
GROUP BY tc.row_id, tc.order_id, pn.pizza_name
ORDER BY tc.row_id;


-- C6. What is the total quantity of each ingredient used across all
-- DELIVERED pizzas, sorted by most frequent first?
WITH base_toppings AS (
    SELECT co.row_id, co.order_id, co.pizza_id, u.topping_id
    FROM customer_orders_clean co
    CROSS JOIN LATERAL UNNEST(
        STRING_TO_ARRAY((SELECT toppings FROM pizza_recipes pr WHERE pr.pizza_id = co.pizza_id), ', ')::INTEGER[]
    ) AS u(topping_id)
),
toppings_after_exclusions AS (
    SELECT bt.row_id, bt.order_id, bt.pizza_id, bt.topping_id
    FROM base_toppings bt
    JOIN customer_orders_clean co ON co.row_id = bt.row_id
    WHERE co.exclusions IS NULL OR NOT (bt.topping_id = ANY(co.exclusions))
),
toppings_with_extras AS (
    SELECT row_id, order_id, pizza_id, topping_id FROM toppings_after_exclusions
    UNION ALL
    SELECT co.row_id, co.order_id, co.pizza_id, u.topping_id
    FROM customer_orders_clean co
    CROSS JOIN LATERAL UNNEST(co.extras) AS u(topping_id)
    WHERE co.extras IS NOT NULL
)
SELECT pt.topping_name, COUNT(*) AS total_quantity
FROM toppings_with_extras twe
JOIN successful_deliveries sd ON sd.order_id = twe.order_id
JOIN pizza_toppings pt        ON pt.topping_id = twe.topping_id
GROUP BY pt.topping_name
ORDER BY total_quantity DESC;


-- ============================================================
-- SECTION D: PRICING AND RATINGS
-- ============================================================

-- D1. Meat Lovers = $12, Vegetarian = $10, no charge for changes - how much
-- has Pizza Runner made, ignoring delivery fees?
SELECT
    SUM(CASE WHEN pn.pizza_name = 'Meat Lovers' THEN 12 ELSE 10 END) AS total_revenue
FROM customer_orders_clean co
JOIN successful_deliveries sd ON sd.order_id = co.order_id
JOIN pizza_names pn ON pn.pizza_id = co.pizza_id;


-- D2. Same as D1, but with an additional $1 charge per extra topping added.
WITH base_price AS (
    SELECT co.row_id, CASE WHEN pn.pizza_name = 'Meat Lovers' THEN 12 ELSE 10 END AS price
    FROM customer_orders_clean co
    JOIN successful_deliveries sd ON sd.order_id = co.order_id
    JOIN pizza_names pn ON pn.pizza_id = co.pizza_id
),
extra_charges AS (
    SELECT co.row_id, COUNT(*) AS num_extras
    FROM customer_orders_clean co
    JOIN successful_deliveries sd ON sd.order_id = co.order_id
    CROSS JOIN LATERAL UNNEST(co.extras) AS u(topping_id)
    WHERE co.extras IS NOT NULL
    GROUP BY co.row_id
)
SELECT SUM(bp.price + COALESCE(ec.num_extras, 0)) AS total_revenue
FROM base_price bp
LEFT JOIN extra_charges ec ON ec.row_id = bp.row_id;


-- D3. Ratings table design + sample data.
-- One rating per successfully delivered order. order_id is NOT a foreign
-- key to customer_orders (which has duplicate order_ids - one row per
-- pizza line item, not per order) or to runner_orders (which has no
-- declared primary key in the original raw schema). It's left as a plain
-- UNIQUE column instead, which is the honest constraint given the
-- upstream schema, with the relationship enforced at the application/
-- query level.
DROP TABLE IF EXISTS runner_ratings;
CREATE TABLE runner_ratings (
    rating_id  SERIAL PRIMARY KEY,
    order_id   INTEGER NOT NULL UNIQUE,
    rating     SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    rated_at   TIMESTAMP NOT NULL
);

INSERT INTO runner_ratings (order_id, rating, rated_at) VALUES
    (1,  5, '2021-01-01 19:00:00'),
    (2,  4, '2021-01-01 19:45:00'),
    (3,  3, '2021-01-03 00:50:00'),
    (4,  5, '2021-01-04 14:30:00'),
    (5,  4, '2021-01-08 21:45:00'),
    (7,  2, '2021-01-08 22:00:00'),
    (8,  5, '2021-01-10 00:50:00'),
    (10, 4, '2021-01-11 19:20:00');


-- D4. Join everything together for successful deliveries: customer_id,
-- order_id, runner_id, rating, order_time, pickup_time, time between order
-- and pickup, delivery duration, average speed, and total pizza count.
WITH pizza_count AS (
    SELECT order_id, COUNT(*) AS total_pizzas
    FROM customer_orders_clean
    GROUP BY order_id
)
SELECT
    co.customer_id,
    sd.order_id,
    sd.runner_id,
    rr.rating,
    co.order_time,
    sd.pickup_time,
    ROUND(EXTRACT(EPOCH FROM (sd.pickup_time - co.order_time)) / 60, 1) AS order_to_pickup_minutes,
    sd.duration_minutes AS delivery_duration_minutes,
    ROUND((sd.distance_km / (sd.duration_minutes / 60.0))::numeric, 1) AS avg_speed_kmh,
    pc.total_pizzas
FROM successful_deliveries sd
JOIN (SELECT DISTINCT order_id, customer_id, order_time FROM customer_orders_clean) co
    ON co.order_id = sd.order_id
JOIN pizza_count pc ON pc.order_id = sd.order_id
LEFT JOIN runner_ratings rr ON rr.order_id = sd.order_id
ORDER BY sd.order_id;


-- D5. Meat Lovers = $12, Vegetarian = $10 fixed, no cost for extras, and
-- each runner is paid $0.30/km. How much money is left over after paying
-- runners?
WITH revenue AS (
    SELECT SUM(CASE WHEN pn.pizza_name = 'Meat Lovers' THEN 12 ELSE 10 END) AS total_revenue
    FROM customer_orders_clean co
    JOIN successful_deliveries sd ON sd.order_id = co.order_id
    JOIN pizza_names pn ON pn.pizza_id = co.pizza_id
),
runner_pay AS (
    SELECT SUM(distance_km * 0.30) AS total_runner_pay
    FROM successful_deliveries
)
SELECT
    r.total_revenue,
    ROUND(rp.total_runner_pay::numeric, 2) AS total_runner_pay,
    ROUND((r.total_revenue - rp.total_runner_pay)::numeric, 2) AS net_revenue
FROM revenue r, runner_pay rp;


-- ============================================================
-- SECTION E: BONUS - SCHEMA EXPANSION
-- ============================================================

-- If Danny wants to add a new "Supreme" pizza with all 12 toppings, the
-- existing two-table design (pizza_names + pizza_recipes) already supports
-- this with no structural changes - just new rows. This is a direct
-- benefit of normalizing toppings into their own recipe table instead of
-- hardcoding "Meat Lovers" / "Vegetarian" logic into queries.
INSERT INTO pizza_names (pizza_id, pizza_name) VALUES
    (3, 'Supreme');

INSERT INTO pizza_recipes (pizza_id, toppings) VALUES
    (3, '1,2,3,4,5,6,7,8,9,10,11,12');

-- Confirm it slots in cleanly alongside the existing pizzas:
SELECT pn.pizza_name, pt.topping_name
FROM pizza_recipes pr
JOIN pizza_names pn ON pn.pizza_id = pr.pizza_id
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(pr.toppings, ',')::INTEGER[]) AS u(topping_id)
JOIN pizza_toppings pt ON pt.topping_id = u.topping_id
WHERE pn.pizza_name = 'Supreme'
ORDER BY pt.topping_name;
