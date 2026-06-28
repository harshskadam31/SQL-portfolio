-- ============================================================
-- Clique Bait: Digital Analytics & Funnel Analysis
-- File: 03_analysis_queries.sql
-- Author: Harsh
--
-- Covers all three sections of the case study:
--   Section 2: Digital Analysis (9 questions)
--   Section 3: Product Funnel Analysis + summary tables
--   Section 4: Campaign Analysis — one row per visit summary
--
-- All queries written against the clique_bait schema.
-- ============================================================

SET search_path TO clique_bait;

-- ============================================================
-- SECTION 2: DIGITAL ANALYSIS
-- General traffic and behaviour metrics across the site.
-- ============================================================

-- Q1. How many users are there?
SELECT COUNT(DISTINCT user_id) AS total_users
FROM users;


-- Q2. How many cookies does each user have on average?
-- Users can have multiple cookies (multiple devices or browsers).
-- First count per user, then average across users.
WITH cookies_per_user AS (
    SELECT
        u.user_id,
        COUNT(DISTINCT e.cookie_id) AS cookie_count
    FROM users u
    JOIN events e ON e.cookie_id = u.cookie_id
    GROUP BY u.user_id
)
SELECT ROUND(AVG(cookie_count), 2) AS avg_cookies_per_user
FROM cookies_per_user;


-- Q3. Unique number of visits by all users per month.
-- visit_id groups all events from a single session.
-- We use the earliest event_time per visit to assign the month.
SELECT
    TO_CHAR(DATE_TRUNC('month', MIN(event_time)), 'Month YYYY') AS month,
    COUNT(DISTINCT visit_id)                                     AS unique_visits
FROM events
GROUP BY DATE_TRUNC('month', MIN(event_time))
ORDER BY DATE_TRUNC('month', MIN(event_time));


-- Q4. Number of events for each event type.
SELECT
    ei.event_name,
    COUNT(*) AS event_count
FROM events e
JOIN event_identifier ei ON ei.event_type = e.event_type
GROUP BY ei.event_name
ORDER BY event_count DESC;


-- Q5. Percentage of visits which have a purchase event.
-- A purchase is event_type = 3. We check at visit level,
-- not event level — one purchase per visit counts as purchased.
SELECT
    ROUND(
        100.0 * COUNT(DISTINCT CASE WHEN e.event_type = 3 THEN e.visit_id END)
        / COUNT(DISTINCT e.visit_id),
        2
    ) AS pct_visits_with_purchase
FROM events e;


-- Q6. Percentage of visits which view the checkout page
-- but do NOT complete a purchase.
-- These are the most valuable leads — they got to checkout
-- and dropped off. Classic cart abandonment metric.
WITH visit_flags AS (
    SELECT
        visit_id,
        MAX(CASE WHEN page_id = 12 AND event_type = 1 THEN 1 ELSE 0 END) AS viewed_checkout,
        MAX(CASE WHEN event_type = 3                  THEN 1 ELSE 0 END) AS purchased
    FROM events
    GROUP BY visit_id
)
SELECT
    ROUND(
        100.0 * SUM(CASE WHEN viewed_checkout = 1 AND purchased = 0 THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS pct_checkout_no_purchase
FROM visit_flags;


-- Q7. Top 3 pages by number of views (page view events only).
SELECT
    ph.page_name,
    COUNT(*) AS view_count
FROM events e
JOIN page_hierarchy ph ON ph.page_id = e.page_id
WHERE e.event_type = 1  -- Page View only
GROUP BY ph.page_name
ORDER BY view_count DESC
LIMIT 3;


-- Q8. Number of views and cart adds for each product category.
-- Excludes non-product pages (Home, Checkout etc.) which have
-- NULL product_category.
SELECT
    ph.product_category,
    COUNT(*) FILTER (WHERE e.event_type = 1) AS page_views,
    COUNT(*) FILTER (WHERE e.event_type = 2) AS cart_adds
FROM events e
JOIN page_hierarchy ph ON ph.page_id = e.page_id
WHERE ph.product_category IS NOT NULL
GROUP BY ph.product_category
ORDER BY page_views DESC;


-- Q9. Top 3 products by number of purchases.
-- A product is "purchased" if it was added to cart (event_type=2)
-- AND a purchase event (event_type=3) exists in the same visit.
WITH purchased_visits AS (
    SELECT DISTINCT visit_id
    FROM events
    WHERE event_type = 3
),
cart_adds AS (
    SELECT
        e.visit_id,
        ph.page_name   AS product_name,
        ph.product_id
    FROM events e
    JOIN page_hierarchy ph ON ph.page_id = e.page_id
    WHERE e.event_type = 2
      AND ph.product_id IS NOT NULL
)
SELECT
    ca.product_name,
    COUNT(*) AS purchase_count
FROM cart_adds ca
JOIN purchased_visits pv ON pv.visit_id = ca.visit_id
GROUP BY ca.product_name
ORDER BY purchase_count DESC
LIMIT 3;


-- ============================================================
-- SECTION 3: PRODUCT FUNNEL ANALYSIS
-- Build two summary tables: one per product, one per category.
-- ============================================================

-- Product-level funnel table.
-- For each product tracks: views, cart adds, abandonments, purchases.
-- "Abandoned" = added to cart but visit did not result in a purchase.
-- "Purchased" = added to cart AND visit had a purchase event.
DROP TABLE IF EXISTS product_funnel;
CREATE TABLE product_funnel AS
WITH purchased_visits AS (
    SELECT DISTINCT visit_id
    FROM events
    WHERE event_type = 3
),
product_events AS (
    SELECT
        e.visit_id,
        ph.product_id,
        ph.page_name                                AS product_name,
        ph.product_category,
        MAX(CASE WHEN e.event_type = 1 THEN 1 ELSE 0 END) AS viewed,
        MAX(CASE WHEN e.event_type = 2 THEN 1 ELSE 0 END) AS added_to_cart
    FROM events e
    JOIN page_hierarchy ph ON ph.page_id = e.page_id
    WHERE ph.product_id IS NOT NULL
    GROUP BY e.visit_id, ph.product_id, ph.page_name, ph.product_category
)
SELECT
    pe.product_id,
    pe.product_name,
    pe.product_category,
    SUM(pe.viewed)                                                      AS views,
    SUM(pe.added_to_cart)                                               AS cart_adds,
    SUM(CASE WHEN pe.added_to_cart = 1
             AND pv.visit_id IS NULL     THEN 1 ELSE 0 END)            AS abandoned,
    SUM(CASE WHEN pe.added_to_cart = 1
             AND pv.visit_id IS NOT NULL THEN 1 ELSE 0 END)            AS purchases
FROM product_events pe
LEFT JOIN purchased_visits pv ON pv.visit_id = pe.visit_id
GROUP BY pe.product_id, pe.product_name, pe.product_category
ORDER BY pe.product_id;

-- Preview product funnel
SELECT * FROM product_funnel;


-- Category-level funnel table (aggregates product_funnel).
DROP TABLE IF EXISTS category_funnel;
CREATE TABLE category_funnel AS
SELECT
    product_category,
    SUM(views)      AS views,
    SUM(cart_adds)  AS cart_adds,
    SUM(abandoned)  AS abandoned,
    SUM(purchases)  AS purchases
FROM product_funnel
GROUP BY product_category
ORDER BY views DESC;

-- Preview category funnel
SELECT * FROM category_funnel;


-- PF1. Which product had the most views, cart adds and purchases?
SELECT
    'Most Views'    AS metric,
    product_name,
    views           AS value
FROM product_funnel ORDER BY views DESC LIMIT 1
UNION ALL
SELECT
    'Most Cart Adds',
    product_name,
    cart_adds
FROM product_funnel ORDER BY cart_adds DESC LIMIT 1
UNION ALL
SELECT
    'Most Purchases',
    product_name,
    purchases
FROM product_funnel ORDER BY purchases DESC LIMIT 1;


-- PF2. Which product was most likely to be abandoned?
-- Abandonment rate = abandoned / cart_adds
-- (of all products added to cart, what % never got purchased)
SELECT
    product_name,
    cart_adds,
    abandoned,
    ROUND(100.0 * abandoned / NULLIF(cart_adds, 0), 2) AS abandonment_rate_pct
FROM product_funnel
ORDER BY abandonment_rate_pct DESC
LIMIT 1;


-- PF3. Which product had the highest view-to-purchase percentage?
SELECT
    product_name,
    views,
    purchases,
    ROUND(100.0 * purchases / NULLIF(views, 0), 2) AS view_to_purchase_pct
FROM product_funnel
ORDER BY view_to_purchase_pct DESC
LIMIT 1;


-- PF4. Average conversion rate from view to cart add (across all products).
SELECT
    ROUND(AVG(100.0 * cart_adds / NULLIF(views, 0)), 2) AS avg_view_to_cart_pct
FROM product_funnel;


-- PF5. Average conversion rate from cart add to purchase (across all products).
SELECT
    ROUND(AVG(100.0 * purchases / NULLIF(cart_adds, 0)), 2) AS avg_cart_to_purchase_pct
FROM product_funnel;


-- ============================================================
-- SECTION 4: CAMPAIGN ANALYSIS
-- One row per visit summarising all key metrics.
-- Used to evaluate campaign performance and user behaviour.
-- ============================================================

-- Core campaign summary table: one row per visit_id.
DROP TABLE IF EXISTS visit_summary;
CREATE TABLE visit_summary AS
WITH visit_base AS (
    SELECT
        e.visit_id,
        u.user_id,
        MIN(e.event_time)                                               AS visit_start_time,
        COUNT(*) FILTER (WHERE e.event_type = 1)                       AS page_views,
        COUNT(*) FILTER (WHERE e.event_type = 2)                       AS cart_adds,
        MAX(CASE WHEN e.event_type = 3 THEN 1 ELSE 0 END)             AS purchase,
        COUNT(*) FILTER (WHERE e.event_type = 4)                       AS impression,
        COUNT(*) FILTER (WHERE e.event_type = 5)                       AS click
    FROM events e
    JOIN users u ON u.cookie_id = e.cookie_id
    GROUP BY e.visit_id, u.user_id
),
cart_products AS (
    -- Comma-separated list of products added to cart, in order added
    SELECT
        e.visit_id,
        STRING_AGG(ph.page_name, ', ' ORDER BY e.sequence_number) AS cart_products
    FROM events e
    JOIN page_hierarchy ph ON ph.page_id = e.page_id
    WHERE e.event_type = 2
      AND ph.product_id IS NOT NULL
    GROUP BY e.visit_id
)
SELECT
    vb.user_id,
    vb.visit_id,
    vb.visit_start_time,
    vb.page_views,
    vb.cart_adds,
    vb.purchase,
    ci.campaign_name,
    vb.impression,
    vb.click,
    cp.cart_products
FROM visit_base vb
LEFT JOIN campaign_identifier ci
       ON vb.visit_start_time BETWEEN ci.start_date AND ci.end_date
LEFT JOIN cart_products cp ON cp.visit_id = vb.visit_id
ORDER BY vb.user_id, vb.visit_start_time;

-- Preview visit summary
SELECT * FROM visit_summary LIMIT 20;


-- CAMPAIGN INSIGHT 1:
-- Overall purchase rate for campaign visits vs non-campaign visits.
-- Do users who visit during a campaign convert at a higher rate?
SELECT
    CASE WHEN campaign_name IS NOT NULL THEN campaign_name ELSE 'No Campaign' END AS period,
    COUNT(*)                                AS total_visits,
    SUM(purchase)                           AS purchases,
    ROUND(100.0 * SUM(purchase) / COUNT(*), 2) AS purchase_rate_pct
FROM visit_summary
GROUP BY campaign_name
ORDER BY purchase_rate_pct DESC;


-- CAMPAIGN INSIGHT 2:
-- Impact of ad impressions on purchase rate.
-- Splits visits into three groups:
--   (a) received impression AND clicked
--   (b) received impression but did NOT click
--   (c) no impression at all
-- This directly answers: does clicking an ad lead to higher purchase rates?
SELECT
    CASE
        WHEN impression > 0 AND click > 0 THEN 'Impression + Click'
        WHEN impression > 0 AND click = 0 THEN 'Impression, No Click'
        ELSE                                    'No Impression'
    END                                                 AS user_group,
    COUNT(*)                                            AS visits,
    SUM(purchase)                                       AS purchases,
    ROUND(100.0 * SUM(purchase) / COUNT(*), 2)         AS purchase_rate_pct,
    ROUND(AVG(cart_adds), 2)                            AS avg_cart_adds,
    ROUND(AVG(page_views), 2)                           AS avg_page_views
FROM visit_summary
GROUP BY
    CASE
        WHEN impression > 0 AND click > 0 THEN 'Impression + Click'
        WHEN impression > 0 AND click = 0 THEN 'Impression, No Click'
        ELSE                                    'No Impression'
    END
ORDER BY purchase_rate_pct DESC;


-- CAMPAIGN INSIGHT 3:
-- Campaign-level performance comparison.
-- Which campaign drove the most visits, highest purchase rate,
-- and most cart adds? This is the apples-to-apples campaign comparison.
SELECT
    campaign_name,
    COUNT(*)                                            AS total_visits,
    SUM(impression)                                     AS total_impressions,
    SUM(click)                                          AS total_clicks,
    ROUND(100.0 * SUM(click) / NULLIF(SUM(impression), 0), 2) AS click_through_rate_pct,
    SUM(purchase)                                       AS total_purchases,
    ROUND(100.0 * SUM(purchase) / COUNT(*), 2)         AS purchase_rate_pct,
    ROUND(AVG(cart_adds), 2)                            AS avg_cart_adds_per_visit
FROM visit_summary
WHERE campaign_name IS NOT NULL
GROUP BY campaign_name
ORDER BY purchase_rate_pct DESC;


-- CAMPAIGN INSIGHT 4:
-- Cart abandonment rate during campaign vs non-campaign periods.
-- High abandonment during a campaign could mean the ad drove
-- low-intent traffic (people browsing due to the promotion but
-- not genuinely ready to buy).
SELECT
    CASE WHEN campaign_name IS NOT NULL THEN 'Campaign Period' ELSE 'No Campaign' END AS period,
    SUM(cart_adds)                                          AS total_cart_adds,
    SUM(CASE WHEN cart_adds > 0 AND purchase = 0 THEN 1 ELSE 0 END) AS visits_abandoned,
    ROUND(
        100.0 * SUM(CASE WHEN cart_adds > 0 AND purchase = 0 THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN cart_adds > 0 THEN 1 ELSE 0 END), 0),
        2
    ) AS abandonment_rate_pct
FROM visit_summary
GROUP BY CASE WHEN campaign_name IS NOT NULL THEN 'Campaign Period' ELSE 'No Campaign' END;


-- CAMPAIGN INSIGHT 5:
-- Top 10 most engaged users (by total cart adds across all visits).
-- High cart-adders who haven't purchased are the clearest
-- retargeting candidates — they show intent but haven't converted.
SELECT
    user_id,
    COUNT(visit_id)         AS total_visits,
    SUM(page_views)         AS total_page_views,
    SUM(cart_adds)          AS total_cart_adds,
    SUM(purchase)           AS total_purchases,
    SUM(impression)         AS total_impressions,
    SUM(click)              AS total_ad_clicks
FROM visit_summary
GROUP BY user_id
ORDER BY total_cart_adds DESC
LIMIT 10;


-- ============================================================
-- REPORTING VIEW
-- Flattened view joining all 5 tables for BI tool consumption.
-- ============================================================
CREATE OR REPLACE VIEW clique_bait.vw_full_event_detail AS
SELECT
    e.visit_id,
    u.user_id,
    e.cookie_id,
    e.sequence_number,
    e.event_time,
    ei.event_name,
    ph.page_name,
    ph.product_category,
    ph.product_id,
    ci.campaign_name
FROM events e
JOIN users           u  ON u.cookie_id    = e.cookie_id
JOIN event_identifier ei ON ei.event_type = e.event_type
JOIN page_hierarchy  ph  ON ph.page_id    = e.page_id
LEFT JOIN campaign_identifier ci
       ON e.event_time BETWEEN ci.start_date AND ci.end_date;
