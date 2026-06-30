-- ============================================================
-- Data Mart - Section 1: Data Cleansing
-- File: 03_clean_data.sql
--
-- Builds clean_weekly_sales from the raw weekly_sales table in a single
-- query, per the case study's exact requirements:
--   1. week_date converted from its raw D/M/YY string format to a
--      proper DATE
--   2. week_number added as the 2nd column - NOT Postgres's built-in
--      ISO week (which starts numbering from the first Thursday-
--      containing week and would NOT match), but the case study's own
--      explicit rule: day 1-7 of the year = week 1, day 8-14 = week 2,
--      etc. - i.e. CEIL(day_of_year / 7)
--   3. month_number added as the 3rd column
--   4. calendar_year added as the 4th column
--   5. age_band added right after segment, derived from the trailing
--      digit of segment (1 -> Young Adults, 2 -> Middle Aged, 3/4 ->
--      Retirees)
--   6. demographic added after age_band, derived from the leading
--      letter of segment (C -> Couples, F -> Families)
--   7. NULL segment values (and the resulting NULL age_band/demographic)
--      replaced with the literal string 'unknown'
--   8. avg_transaction added as sales / transactions, rounded to 2dp
-- ============================================================

SET search_path TO data_mart;

DROP TABLE IF EXISTS clean_weekly_sales;

CREATE TABLE clean_weekly_sales AS
SELECT
    TO_DATE(week_date, 'DD/MM/YY')                                     AS week_date,
    CEIL(EXTRACT(DOY FROM TO_DATE(week_date, 'DD/MM/YY')) / 7.0)::INT   AS week_number,
    EXTRACT(MONTH FROM TO_DATE(week_date, 'DD/MM/YY'))::INT             AS month_number,
    EXTRACT(YEAR  FROM TO_DATE(week_date, 'DD/MM/YY'))::INT             AS calendar_year,
    region,
    platform,
    COALESCE(segment, 'unknown')                                       AS segment,
    CASE
        WHEN segment IS NULL THEN 'unknown'
        WHEN RIGHT(segment, 1) = '1'        THEN 'Young Adults'
        WHEN RIGHT(segment, 1) = '2'        THEN 'Middle Aged'
        WHEN RIGHT(segment, 1) IN ('3','4') THEN 'Retirees'
        ELSE 'unknown'
    END                                                                 AS age_band,
    CASE
        WHEN segment IS NULL THEN 'unknown'
        WHEN LEFT(segment, 1) = 'C' THEN 'Couples'
        WHEN LEFT(segment, 1) = 'F' THEN 'Families'
        ELSE 'unknown'
    END                                                                 AS demographic,
    customer_type,
    transactions,
    sales,
    ROUND(sales / transactions, 2)                                     AS avg_transaction
FROM weekly_sales;

-- Helpful indexes for the analysis queries that follow
CREATE INDEX idx_clean_weekly_sales_date     ON clean_weekly_sales(week_date);
CREATE INDEX idx_clean_weekly_sales_region   ON clean_weekly_sales(region);
CREATE INDEX idx_clean_weekly_sales_platform ON clean_weekly_sales(platform);
