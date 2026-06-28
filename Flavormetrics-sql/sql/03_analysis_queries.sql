-- ============================================================
-- FlavorMetrics: Customer & Loyalty Analytics
-- File: 03_analysis_queries.sql
-- Author: Harsh
--
-- All queries below were written and verified against a live
-- PostgreSQL 16 instance loaded with 01_schema.sql + 02_seed_data.sql.
-- Organized into four tiers of increasing complexity.
-- ============================================================

SET search_path TO flavormetrics;

-- ============================================================
-- ORIGINAL CASE STUDY QUESTIONS (adapted to the FlavorMetrics schema)
-- These are the 10 standard "Danny's Diner"-style case study questions,
-- rewritten to run against this project's normalized schema (orders +
-- order_items instead of one flat sales table) and its loyalty/menu
-- structure. Included alongside the Tier 1-4 analysis above so this
-- project covers both the original case-study format and the extended
-- business-analysis layer.
-- ============================================================

-- CQ1. What is the total amount each customer has spent?
SELECT
    o.customer_id,
    SUM(mi.price * oi.quantity) AS total_spent
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN menu_items mi  ON mi.product_id = oi.product_id
GROUP BY o.customer_id
ORDER BY o.customer_id;


-- CQ2. How many days has each customer visited (placed at least one order)?
SELECT
    customer_id,
    COUNT(DISTINCT order_date) AS days_visited
FROM orders
GROUP BY customer_id
ORDER BY customer_id;


-- CQ3. What was the first item purchased by each customer?
-- (DENSE_RANK so multiple items on the same first order all show up)
WITH ranked AS (
    SELECT
        o.customer_id,
        o.order_id,
        o.order_date,
        oi.product_id,
        DENSE_RANK() OVER (PARTITION BY o.customer_id ORDER BY o.order_date, o.order_id) AS rnk
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
)
SELECT
    r.customer_id,
    mi.product_name,
    r.order_date AS first_order_date
FROM ranked r
JOIN menu_items mi ON mi.product_id = r.product_id
WHERE r.rnk = 1
ORDER BY r.customer_id;


-- CQ4. What is the most purchased item overall, and how many times was it purchased?
SELECT
    mi.product_name,
    SUM(oi.quantity) AS total_purchased
FROM order_items oi
JOIN menu_items mi ON mi.product_id = oi.product_id
GROUP BY mi.product_name
ORDER BY total_purchased DESC
LIMIT 1;


-- CQ5. Which item was the most popular for each customer? (ties included)
WITH item_counts AS (
    SELECT
        o.customer_id,
        mi.product_name,
        SUM(oi.quantity) AS qty,
        RANK() OVER (PARTITION BY o.customer_id ORDER BY SUM(oi.quantity) DESC) AS rnk
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN menu_items mi  ON mi.product_id = oi.product_id
    GROUP BY o.customer_id, mi.product_name
)
SELECT customer_id, product_name, qty
FROM item_counts
WHERE rnk = 1
ORDER BY customer_id;


-- CQ6. Which item was purchased first by each customer AFTER they became a loyalty member?
WITH member_orders AS (
    SELECT
        o.customer_id,
        o.order_id,
        o.order_date,
        RANK() OVER (PARTITION BY o.customer_id ORDER BY o.order_date) AS rnk
    FROM orders o
    JOIN loyalty_members lm ON lm.customer_id = o.customer_id
    WHERE o.order_date >= lm.join_date
)
SELECT
    mo.customer_id,
    mi.product_name,
    mo.order_date
FROM member_orders mo
JOIN order_items oi ON oi.order_id = mo.order_id
JOIN menu_items mi  ON mi.product_id = oi.product_id
WHERE mo.rnk = 1
ORDER BY mo.customer_id;


-- CQ7. Which item was purchased just BEFORE the customer became a member?
WITH pre_member_orders AS (
    SELECT
        o.customer_id,
        o.order_id,
        o.order_date,
        RANK() OVER (PARTITION BY o.customer_id ORDER BY o.order_date DESC) AS rnk
    FROM orders o
    JOIN loyalty_members lm ON lm.customer_id = o.customer_id
    WHERE o.order_date < lm.join_date
)
SELECT
    pmo.customer_id,
    mi.product_name,
    pmo.order_date
FROM pre_member_orders pmo
JOIN order_items oi ON oi.order_id = pmo.order_id
JOIN menu_items mi  ON mi.product_id = oi.product_id
WHERE pmo.rnk = 1
ORDER BY pmo.customer_id;


-- CQ8. What is the total items and amount spent by each member BEFORE they
-- became a member? (Customers who never ordered pre-membership are
-- correctly absent here, not shown with zero.)
SELECT
    o.customer_id,
    SUM(oi.quantity)            AS total_items,
    SUM(mi.price * oi.quantity) AS total_spent
FROM orders o
JOIN loyalty_members lm ON lm.customer_id = o.customer_id
JOIN order_items oi     ON oi.order_id = o.order_id
JOIN menu_items mi      ON mi.product_id = oi.product_id
WHERE o.order_date < lm.join_date
GROUP BY o.customer_id
ORDER BY o.customer_id;


-- CQ9. Points system: 1 rupee spent = 10 points, but items in the "Sushi"
-- category earn a 2x multiplier. How many points does each customer have?
SELECT
    o.customer_id,
    SUM(
        CASE WHEN mi.category = 'Sushi'
             THEN mi.price * oi.quantity * 10 * 2
             ELSE mi.price * oi.quantity * 10
        END
    ) AS total_points
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN menu_items mi  ON mi.product_id = oi.product_id
GROUP BY o.customer_id
ORDER BY o.customer_id;


-- CQ10. In the first week after a customer joins the loyalty program
-- (join_date inclusive), they earn 2x points on ALL items, not just sushi.
-- Sushi items still earn 2x at all other times. How many points has each
-- member accumulated by the end of June 2023?
-- (June 2023 is used here as the reference month, since it is the first
-- month in this dataset with multiple members past their join date - the
-- same role "end of January" played in the original case study.)
WITH member_orders AS (
    SELECT
        o.customer_id,
        o.order_id,
        o.order_date,
        lm.join_date
    FROM orders o
    JOIN loyalty_members lm ON lm.customer_id = o.customer_id
    WHERE o.order_date >= lm.join_date
      AND o.order_date <= '2023-06-30'
)
SELECT
    mo.customer_id,
    SUM(
        CASE
            WHEN mo.order_date BETWEEN mo.join_date AND mo.join_date + INTERVAL '6 days'
                THEN mi.price * oi.quantity * 10 * 2
            WHEN mi.category = 'Sushi'
                THEN mi.price * oi.quantity * 10 * 2
            ELSE mi.price * oi.quantity * 10
        END
    ) AS total_points
FROM member_orders mo
JOIN order_items oi ON oi.order_id = mo.order_id
JOIN menu_items mi  ON mi.product_id = oi.product_id
GROUP BY mo.customer_id
ORDER BY mo.customer_id;


-- ============================================================
-- TIER 1: FOUNDATIONAL AGGREGATION & JOINS
-- ============================================================

-- Q1. What is the total amount each customer has spent, all-time?
SELECT
    c.customer_id,
    c.first_name,
    SUM(mi.price * oi.quantity) AS total_spent
FROM customers c
JOIN orders o       ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN menu_items mi  ON mi.product_id = oi.product_id
GROUP BY c.customer_id, c.first_name
ORDER BY total_spent DESC;


-- Q2. How many distinct days has each customer visited (placed an order)?
SELECT
    customer_id,
    COUNT(DISTINCT order_date) AS days_visited
FROM orders
GROUP BY customer_id
ORDER BY days_visited DESC;


-- Q3. What is the most popular product overall (by total quantity sold)?
SELECT
    mi.product_name,
    SUM(oi.quantity) AS total_quantity_sold
FROM order_items oi
JOIN menu_items mi ON mi.product_id = oi.product_id
GROUP BY mi.product_name
ORDER BY total_quantity_sold DESC
LIMIT 5;


-- Q4. What is total revenue and gross margin (%) by product category?
SELECT
    mi.category,
    SUM(mi.price * oi.quantity)               AS revenue,
    SUM((mi.price - mi.cost) * oi.quantity)   AS gross_profit,
    ROUND(
        100.0 * SUM((mi.price - mi.cost) * oi.quantity) / SUM(mi.price * oi.quantity),
        2
    ) AS gross_margin_pct
FROM order_items oi
JOIN menu_items mi ON mi.product_id = oi.product_id
GROUP BY mi.category
ORDER BY revenue DESC;


-- Q5. Which store generates the highest average order value (AOV)?
SELECT
    s.store_name,
    s.city,
    COUNT(DISTINCT o.order_id)                                   AS total_orders,
    ROUND(SUM(mi.price * oi.quantity)::numeric, 2)                AS total_revenue,
    ROUND(SUM(mi.price * oi.quantity) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM stores s
JOIN orders o       ON o.store_id = s.store_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN menu_items mi  ON mi.product_id = oi.product_id
GROUP BY s.store_name, s.city
ORDER BY avg_order_value DESC;


-- ============================================================
-- TIER 2: WINDOW FUNCTIONS
-- ============================================================

-- Q6. What was each customer's first-ever order, and which item(s) did they buy on it?
-- (DENSE_RANK handles the case where a customer placed multiple orders on the same first day)
WITH ranked_orders AS (
    SELECT
        o.customer_id,
        o.order_id,
        o.order_date,
        DENSE_RANK() OVER (PARTITION BY o.customer_id ORDER BY o.order_date, o.order_id) AS order_rank
    FROM orders o
)
SELECT
    ro.customer_id,
    ro.order_date AS first_order_date,
    mi.product_name
FROM ranked_orders ro
JOIN order_items oi ON oi.order_id = ro.order_id
JOIN menu_items mi  ON mi.product_id = oi.product_id
WHERE ro.order_rank = 1
ORDER BY ro.customer_id;


-- Q7. What is each customer's single favourite item (by quantity), including ties?
WITH item_counts AS (
    SELECT
        o.customer_id,
        mi.product_name,
        SUM(oi.quantity) AS total_qty,
        RANK() OVER (PARTITION BY o.customer_id ORDER BY SUM(oi.quantity) DESC) AS item_rank
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN menu_items mi  ON mi.product_id = oi.product_id
    GROUP BY o.customer_id, mi.product_name
)
SELECT customer_id, product_name, total_qty
FROM item_counts
WHERE item_rank = 1
ORDER BY customer_id;


-- Q8. Rank every member's orders chronologically AFTER they joined the loyalty
-- program (non-member orders should show a NULL rank rather than be excluded).
WITH tagged_orders AS (
    SELECT
        o.customer_id,
        o.order_id,
        o.order_date,
        lm.join_date,
        CASE WHEN o.order_date >= lm.join_date THEN 'Y' ELSE 'N' END AS is_member_order
    FROM orders o
    LEFT JOIN loyalty_members lm ON lm.customer_id = o.customer_id
)
SELECT
    customer_id,
    order_id,
    order_date,
    is_member_order,
    CASE WHEN is_member_order = 'Y'
         THEN RANK() OVER (
                PARTITION BY customer_id, is_member_order
                ORDER BY order_date
              )
         ELSE NULL
    END AS member_order_rank
FROM tagged_orders
ORDER BY customer_id, order_date
LIMIT 20;


-- Q9. Running 30-day rolling order count per store (operational load monitoring)
SELECT
    store_id,
    order_date,
    COUNT(*) AS orders_that_day,
    SUM(COUNT(*)) OVER (
        PARTITION BY store_id
        ORDER BY order_date
        RANGE BETWEEN INTERVAL '29 days' PRECEDING AND CURRENT ROW
    ) AS rolling_30day_orders
FROM orders
GROUP BY store_id, order_date
ORDER BY store_id, order_date
LIMIT 15;


-- ============================================================
-- TIER 3: CTEs & MULTI-STEP BUSINESS LOGIC
-- ============================================================

-- Q10. Loyalty Program Impact: compare average order value and order
-- frequency for members BEFORE vs. AFTER they joined the program.
-- This directly answers "is the loyalty program worth expanding?"
WITH spend_by_period AS (
    SELECT
        o.customer_id,
        CASE WHEN o.order_date < lm.join_date THEN 'pre_membership' ELSE 'post_membership' END AS period,
        SUM(mi.price * oi.quantity)        AS total_spend,
        COUNT(DISTINCT o.order_id)         AS order_count
    FROM loyalty_members lm
    JOIN orders o       ON o.customer_id = lm.customer_id
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN menu_items mi  ON mi.product_id = oi.product_id
    GROUP BY o.customer_id, lm.join_date,
             CASE WHEN o.order_date < lm.join_date THEN 'pre_membership' ELSE 'post_membership' END
)
SELECT
    period,
    COUNT(DISTINCT customer_id)                                         AS num_customers,
    ROUND(AVG(order_count), 2)                                          AS avg_orders_per_customer,
    ROUND(AVG(total_spend / GREATEST(order_count, 1)), 2)               AS avg_order_value
FROM spend_by_period
GROUP BY period;


-- Q11. Monthly Cohort Retention: of customers who placed their first order
-- in a given month, what % were still ordering N months later?
WITH first_order AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', MIN(order_date))::date AS cohort_month
    FROM orders
    GROUP BY customer_id
),
activity AS (
    SELECT
        o.customer_id,
        fo.cohort_month,
        DATE_TRUNC('month', o.order_date)::date AS order_month
    FROM orders o
    JOIN first_order fo ON fo.customer_id = o.customer_id
),
cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_total
    FROM first_order GROUP BY cohort_month
),
monthly_activity AS (
    SELECT
        cohort_month,
        order_month,
        (EXTRACT(YEAR  FROM order_month) - EXTRACT(YEAR  FROM cohort_month)) * 12 +
        (EXTRACT(MONTH FROM order_month) - EXTRACT(MONTH FROM cohort_month))     AS month_number,
        COUNT(DISTINCT customer_id) AS active_customers
    FROM activity
    GROUP BY cohort_month, order_month
)
SELECT
    ma.cohort_month,
    ma.month_number,
    ma.active_customers,
    cs.cohort_total,
    ROUND(100.0 * ma.active_customers / cs.cohort_total, 1) AS retention_pct
FROM monthly_activity ma
JOIN cohort_size cs ON cs.cohort_month = ma.cohort_month
ORDER BY ma.cohort_month, ma.month_number;


-- Q12. RFM Customer Segmentation: bucket every customer into
-- Recency / Frequency / Monetary quartiles and assign a segment label.
-- This is the kind of segmentation a growth/marketing PM would use to
-- decide who gets a re-engagement campaign vs. a loyalty upsell.
WITH customer_stats AS (
    SELECT
        c.customer_id,
        c.first_name,
        MAX(o.order_date)                  AS last_order_date,
        COUNT(DISTINCT o.order_id)         AS frequency,
        SUM(mi.price * oi.quantity)        AS monetary
    FROM customers c
    JOIN orders o       ON o.customer_id = c.customer_id
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN menu_items mi  ON mi.product_id = oi.product_id
    GROUP BY c.customer_id, c.first_name
),
scored AS (
    SELECT
        *,
        (DATE '2024-12-31' - last_order_date)                                       AS recency_days,
        NTILE(4) OVER (ORDER BY (DATE '2024-12-31' - last_order_date) DESC)         AS recency_score,
        NTILE(4) OVER (ORDER BY frequency ASC)                                       AS frequency_score,
        NTILE(4) OVER (ORDER BY monetary ASC)                                        AS monetary_score
    FROM customer_stats
)
SELECT
    customer_id,
    first_name,
    recency_days,
    frequency,
    monetary,
    CASE
        WHEN recency_score >= 3 AND frequency_score >= 3 AND monetary_score >= 3 THEN 'Champion'
        WHEN recency_score <= 2 AND frequency_score >= 3                        THEN 'At Risk'
        WHEN frequency_score <= 2 AND monetary_score <= 2                       THEN 'Low Value'
        ELSE 'Regular'
    END AS rfm_segment
FROM scored
ORDER BY monetary DESC;


-- Q13. Loyalty Tier Value: total & average revenue contribution by tier,
-- including the "Not a Member" bucket for comparison.
WITH customer_revenue AS (
    SELECT
        c.customer_id,
        COALESCE(lm.tier, 'Not a Member') AS tier,
        SUM(mi.price * oi.quantity)       AS revenue
    FROM customers c
    JOIN orders o            ON o.customer_id = c.customer_id
    JOIN order_items oi      ON oi.order_id = o.order_id
    JOIN menu_items mi       ON mi.product_id = oi.product_id
    LEFT JOIN loyalty_members lm ON lm.customer_id = c.customer_id
    GROUP BY c.customer_id, COALESCE(lm.tier, 'Not a Member')
)
SELECT
    tier,
    COUNT(*)                          AS num_customers,
    ROUND(SUM(revenue), 2)            AS total_revenue,
    ROUND(AVG(revenue), 2)            AS avg_revenue_per_customer
FROM customer_revenue
GROUP BY tier
ORDER BY avg_revenue_per_customer DESC;


-- ============================================================
-- TIER 4: REPORTING VIEWS ("Join All The Things")
-- These recreate the kind of pre-joined, query-free tables a
-- non-technical stakeholder (e.g. ops team) could read directly.
-- ============================================================

-- Q14. A flattened order detail view: every line item with customer,
-- product, price, and membership status at time of order, ready for
-- a BI tool like Power BI to consume directly without further joins.
CREATE OR REPLACE VIEW vw_order_details AS
SELECT
    o.customer_id,
    o.order_id,
    o.order_date,
    s.store_name,
    mi.product_name,
    mi.category,
    oi.quantity,
    mi.price,
    (mi.price * oi.quantity) AS line_total,
    CASE
        WHEN lm.join_date IS NOT NULL AND o.order_date >= lm.join_date THEN 'Y'
        ELSE 'N'
    END AS member_at_time_of_order
FROM orders o
JOIN stores s              ON s.store_id = o.store_id
JOIN order_items oi        ON oi.order_id = o.order_id
JOIN menu_items mi         ON mi.product_id = oi.product_id
LEFT JOIN loyalty_members lm ON lm.customer_id = o.customer_id;

SELECT * FROM vw_order_details ORDER BY customer_id, order_date LIMIT 10;


-- Q15. Monthly revenue trend with month-over-month growth %
-- (the kind of single chart-ready table a PM would put straight into a slide)
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', o.order_date)::date AS month,
        SUM(mi.price * oi.quantity)             AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    JOIN menu_items mi  ON mi.product_id = oi.product_id
    GROUP BY DATE_TRUNC('month', o.order_date)
)
SELECT
    month,
    ROUND(revenue, 2) AS revenue,
    ROUND(
        100.0 * (revenue - LAG(revenue) OVER (ORDER BY month)) / LAG(revenue) OVER (ORDER BY month),
        1
    ) AS mom_growth_pct
FROM monthly_revenue
ORDER BY month;
