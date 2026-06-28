-- ============================================================
-- Data Bank: Customer & Data Storage Analytics
-- File: 03_analysis_queries.sql
-- Author: Harsh
--
-- All queries written and verified against the Data Bank schema
-- (01_schema.sql + 02_seed_data.sql). Organized into four
-- sections matching the case study structure, with increasing
-- complexity from basic aggregation through window functions,
-- CTEs, and financial modeling.
-- ============================================================

SET search_path TO data_bank;

-- ============================================================
-- SECTION A: CUSTOMER NODES EXPLORATION
-- Understanding how customers are distributed across nodes
-- and how frequently they get reallocated for security.
-- ============================================================

-- A1. How many unique nodes are there on the Data Bank system?
-- Nodes are numbered 1-5 and are the same across all regions.
SELECT
    COUNT(DISTINCT node_id) AS unique_nodes
FROM customer_nodes;


-- A2. What is the number of nodes per region?
-- Shows how many distinct nodes exist within each region.
SELECT
    r.region_name,
    COUNT(DISTINCT cn.node_id) AS node_count
FROM customer_nodes cn
JOIN regions r ON r.region_id = cn.region_id
GROUP BY r.region_name
ORDER BY r.region_name;


-- A3. How many customers are allocated to each region?
-- Each customer belongs to exactly one region (their home region).
SELECT
    r.region_name,
    COUNT(DISTINCT cn.customer_id) AS customer_count
FROM customer_nodes cn
JOIN regions r ON r.region_id = cn.region_id
GROUP BY r.region_name
ORDER BY customer_count DESC;


-- A4. How many days on average are customers reallocated to a different node?
-- Excludes the sentinel end_date (9999-12-31) which marks the current
-- active allocation — including it would massively inflate the average.
SELECT
    ROUND(AVG(end_date - start_date), 2) AS avg_reallocation_days
FROM customer_nodes
WHERE end_date <> '9999-12-31';


-- A5. Median, 80th and 95th percentile for reallocation days per region.
-- Uses PERCENTILE_CONT (continuous interpolation) which is standard
-- for financial and operational metrics where fractional days matter.
SELECT
    r.region_name,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY cn.end_date - cn.start_date) AS median_days,
    PERCENTILE_CONT(0.80) WITHIN GROUP (ORDER BY cn.end_date - cn.start_date) AS p80_days,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY cn.end_date - cn.start_date) AS p95_days
FROM customer_nodes cn
JOIN regions r ON r.region_id = cn.region_id
WHERE cn.end_date <> '9999-12-31'
GROUP BY r.region_name
ORDER BY r.region_name;


-- ============================================================
-- SECTION B: CUSTOMER TRANSACTIONS
-- Analysing deposit, withdrawal, and purchase behaviour.
-- ============================================================

-- B1. Unique count and total amount for each transaction type.
-- Simple baseline — how much volume does each transaction type generate?
SELECT
    txn_type,
    COUNT(*)            AS txn_count,
    SUM(txn_amount)     AS total_amount
FROM customer_transactions
GROUP BY txn_type
ORDER BY txn_type;


-- B2. Average total historical deposit counts and amounts for all customers.
-- First aggregates per customer, then averages across customers —
-- this gives per-customer averages, not a simple average of all deposits.
WITH customer_deposits AS (
    SELECT
        customer_id,
        COUNT(*)        AS deposit_count,
        SUM(txn_amount) AS total_deposited
    FROM customer_transactions
    WHERE txn_type = 'deposit'
    GROUP BY customer_id
)
SELECT
    ROUND(AVG(deposit_count), 2)    AS avg_deposit_count_per_customer,
    ROUND(AVG(total_deposited), 2)  AS avg_total_deposited_per_customer
FROM customer_deposits;


-- B3. For each month, how many customers make more than 1 deposit
-- AND either 1 purchase OR 1 withdrawal in that same month?
-- This identifies "engaged" customers who are actively using the platform.
WITH monthly_activity AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', txn_date)                               AS txn_month,
        COUNT(*) FILTER (WHERE txn_type = 'deposit')                AS deposit_count,
        COUNT(*) FILTER (WHERE txn_type = 'purchase')               AS purchase_count,
        COUNT(*) FILTER (WHERE txn_type = 'withdrawal')             AS withdrawal_count
    FROM customer_transactions
    GROUP BY customer_id, DATE_TRUNC('month', txn_date)
)
SELECT
    TO_CHAR(txn_month, 'Month YYYY')    AS month,
    COUNT(*)                            AS qualifying_customers
FROM monthly_activity
WHERE
    deposit_count > 1
    AND (purchase_count >= 1 OR withdrawal_count >= 1)
GROUP BY txn_month
ORDER BY txn_month;


-- B4. Closing balance for each customer at the end of each month.
-- Deposits increase balance; withdrawals and purchases decrease it.
-- Uses a running SUM window function over ordered months.
WITH monthly_net AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', txn_date) AS txn_month,
        SUM(
            CASE
                WHEN txn_type = 'deposit'               THEN  txn_amount
                WHEN txn_type IN ('withdrawal','purchase') THEN -txn_amount
            END
        ) AS net_amount
    FROM customer_transactions
    GROUP BY customer_id, DATE_TRUNC('month', txn_date)
)
SELECT
    customer_id,
    TO_CHAR(txn_month, 'Mon YYYY') AS month,
    SUM(net_amount) OVER (
        PARTITION BY customer_id
        ORDER BY txn_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS closing_balance
FROM monthly_net
ORDER BY customer_id, txn_month;


-- B5. What percentage of customers increased their closing balance by more than 5%?
-- Compares each customer's first and last monthly closing balance.
-- Only customers with at least 2 months of activity are included
-- (a customer with only one month has no "growth" to measure).
WITH monthly_net AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', txn_date) AS txn_month,
        SUM(
            CASE
                WHEN txn_type = 'deposit'                 THEN  txn_amount
                WHEN txn_type IN ('withdrawal','purchase') THEN -txn_amount
            END
        ) AS net_amount
    FROM customer_transactions
    GROUP BY customer_id, DATE_TRUNC('month', txn_date)
),
running_balance AS (
    SELECT
        customer_id,
        txn_month,
        SUM(net_amount) OVER (
            PARTITION BY customer_id
            ORDER BY txn_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS closing_balance,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY txn_month)         AS rn_asc,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY txn_month DESC)    AS rn_desc
    FROM monthly_net
),
first_last AS (
    SELECT
        customer_id,
        MAX(CASE WHEN rn_asc  = 1 THEN closing_balance END) AS first_balance,
        MAX(CASE WHEN rn_desc = 1 THEN closing_balance END) AS last_balance
    FROM running_balance
    GROUP BY customer_id
    HAVING COUNT(*) >= 2
)
SELECT
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE last_balance > first_balance * 1.05
        ) / COUNT(*),
        2
    ) AS pct_customers_grew_over_5
FROM first_last;


-- ============================================================
-- SECTION C: DATA ALLOCATION CHALLENGE
-- How much cloud storage to provision depends on which
-- allocation model the business chooses. Three options are
-- evaluated. Data allocation = balance (treat $ as GB).
-- ============================================================

-- C - Supporting CTE: running balance per transaction
-- Used across all three option calculations below.
-- This is the core building block: every transaction's
-- cumulative impact on each customer's balance.
WITH running_balance AS (
    SELECT
        customer_id,
        txn_date,
        txn_type,
        txn_amount,
        SUM(
            CASE
                WHEN txn_type = 'deposit'                 THEN  txn_amount
                WHEN txn_type IN ('withdrawal','purchase') THEN -txn_amount
            END
        ) OVER (
            PARTITION BY customer_id
            ORDER BY txn_date, txn_type
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_balance
    FROM customer_transactions
)
SELECT customer_id, txn_date, running_balance
FROM running_balance
ORDER BY customer_id, txn_date
LIMIT 20; -- preview only


-- C - Option 1: Data allocated based on closing balance at END of previous month.
-- If a customer's closing balance is negative, they get 0 allocation
-- (you can't provision negative storage).
WITH monthly_net AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', txn_date) AS txn_month,
        SUM(
            CASE
                WHEN txn_type = 'deposit'                 THEN  txn_amount
                WHEN txn_type IN ('withdrawal','purchase') THEN -txn_amount
            END
        ) AS net_amount
    FROM customer_transactions
    GROUP BY customer_id, DATE_TRUNC('month', txn_date)
),
closing_balance AS (
    SELECT
        customer_id,
        txn_month,
        SUM(net_amount) OVER (
            PARTITION BY customer_id
            ORDER BY txn_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS closing_balance
    FROM monthly_net
),
-- Shift closing balance forward by 1 month to get "previous month's balance"
allocation AS (
    SELECT
        customer_id,
        txn_month + INTERVAL '1 month'          AS allocation_month,
        GREATEST(closing_balance, 0)            AS data_allocated
    FROM closing_balance
)
SELECT
    TO_CHAR(allocation_month, 'Mon YYYY')   AS month,
    SUM(data_allocated)                     AS total_data_required_gb
FROM allocation
GROUP BY allocation_month
ORDER BY allocation_month;


-- C - Option 2: Data allocated based on average running balance in previous 30 days.
-- More dynamic — rewards customers who maintain high balances consistently,
-- not just at month end (which could be gamed by a single large deposit).
WITH running_balance AS (
    SELECT
        customer_id,
        txn_date,
        SUM(
            CASE
                WHEN txn_type = 'deposit'                 THEN  txn_amount
                WHEN txn_type IN ('withdrawal','purchase') THEN -txn_amount
            END
        ) OVER (
            PARTITION BY customer_id
            ORDER BY txn_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS balance
    FROM customer_transactions
),
monthly_avg AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', txn_date)   AS txn_month,
        AVG(balance)                    AS avg_balance_30d
    FROM running_balance
    GROUP BY customer_id, DATE_TRUNC('month', txn_date)
)
SELECT
    TO_CHAR(txn_month, 'Mon YYYY')          AS month,
    SUM(GREATEST(avg_balance_30d, 0))       AS total_data_required_gb
FROM monthly_avg
GROUP BY txn_month
ORDER BY txn_month;


-- C - Option 3: Data updated in real time — balance at every transaction point.
-- Most accurate but most expensive to provision since it changes constantly.
-- We summarize as the maximum data needed at any point within each month.
WITH running_balance AS (
    SELECT
        customer_id,
        txn_date,
        SUM(
            CASE
                WHEN txn_type = 'deposit'                 THEN  txn_amount
                WHEN txn_type IN ('withdrawal','purchase') THEN -txn_amount
            END
        ) OVER (
            PARTITION BY customer_id
            ORDER BY txn_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS balance
    FROM customer_transactions
)
SELECT
    TO_CHAR(DATE_TRUNC('month', txn_date), 'Mon YYYY') AS month,
    SUM(GREATEST(balance, 0))                           AS total_data_required_gb
FROM running_balance
GROUP BY DATE_TRUNC('month', txn_date)
ORDER BY DATE_TRUNC('month', txn_date);


-- C - Comparison summary: all three options side by side.
-- This is the most useful output for the business — one table
-- showing what each option costs in storage, per month.
WITH monthly_net AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', txn_date) AS txn_month,
        SUM(
            CASE
                WHEN txn_type = 'deposit'                 THEN  txn_amount
                WHEN txn_type IN ('withdrawal','purchase') THEN -txn_amount
            END
        ) AS net_amount
    FROM customer_transactions
    GROUP BY customer_id, DATE_TRUNC('month', txn_date)
),
closing AS (
    SELECT
        customer_id,
        txn_month,
        SUM(net_amount) OVER (
            PARTITION BY customer_id ORDER BY txn_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS closing_balance
    FROM monthly_net
),
option1 AS (
    SELECT
        txn_month + INTERVAL '1 month' AS month,
        SUM(GREATEST(closing_balance, 0)) AS opt1_data
    FROM closing
    GROUP BY txn_month + INTERVAL '1 month'
),
running AS (
    SELECT
        customer_id,
        txn_date,
        SUM(
            CASE
                WHEN txn_type = 'deposit'                 THEN  txn_amount
                WHEN txn_type IN ('withdrawal','purchase') THEN -txn_amount
            END
        ) OVER (
            PARTITION BY customer_id ORDER BY txn_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS balance
    FROM customer_transactions
),
option2 AS (
    SELECT
        DATE_TRUNC('month', txn_date) AS month,
        SUM(GREATEST(AVG(balance), 0)) AS opt2_data
    FROM running
    GROUP BY DATE_TRUNC('month', txn_date)
),
option3 AS (
    SELECT
        DATE_TRUNC('month', txn_date) AS month,
        SUM(GREATEST(balance, 0)) AS opt3_data
    FROM running
    GROUP BY DATE_TRUNC('month', txn_date)
)
SELECT
    TO_CHAR(o1.month, 'Mon YYYY')   AS month,
    o1.opt1_data                    AS option_1_prev_month_end,
    o2.opt2_data                    AS option_2_avg_30d,
    o3.opt3_data                    AS option_3_realtime
FROM option1 o1
JOIN option2 o2 ON o2.month = o1.month
JOIN option3 o3 ON o3.month = o1.month
ORDER BY o1.month;


-- ============================================================
-- SECTION D: EXTRA CHALLENGE — DAILY COMPOUND INTEREST
-- Annual rate: 6%. Data allocation grows daily based on
-- interest earned on positive balances. Two calculations:
-- simple (no compounding) and compound (daily compounding).
-- ============================================================

-- D - Daily interest on running balance, non-compounding.
-- Interest = balance * (0.06 / 365) per day.
-- Only positive balances earn interest (negative = no reward).
WITH running_balance AS (
    SELECT
        customer_id,
        txn_date,
        SUM(
            CASE
                WHEN txn_type = 'deposit'                 THEN  txn_amount
                WHEN txn_type IN ('withdrawal','purchase') THEN -txn_amount
            END
        ) OVER (
            PARTITION BY customer_id
            ORDER BY txn_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS balance
    FROM customer_transactions
),
daily_interest AS (
    SELECT
        customer_id,
        txn_date,
        balance,
        GREATEST(balance, 0) * (0.06 / 365.0) AS daily_interest_earned
    FROM running_balance
),
monthly_interest AS (
    SELECT
        DATE_TRUNC('month', txn_date)   AS txn_month,
        SUM(daily_interest_earned)      AS total_interest_earned
    FROM daily_interest
    GROUP BY DATE_TRUNC('month', txn_date)
)
SELECT
    TO_CHAR(txn_month, 'Mon YYYY')          AS month,
    ROUND(total_interest_earned::NUMERIC, 2) AS interest_earned_simple,
    ROUND(
        SUM(total_interest_earned) OVER (ORDER BY txn_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::NUMERIC,
        2
    )                                        AS cumulative_interest
FROM monthly_interest
ORDER BY txn_month;


-- D - Daily COMPOUND interest.
-- Each day's interest is added to the balance before next day's calculation.
-- Effective daily rate = (1 + 0.06)^(1/365) - 1
-- For a short 4-month window, compounding vs simple won't differ dramatically,
-- but the formula is correct for any window length.
WITH running_balance AS (
    SELECT
        customer_id,
        txn_date,
        SUM(
            CASE
                WHEN txn_type = 'deposit'                 THEN  txn_amount
                WHEN txn_type IN ('withdrawal','purchase') THEN -txn_amount
            END
        ) OVER (
            PARTITION BY customer_id
            ORDER BY txn_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS balance
    FROM customer_transactions
),
compound_daily AS (
    SELECT
        customer_id,
        txn_date,
        balance,
        -- daily compounding: balance * ((1.06)^(1/365) - 1)
        GREATEST(balance, 0) * (POWER(1.06, 1.0/365.0) - 1) AS compound_interest_daily
    FROM running_balance
)
SELECT
    TO_CHAR(DATE_TRUNC('month', txn_date), 'Mon YYYY') AS month,
    ROUND(SUM(compound_interest_daily)::NUMERIC, 2)    AS compound_interest_earned,
    ROUND(SUM(GREATEST(balance, 0))::NUMERIC, 2)       AS total_positive_balance
FROM compound_daily
GROUP BY DATE_TRUNC('month', txn_date)
ORDER BY DATE_TRUNC('month', txn_date);


-- ============================================================
-- REPORTING VIEW
-- Flattened view for BI tool consumption (Power BI / Tableau).
-- Joins all three tables into one clean, analysis-ready layer.
-- ============================================================

CREATE OR REPLACE VIEW data_bank.vw_customer_summary AS
SELECT
    ct.customer_id,
    r.region_name,
    cn.node_id,
    cn.start_date           AS node_start,
    cn.end_date             AS node_end,
    ct.txn_date,
    ct.txn_type,
    ct.txn_amount,
    CASE
        WHEN ct.txn_type = 'deposit'                 THEN  ct.txn_amount
        WHEN ct.txn_type IN ('withdrawal','purchase') THEN -ct.txn_amount
    END                     AS signed_amount
FROM customer_transactions ct
JOIN customer_nodes cn  ON cn.customer_id = ct.customer_id
                       AND cn.end_date = '9999-12-31'   -- current node only
JOIN regions r          ON r.region_id = cn.region_id;
