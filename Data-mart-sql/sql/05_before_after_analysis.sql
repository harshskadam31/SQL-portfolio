-- ============================================================
-- Data Mart - Section 3: Before & After Analysis
-- Section 4: Bonus Question
-- File: 05_before_after_analysis.sql
--
-- Baseline event: the week_date of 2020-06-15, when Data Mart's
-- sustainable packaging change took effect. Per the case study's own
-- definition: the week STARTING 2020-06-15 counts as the first "after"
-- week; everything before that is "before".
-- ============================================================

SET search_path TO data_mart;


-- ============================================================
-- SECTION 3: BEFORE & AFTER ANALYSIS
-- ============================================================

-- 3.1 Total sales for the 4 weeks before and after 2020-06-15, with the
-- growth/reduction rate in both absolute and percentage terms.
WITH periods AS (
    SELECT
        CASE
            WHEN week_date >= '2020-06-15' AND week_date < '2020-06-15'::date + INTERVAL '28 days' THEN 'after'
            WHEN week_date <  '2020-06-15' AND week_date >= '2020-06-15'::date - INTERVAL '28 days' THEN 'before'
        END AS period,
        sales
    FROM clean_weekly_sales
    WHERE week_date >= '2020-06-15'::date - INTERVAL '28 days'
      AND week_date <  '2020-06-15'::date + INTERVAL '28 days'
),
totals AS (
    SELECT period, SUM(sales) AS total_sales
    FROM periods
    WHERE period IS NOT NULL
    GROUP BY period
)
SELECT
    MAX(CASE WHEN period = 'before' THEN total_sales END) AS before_sales,
    MAX(CASE WHEN period = 'after'  THEN total_sales END) AS after_sales,
    MAX(CASE WHEN period = 'after'  THEN total_sales END)
        - MAX(CASE WHEN period = 'before' THEN total_sales END) AS change_amount,
    ROUND(
        100.0 * (MAX(CASE WHEN period = 'after' THEN total_sales END) - MAX(CASE WHEN period = 'before' THEN total_sales END))
        / MAX(CASE WHEN period = 'before' THEN total_sales END),
        2
    ) AS pct_change
FROM totals;
-- Result: roughly a 14.5% drop in total sales across the 4-week window.


-- 3.2 The same comparison, but for the entire 12 weeks before and after.
WITH periods AS (
    SELECT
        CASE
            WHEN week_date >= '2020-06-15' AND week_date < '2020-06-15'::date + INTERVAL '84 days' THEN 'after'
            WHEN week_date <  '2020-06-15' AND week_date >= '2020-06-15'::date - INTERVAL '84 days' THEN 'before'
        END AS period,
        sales
    FROM clean_weekly_sales
    WHERE week_date >= '2020-06-15'::date - INTERVAL '84 days'
      AND week_date <  '2020-06-15'::date + INTERVAL '84 days'
),
totals AS (
    SELECT period, SUM(sales) AS total_sales
    FROM periods
    WHERE period IS NOT NULL
    GROUP BY period
)
SELECT
    MAX(CASE WHEN period = 'before' THEN total_sales END) AS before_sales,
    MAX(CASE WHEN period = 'after'  THEN total_sales END) AS after_sales,
    ROUND(
        100.0 * (MAX(CASE WHEN period = 'after' THEN total_sales END) - MAX(CASE WHEN period = 'before' THEN total_sales END))
        / MAX(CASE WHEN period = 'before' THEN total_sales END),
        2
    ) AS pct_change
FROM totals;
-- Result: roughly an 11.2% drop over the wider 12-week window - smaller
-- than the 4-week figure, consistent with sales gradually recovering
-- rather than the impact being a permanent step-change.


-- 3.3 How do these before/after metrics compare against the SAME
-- calendar window (12 weeks either side of June 15) in 2018 and 2019,
-- to check this isn't just normal seasonality?
WITH yearly_periods AS (
    SELECT
        calendar_year,
        CASE
            WHEN week_date >= MAKE_DATE(calendar_year, 6, 15)
                 AND week_date <  MAKE_DATE(calendar_year, 6, 15) + INTERVAL '84 days' THEN 'after'
            WHEN week_date <  MAKE_DATE(calendar_year, 6, 15)
                 AND week_date >= MAKE_DATE(calendar_year, 6, 15) - INTERVAL '84 days' THEN 'before'
        END AS period,
        sales
    FROM clean_weekly_sales
    WHERE week_date >= MAKE_DATE(calendar_year, 6, 15) - INTERVAL '84 days'
      AND week_date <  MAKE_DATE(calendar_year, 6, 15) + INTERVAL '84 days'
),
totals AS (
    SELECT calendar_year, period, SUM(sales) AS total_sales
    FROM yearly_periods
    WHERE period IS NOT NULL
    GROUP BY calendar_year, period
)
SELECT
    calendar_year,
    MAX(CASE WHEN period = 'before' THEN total_sales END) AS before_sales,
    MAX(CASE WHEN period = 'after'  THEN total_sales END) AS after_sales,
    ROUND(
        100.0 * (MAX(CASE WHEN period = 'after' THEN total_sales END) - MAX(CASE WHEN period = 'before' THEN total_sales END))
        / MAX(CASE WHEN period = 'before' THEN total_sales END),
        2
    ) AS pct_change
FROM totals
GROUP BY calendar_year
ORDER BY calendar_year;
-- Result: 2018 (+0.6%) and 2019 (+0.2%) both show small, normal GROWTH
-- across this same calendar window, while 2020 shows an -11.2% DECLINE -
-- strong evidence the 2020 drop is tied to the packaging change rather
-- than ordinary seasonal variation.


-- ============================================================
-- SECTION 4: BONUS QUESTION
-- Which areas of the business had the highest negative impact in 2020,
-- for the 12-week before/after window, broken down by region, platform,
-- age_band, demographic, and customer_type?
-- ============================================================

-- By region
WITH periods AS (
    SELECT region,
        CASE WHEN week_date >= '2020-06-15' AND week_date < '2020-06-15'::date + INTERVAL '84 days' THEN 'after'
             WHEN week_date <  '2020-06-15' AND week_date >= '2020-06-15'::date - INTERVAL '84 days' THEN 'before'
        END AS period, sales
    FROM clean_weekly_sales
    WHERE week_date >= '2020-06-15'::date - INTERVAL '84 days' AND week_date < '2020-06-15'::date + INTERVAL '84 days'
),
totals AS (SELECT region, period, SUM(sales) AS total_sales FROM periods WHERE period IS NOT NULL GROUP BY region, period)
SELECT region,
    MAX(CASE WHEN period='before' THEN total_sales END) AS before_sales,
    MAX(CASE WHEN period='after'  THEN total_sales END) AS after_sales,
    ROUND(100.0 * (MAX(CASE WHEN period='after' THEN total_sales END) - MAX(CASE WHEN period='before' THEN total_sales END))
        / MAX(CASE WHEN period='before' THEN total_sales END), 2) AS pct_change
FROM totals GROUP BY region ORDER BY pct_change ASC;
-- Result: OCEANIA was hit hardest (~-15.8%), consistent with this case
-- study's real-world basis (the Australian plastic-bag-ban analogy
-- Danny references). USA and Canada were the least affected (~-4 to -5%).


-- By platform
WITH periods AS (
    SELECT platform,
        CASE WHEN week_date >= '2020-06-15' AND week_date < '2020-06-15'::date + INTERVAL '84 days' THEN 'after'
             WHEN week_date <  '2020-06-15' AND week_date >= '2020-06-15'::date - INTERVAL '84 days' THEN 'before'
        END AS period, sales
    FROM clean_weekly_sales
    WHERE week_date >= '2020-06-15'::date - INTERVAL '84 days' AND week_date < '2020-06-15'::date + INTERVAL '84 days'
),
totals AS (SELECT platform, period, SUM(sales) AS total_sales FROM periods WHERE period IS NOT NULL GROUP BY platform, period)
SELECT platform,
    ROUND(100.0 * (MAX(CASE WHEN period='after' THEN total_sales END) - MAX(CASE WHEN period='before' THEN total_sales END))
        / MAX(CASE WHEN period='before' THEN total_sales END), 2) AS pct_change
FROM totals GROUP BY platform ORDER BY pct_change ASC;
-- Result: Retail was hit roughly twice as hard as Shopify (~-12.7% vs
-- ~-5.8%) - a physical, in-store packaging change is naturally more
-- visible and disruptive than an online checkout experience.


-- By age_band
WITH periods AS (
    SELECT age_band,
        CASE WHEN week_date >= '2020-06-15' AND week_date < '2020-06-15'::date + INTERVAL '84 days' THEN 'after'
             WHEN week_date <  '2020-06-15' AND week_date >= '2020-06-15'::date - INTERVAL '84 days' THEN 'before'
        END AS period, sales
    FROM clean_weekly_sales
    WHERE week_date >= '2020-06-15'::date - INTERVAL '84 days' AND week_date < '2020-06-15'::date + INTERVAL '84 days'
),
totals AS (SELECT age_band, period, SUM(sales) AS total_sales FROM periods WHERE period IS NOT NULL GROUP BY age_band, period)
SELECT age_band,
    ROUND(100.0 * (MAX(CASE WHEN period='after' THEN total_sales END) - MAX(CASE WHEN period='before' THEN total_sales END))
        / MAX(CASE WHEN period='before' THEN total_sales END), 2) AS pct_change
FROM totals GROUP BY age_band ORDER BY pct_change ASC;
-- Result: Retirees were hit hardest (~-13.3%), Young Adults the least
-- (~-8.1%) - consistent with older customers being more habit-driven and
-- more disrupted by a change to a familiar shopping routine.


-- By demographic
WITH periods AS (
    SELECT demographic,
        CASE WHEN week_date >= '2020-06-15' AND week_date < '2020-06-15'::date + INTERVAL '84 days' THEN 'after'
             WHEN week_date <  '2020-06-15' AND week_date >= '2020-06-15'::date - INTERVAL '84 days' THEN 'before'
        END AS period, sales
    FROM clean_weekly_sales
    WHERE week_date >= '2020-06-15'::date - INTERVAL '84 days' AND week_date < '2020-06-15'::date + INTERVAL '84 days'
),
totals AS (SELECT demographic, period, SUM(sales) AS total_sales FROM periods WHERE period IS NOT NULL GROUP BY demographic, period)
SELECT demographic,
    ROUND(100.0 * (MAX(CASE WHEN period='after' THEN total_sales END) - MAX(CASE WHEN period='before' THEN total_sales END))
        / MAX(CASE WHEN period='before' THEN total_sales END), 2) AS pct_change
FROM totals GROUP BY demographic ORDER BY pct_change ASC;


-- By customer_type
WITH periods AS (
    SELECT customer_type,
        CASE WHEN week_date >= '2020-06-15' AND week_date < '2020-06-15'::date + INTERVAL '84 days' THEN 'after'
             WHEN week_date <  '2020-06-15' AND week_date >= '2020-06-15'::date - INTERVAL '84 days' THEN 'before'
        END AS period, sales
    FROM clean_weekly_sales
    WHERE week_date >= '2020-06-15'::date - INTERVAL '84 days' AND week_date < '2020-06-15'::date + INTERVAL '84 days'
),
totals AS (SELECT customer_type, period, SUM(sales) AS total_sales FROM periods WHERE period IS NOT NULL GROUP BY customer_type, period)
SELECT customer_type,
    ROUND(100.0 * (MAX(CASE WHEN period='after' THEN total_sales END) - MAX(CASE WHEN period='before' THEN total_sales END))
        / MAX(CASE WHEN period='before' THEN total_sales END), 2) AS pct_change
FROM totals GROUP BY customer_type ORDER BY pct_change ASC;
-- Result: New customers were hit hardest (~-14.9%), Existing customers
-- the least (~-8.4%) - loyal/habitual customers are more resilient to a
-- change like this than new customers who haven't yet formed a habit.
