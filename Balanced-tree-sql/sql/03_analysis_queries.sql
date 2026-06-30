-- ============================================================
-- Balanced Tree Clothing Co.: Sales & Merchandising Analytics
-- File: 03_analysis_queries.sql
-- Author: Harsh
--
-- Covers all sections of the case study:
--   Section 1: High Level Sales Analysis (3 questions)
--   Section 2: Transaction Analysis (6 questions)
--   Section 3: Product Analysis (10 questions)
--   Section 4: Reporting Challenge (monthly script for Jan + Feb)
--   Bonus:     Recursive CTE to rebuild product_details from scratch
--
-- Net revenue throughout = qty * price * (1 - discount/100)
-- Gross revenue          = qty * price (before discount)
-- ============================================================

SET search_path TO balanced_tree;

-- ============================================================
-- SECTION 1: HIGH LEVEL SALES ANALYSIS
-- ============================================================

-- S1. Total quantity sold across all products.
SELECT SUM(qty) AS total_quantity_sold
FROM sales;


-- S2. Total revenue before discounts (gross revenue).
-- price in sales is the listed unit price, qty is units sold.
SELECT SUM(qty * price) AS total_gross_revenue
FROM sales;


-- S3. Total discount amount across all products.
-- Discount is stored as an integer percentage.
-- discount_amount = qty * price * (discount / 100)
SELECT
    ROUND(SUM(qty * price * discount / 100.0), 2) AS total_discount_amount
FROM sales;


-- ============================================================
-- SECTION 2: TRANSACTION ANALYSIS
-- ============================================================

-- T1. How many unique transactions were there?
SELECT COUNT(DISTINCT txn_id) AS unique_transactions
FROM sales;


-- T2. Average number of unique products purchased per transaction.
WITH products_per_txn AS (
    SELECT
        txn_id,
        COUNT(DISTINCT prod_id) AS unique_products
    FROM sales
    GROUP BY txn_id
)
SELECT ROUND(AVG(unique_products), 2) AS avg_unique_products_per_txn
FROM products_per_txn;


-- T3. 25th, 50th, and 75th percentile of revenue per transaction.
-- Revenue here is net (after discount) to reflect actual earnings.
WITH txn_revenue AS (
    SELECT
        txn_id,
        SUM(qty * price * (1 - discount / 100.0)) AS net_revenue
    FROM sales
    GROUP BY txn_id
)
SELECT
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY net_revenue) AS p25_revenue,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY net_revenue) AS p50_revenue,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY net_revenue) AS p75_revenue
FROM txn_revenue;


-- T4. Average discount value per transaction.
WITH txn_discounts AS (
    SELECT
        txn_id,
        SUM(qty * price * discount / 100.0) AS total_discount
    FROM sales
    GROUP BY txn_id
)
SELECT ROUND(AVG(total_discount), 2) AS avg_discount_per_txn
FROM txn_discounts;


-- T5. Percentage split of transactions: members vs non-members.
-- A transaction is "member" if ANY line item in it has member = true.
-- (In practice all line items in a transaction share the same member flag.)
WITH txn_member AS (
    SELECT
        txn_id,
        MAX(member::INT) AS is_member
    FROM sales
    GROUP BY txn_id
)
SELECT
    ROUND(100.0 * SUM(is_member)     / COUNT(*), 2) AS member_pct,
    ROUND(100.0 * SUM(1 - is_member) / COUNT(*), 2) AS non_member_pct
FROM txn_member;


-- T6. Average net revenue for member vs non-member transactions.
WITH txn_revenue AS (
    SELECT
        txn_id,
        MAX(member::INT)                               AS is_member,
        SUM(qty * price * (1 - discount / 100.0))     AS net_revenue
    FROM sales
    GROUP BY txn_id
)
SELECT
    CASE WHEN is_member = 1 THEN 'Member' ELSE 'Non-Member' END AS customer_type,
    ROUND(AVG(net_revenue), 2)                                   AS avg_net_revenue
FROM txn_revenue
GROUP BY is_member
ORDER BY is_member DESC;


-- ============================================================
-- SECTION 3: PRODUCT ANALYSIS
-- ============================================================

-- P1. Top 3 products by total gross revenue (before discount).
SELECT
    pd.product_name,
    SUM(s.qty * s.price) AS gross_revenue
FROM sales s
JOIN product_details pd ON pd.product_id = s.prod_id
GROUP BY pd.product_name
ORDER BY gross_revenue DESC
LIMIT 3;


-- P2. Total quantity, revenue (net), and discount for each segment.
SELECT
    pd.segment_name,
    SUM(s.qty)                                          AS total_qty,
    ROUND(SUM(s.qty * s.price * (1 - s.discount/100.0)), 2) AS net_revenue,
    ROUND(SUM(s.qty * s.price * s.discount / 100.0), 2)     AS total_discount
FROM sales s
JOIN product_details pd ON pd.product_id = s.prod_id
GROUP BY pd.segment_name
ORDER BY net_revenue DESC;


-- P3. Top selling product for each segment (by total quantity sold).
-- Uses RANK() to handle ties correctly — if two products tie for
-- most units sold, both get rank 1.
WITH segment_product_qty AS (
    SELECT
        pd.segment_name,
        pd.product_name,
        SUM(s.qty) AS total_qty,
        RANK() OVER (PARTITION BY pd.segment_name ORDER BY SUM(s.qty) DESC) AS rnk
    FROM sales s
    JOIN product_details pd ON pd.product_id = s.prod_id
    GROUP BY pd.segment_name, pd.product_name
)
SELECT segment_name, product_name, total_qty
FROM segment_product_qty
WHERE rnk = 1
ORDER BY segment_name;


-- P4. Total quantity, revenue (net), and discount for each category.
SELECT
    pd.category_name,
    SUM(s.qty)                                               AS total_qty,
    ROUND(SUM(s.qty * s.price * (1 - s.discount/100.0)), 2) AS net_revenue,
    ROUND(SUM(s.qty * s.price * s.discount / 100.0), 2)     AS total_discount
FROM sales s
JOIN product_details pd ON pd.product_id = s.prod_id
GROUP BY pd.category_name
ORDER BY net_revenue DESC;


-- P5. Top selling product for each category (by total quantity).
WITH category_product_qty AS (
    SELECT
        pd.category_name,
        pd.product_name,
        SUM(s.qty) AS total_qty,
        RANK() OVER (PARTITION BY pd.category_name ORDER BY SUM(s.qty) DESC) AS rnk
    FROM sales s
    JOIN product_details pd ON pd.product_id = s.prod_id
    GROUP BY pd.category_name, pd.product_name
)
SELECT category_name, product_name, total_qty
FROM category_product_qty
WHERE rnk = 1
ORDER BY category_name;


-- P6. Percentage split of net revenue by product within each segment.
-- Shows which products drive the most revenue inside their segment.
WITH segment_revenue AS (
    SELECT
        pd.segment_name,
        pd.product_name,
        SUM(s.qty * s.price * (1 - s.discount/100.0)) AS product_revenue
    FROM sales s
    JOIN product_details pd ON pd.product_id = s.prod_id
    GROUP BY pd.segment_name, pd.product_name
)
SELECT
    segment_name,
    product_name,
    ROUND(product_revenue, 2) AS product_revenue,
    ROUND(
        100.0 * product_revenue / SUM(product_revenue) OVER (PARTITION BY segment_name),
        2
    ) AS pct_of_segment_revenue
FROM segment_revenue
ORDER BY segment_name, pct_of_segment_revenue DESC;


-- P7. Percentage split of net revenue by segment within each category.
WITH category_segment_revenue AS (
    SELECT
        pd.category_name,
        pd.segment_name,
        SUM(s.qty * s.price * (1 - s.discount/100.0)) AS segment_revenue
    FROM sales s
    JOIN product_details pd ON pd.product_id = s.prod_id
    GROUP BY pd.category_name, pd.segment_name
)
SELECT
    category_name,
    segment_name,
    ROUND(segment_revenue, 2) AS segment_revenue,
    ROUND(
        100.0 * segment_revenue / SUM(segment_revenue) OVER (PARTITION BY category_name),
        2
    ) AS pct_of_category_revenue
FROM category_segment_revenue
ORDER BY category_name, pct_of_category_revenue DESC;


-- P8. Percentage split of total net revenue by category.
WITH total_revenue AS (
    SELECT SUM(qty * price * (1 - discount/100.0)) AS grand_total FROM sales
),
category_revenue AS (
    SELECT
        pd.category_name,
        SUM(s.qty * s.price * (1 - s.discount/100.0)) AS cat_revenue
    FROM sales s
    JOIN product_details pd ON pd.product_id = s.prod_id
    GROUP BY pd.category_name
)
SELECT
    category_name,
    ROUND(cat_revenue, 2)                               AS category_revenue,
    ROUND(100.0 * cat_revenue / tr.grand_total, 2)     AS pct_of_total_revenue
FROM category_revenue
CROSS JOIN total_revenue tr
ORDER BY pct_of_total_revenue DESC;


-- P9. Transaction penetration for each product.
-- Penetration = transactions containing this product / total transactions.
-- Shows which products appear most broadly across the customer base
-- (vs being bought in bulk by few customers — qty doesn't matter here,
-- just whether the product appeared in the transaction at all).
WITH total_txns AS (
    SELECT COUNT(DISTINCT txn_id) AS total FROM sales
),
product_txns AS (
    SELECT
        prod_id,
        COUNT(DISTINCT txn_id) AS txns_with_product
    FROM sales
    GROUP BY prod_id
)
SELECT
    pd.product_name,
    pt.txns_with_product,
    ROUND(100.0 * pt.txns_with_product / tt.total, 2) AS penetration_pct
FROM product_txns pt
JOIN product_details pd ON pd.product_id = pt.prod_id
CROSS JOIN total_txns tt
ORDER BY penetration_pct DESC;


-- P10. Most common combination of any 3 products in a single transaction.
-- This is a self-join approach: join sales to itself twice on txn_id
-- to generate all 3-product combinations, then count frequency.
-- prod_id ordering (p1 < p2 < p3) prevents counting the same combo
-- multiple times in different orders.
WITH product_combos AS (
    SELECT
        s1.txn_id,
        s1.prod_id AS p1,
        s2.prod_id AS p2,
        s3.prod_id AS p3
    FROM sales s1
    JOIN sales s2 ON s2.txn_id = s1.txn_id AND s2.prod_id > s1.prod_id
    JOIN sales s3 ON s3.txn_id = s1.txn_id AND s3.prod_id > s2.prod_id
),
combo_counts AS (
    SELECT
        p1, p2, p3,
        COUNT(*) AS combo_count
    FROM product_combos
    GROUP BY p1, p2, p3
)
SELECT
    pd1.product_name AS product_1,
    pd2.product_name AS product_2,
    pd3.product_name AS product_3,
    cc.combo_count
FROM combo_counts cc
JOIN product_details pd1 ON pd1.product_id = cc.p1
JOIN product_details pd2 ON pd2.product_id = cc.p2
JOIN product_details pd3 ON pd3.product_id = cc.p3
ORDER BY combo_count DESC
LIMIT 1;


-- ============================================================
-- SECTION 4: REPORTING CHALLENGE
-- A single parameterised script that generates all the above
-- metrics for a specific month. Run for January first,
-- then change the date filter to February with no other changes.
--
-- Change the two date values below to switch months:
--   January:  '2021-01-01' to '2021-01-31'
--   February: '2021-02-01' to '2021-02-28'
-- ============================================================

DO $$
DECLARE
    v_start DATE := '2021-01-01';  -- ← Change this to run a different month
    v_end   DATE := '2021-01-31';  -- ← Change this too
BEGIN
    RAISE NOTICE 'Running monthly report for % to %', v_start, v_end;
END $$;

-- Monthly Sales Summary
WITH monthly_sales AS (
    SELECT *
    FROM sales
    WHERE start_txn_time::DATE BETWEEN '2021-01-01' AND '2021-01-31'
    -- For February: change dates to '2021-02-01' AND '2021-02-28'
)
SELECT
    'High Level'                                                     AS report_section,
    SUM(qty)                                                         AS total_qty,
    SUM(qty * price)                                                 AS gross_revenue,
    ROUND(SUM(qty * price * (1 - discount/100.0)), 2)               AS net_revenue,
    ROUND(SUM(qty * price * discount / 100.0), 2)                   AS total_discounts,
    COUNT(DISTINCT txn_id)                                           AS unique_transactions
FROM monthly_sales;

-- Monthly Product Performance
WITH monthly_sales AS (
    SELECT s.*, pd.product_name, pd.segment_name, pd.category_name
    FROM sales s
    JOIN product_details pd ON pd.product_id = s.prod_id
    WHERE s.start_txn_time::DATE BETWEEN '2021-01-01' AND '2021-01-31'
)
SELECT
    product_name,
    segment_name,
    category_name,
    SUM(qty)                                                    AS total_qty,
    SUM(qty * price)                                            AS gross_revenue,
    ROUND(SUM(qty * price * (1 - discount/100.0)), 2)          AS net_revenue,
    ROUND(SUM(qty * price * discount / 100.0), 2)              AS total_discount
FROM monthly_sales
GROUP BY product_name, segment_name, category_name
ORDER BY net_revenue DESC;

-- Monthly Member vs Non-Member Split
WITH monthly_txns AS (
    SELECT
        txn_id,
        MAX(member::INT)                               AS is_member,
        SUM(qty * price * (1 - discount/100.0))       AS net_revenue
    FROM sales
    WHERE start_txn_time::DATE BETWEEN '2021-01-01' AND '2021-01-31'
    GROUP BY txn_id
)
SELECT
    CASE WHEN is_member = 1 THEN 'Member' ELSE 'Non-Member' END AS customer_type,
    COUNT(*)                                                       AS transactions,
    ROUND(AVG(net_revenue), 2)                                     AS avg_revenue_per_txn,
    ROUND(SUM(net_revenue), 2)                                     AS total_revenue
FROM monthly_txns
GROUP BY is_member
ORDER BY is_member DESC;


-- ============================================================
-- BONUS CHALLENGE: Rebuild product_details using a recursive CTE
-- Starting from product_hierarchy + product_prices alone —
-- no hardcoded values.
--
-- The hierarchy has 3 levels: Category → Segment → Style.
-- For each Style (leaf node), we need to walk UP the tree
-- to find its Segment and then its Category.
-- A recursive CTE makes this elegant regardless of depth.
-- ============================================================

WITH RECURSIVE hierarchy_path AS (
    -- Base case: start at the top-level categories (no parent)
    SELECT
        id,
        parent_id,
        level_text,
        level_name,
        -- Store the path as we recurse down
        NULL::VARCHAR   AS category_name,
        NULL::INTEGER   AS category_id,
        NULL::VARCHAR   AS segment_name,
        NULL::INTEGER   AS segment_id
    FROM product_hierarchy
    WHERE parent_id IS NULL  -- Category level

    UNION ALL

    -- Recursive case: join children to their parent
    SELECT
        ph.id,
        ph.parent_id,
        ph.level_text,
        ph.level_name,
        CASE WHEN hp.level_name = 'Category' THEN hp.level_text ELSE hp.category_name END,
        CASE WHEN hp.level_name = 'Category' THEN hp.id        ELSE hp.category_id   END,
        CASE WHEN hp.level_name = 'Segment'  THEN hp.level_text ELSE hp.segment_name END,
        CASE WHEN hp.level_name = 'Segment'  THEN hp.id        ELSE hp.segment_id   END
    FROM product_hierarchy ph
    JOIN hierarchy_path hp ON hp.id = ph.parent_id
),
-- Filter to leaf (Style) nodes only and join product_prices
product_details_rebuilt AS (
    SELECT
        pp.product_id,
        pp.price,
        CONCAT(hp.level_text, ' - ', hp.category_name, 's') AS product_name,
        hp.category_id,
        hp.segment_id,
        hp.id                                                 AS style_id,
        hp.category_name,
        hp.segment_name,
        hp.level_text                                         AS style_name
    FROM hierarchy_path hp
    JOIN product_prices pp ON pp.id = hp.id
    WHERE hp.level_name = 'Style'
)
SELECT * FROM product_details_rebuilt
ORDER BY category_id, segment_id, style_id;


-- ============================================================
-- REPORTING VIEW
-- Flat denormalized view joining sales + product_details
-- for direct consumption in BI tools (Power BI / Tableau).
-- ============================================================
CREATE OR REPLACE VIEW balanced_tree.vw_sales_detail AS
SELECT
    s.txn_id,
    s.start_txn_time,
    s.member,
    s.prod_id,
    pd.product_name,
    pd.category_name,
    pd.segment_name,
    pd.style_name,
    s.qty,
    s.price                                             AS listed_price,
    s.discount,
    ROUND(s.qty * s.price * s.discount / 100.0, 2)     AS discount_amount,
    ROUND(s.qty * s.price * (1 - s.discount/100.0), 2) AS net_revenue
FROM sales s
JOIN product_details pd ON pd.product_id = s.prod_id;
