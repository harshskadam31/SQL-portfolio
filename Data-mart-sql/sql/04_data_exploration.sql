-- ============================================================
-- Data Mart - Section 2: Data Exploration
-- File: 04_data_exploration.sql
--
-- All queries run against clean_weekly_sales (built in
-- 03_clean_data.sql), never the raw weekly_sales table.
-- ============================================================

SET search_path TO data_mart;


-- Q1. What day of the week is used for each week_date value?
SELECT DISTINCT TO_CHAR(week_date, 'Day') AS day_of_week
FROM clean_weekly_sales;
-- Result: every week_date falls on a Monday.


-- Q2. What range of week numbers are missing from the dataset?
SELECT generate_series(1, 53) AS week_number
EXCEPT
SELECT DISTINCT week_number FROM clean_weekly_sales
ORDER BY 1;
-- Result: weeks 1 and 53 are missing in every year - these are the
-- partial first/last weeks of the calendar year and were dropped from
-- the source data.


-- Q3. How many total transactions were there for each year?
SELECT calendar_year, SUM(transactions) AS total_transactions
FROM clean_weekly_sales
GROUP BY calendar_year
ORDER BY calendar_year;


-- Q4. What is the total sales for each region for each month?
SELECT region, month_number, SUM(sales) AS total_sales
FROM clean_weekly_sales
GROUP BY region, month_number
ORDER BY region, month_number;


-- Q5. What is the total count of transactions for each platform?
SELECT platform, SUM(transactions) AS total_transactions
FROM clean_weekly_sales
GROUP BY platform
ORDER BY total_transactions DESC;


-- Q6. What is the percentage of sales for Retail vs Shopify for each month?
WITH monthly AS (
    SELECT calendar_year, month_number, platform, SUM(sales) AS sales
    FROM clean_weekly_sales
    GROUP BY calendar_year, month_number, platform
)
SELECT
    calendar_year,
    month_number,
    ROUND(100.0 * SUM(CASE WHEN platform = 'Retail'  THEN sales ELSE 0 END) / SUM(sales), 1) AS retail_pct,
    ROUND(100.0 * SUM(CASE WHEN platform = 'Shopify' THEN sales ELSE 0 END) / SUM(sales), 1) AS shopify_pct
FROM monthly
GROUP BY calendar_year, month_number
ORDER BY calendar_year, month_number;


-- Q7. What is the percentage of sales by demographic for each year?
SELECT
    calendar_year,
    demographic,
    ROUND(100.0 * SUM(sales) / SUM(SUM(sales)) OVER (PARTITION BY calendar_year), 1) AS pct_of_sales
FROM clean_weekly_sales
GROUP BY calendar_year, demographic
ORDER BY calendar_year, demographic;


-- Q8. Which age_band and demographic values contribute the most to
-- Retail sales? (excluding 'unknown' - this question is about
-- identifying who Data Mart's customers actually are, which an
-- 'unknown' bucket can't answer)
SELECT age_band, demographic, SUM(sales) AS total_sales
FROM clean_weekly_sales
WHERE platform = 'Retail' AND age_band != 'unknown' AND demographic != 'unknown'
GROUP BY age_band, demographic
ORDER BY total_sales DESC;


-- Q9. Can the avg_transaction column be used to find the average
-- transaction size for each year for Retail vs Shopify? If not, how
-- should it be calculated instead?
--
-- No - naively averaging the per-row avg_transaction column (AVG())
-- treats every row as equally weighted, regardless of how many actual
-- transactions that row represents. A row with 50,000 transactions and
-- a row with 5 transactions would count equally toward the average,
-- which is misleading. The CORRECT approach is a transactions-weighted
-- average: SUM(sales) / SUM(transactions). Both versions are shown
-- below for direct comparison - they happen to be close in this
-- dataset because each row is already a fairly granular weekly slice,
-- but the naive version is still conceptually wrong and would diverge
-- more on a coarser-grained or more skewed dataset.
SELECT
    calendar_year,
    platform,
    ROUND(AVG(avg_transaction), 2)             AS naive_avg_of_avg_transaction,  -- WRONG
    ROUND(SUM(sales) / SUM(transactions), 2)    AS correct_weighted_avg          -- CORRECT
FROM clean_weekly_sales
GROUP BY calendar_year, platform
ORDER BY calendar_year, platform;
