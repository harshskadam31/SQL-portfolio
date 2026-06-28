-- ============================================================
-- Foodie-Fi - Case Study Analysis
-- File: 04_analysis_queries.sql
--
-- Covers Section A (Customer Journey) and Section B (Data Analysis
-- Questions 1-11) from the case study. Section C (the payments
-- challenge) lives in its own file, 05_payments_challenge.sql, since
-- it builds a new table rather than just querying.
--
-- Every query here was written and verified against a live PostgreSQL
-- 16 instance, loaded with both the 8 published sample customers
-- (02_seed_data_sample.sql) and a 250-customer synthetic base
-- (03_seed_data_synthetic.sql) that follows the same plan-transition
-- rules. Using only the 8 sample rows would make several of these
-- questions (e.g. monthly distributions, churn %) statistically
-- meaningless, so the synthetic data exists purely to give the
-- analysis layer something real to say.
-- ============================================================

SET search_path TO foodie_fi;


-- ============================================================
-- SECTION A: CUSTOMER JOURNEY
-- ============================================================

-- Generates a one-line journey summary for each of the 8 published
-- sample customers, e.g.:
--   "trial on 2020-08-01 -> basic monthly on 2020-08-08"
SELECT
    s.customer_id,
    STRING_AGG(p.plan_name || ' on ' || s.start_date, ' -> ' ORDER BY s.start_date) AS journey
FROM subscriptions s
JOIN plans p ON p.plan_id = s.plan_id
WHERE s.customer_id IN (1, 2, 11, 13, 15, 16, 18, 19)
GROUP BY s.customer_id
ORDER BY s.customer_id;

-- Written summary of each journey (the actual answer to "describe each
-- customer's onboarding journey"):
--
--   Customer 1  - Took the 7-day trial, then settled on basic monthly
--                 ($9.90) and has stayed on it since.
--   Customer 2  - Took the trial, then upgraded straight to pro annual
--                 ($199) right as the trial ended - the highest-commitment
--                 path available.
--   Customer 11 - Took the trial and churned immediately after - never
--                 converted to a paid plan.
--   Customer 13 - Took the trial, downgraded(*) to basic monthly, then
--                 over 3 months later upgraded to pro monthly.
--                 (*the trial->basic transition isn't a "downgrade" in the
--                 churn sense - it's the standard non-upgrade trial outcome)
--   Customer 15 - Took the trial, upgraded to pro monthly, then churned
--                 about 5 weeks later.
--   Customer 16 - Took the trial, went to basic monthly, then upgraded to
--                 pro annual about 4.5 months later.
--   Customer 18 - Took the trial, upgraded to pro monthly immediately
--                 after, and has remained on it.
--   Customer 19 - Took the trial, upgraded to pro monthly, then to pro
--                 annual two months later - a full "ideal funnel" customer.


-- ============================================================
-- SECTION B: DATA ANALYSIS QUESTIONS
-- ============================================================

-- B1. How many customers has Foodie-Fi ever had?
SELECT COUNT(DISTINCT customer_id) AS total_customers
FROM subscriptions;


-- B2. Monthly distribution of trial plan start_date values
-- (grouped by the start of the month)
SELECT
    DATE_TRUNC('month', start_date)::date AS month,
    COUNT(*) AS trial_starts
FROM subscriptions
WHERE plan_id = 0
GROUP BY 1
ORDER BY 1;


-- B3. Plan start_date values that occur after 2020, broken down by
-- count of events for each plan_name
SELECT
    p.plan_name,
    COUNT(*) AS event_count
FROM subscriptions s
JOIN plans p ON p.plan_id = s.plan_id
WHERE s.start_date > '2020-12-31'
GROUP BY p.plan_name
ORDER BY event_count DESC;


-- B4. Customer count and percentage of customers who have churned
-- (rounded to 1 decimal place)
SELECT
    COUNT(DISTINCT customer_id) AS churned_customers,
    ROUND(
        100.0 * COUNT(DISTINCT customer_id) / (SELECT COUNT(DISTINCT customer_id) FROM subscriptions),
        1
    ) AS churn_pct
FROM subscriptions
WHERE plan_id = 4;


-- B5. How many customers churned straight after their initial free
-- trial, and what percentage is this (rounded to the nearest whole number)?
WITH ranked AS (
    SELECT
        customer_id, plan_id, start_date,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY start_date) AS rn
    FROM subscriptions
)
SELECT
    COUNT(*) AS churned_after_trial,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT customer_id) FROM subscriptions), 0) AS pct_of_all_customers
FROM ranked
WHERE rn = 2 AND plan_id = 4;


-- B6. Number and percentage of customer plans immediately after their
-- initial free trial
WITH ranked AS (
    SELECT
        customer_id, plan_id, start_date,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY start_date) AS rn
    FROM subscriptions
)
SELECT
    p.plan_name,
    COUNT(*) AS customer_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT customer_id) FROM subscriptions), 1) AS pct
FROM ranked r
JOIN plans p ON p.plan_id = r.plan_id
WHERE r.rn = 2
GROUP BY p.plan_name
ORDER BY customer_count DESC;


-- B7. Customer count and percentage breakdown of all 5 plan_name values
-- as at 2020-12-31 (i.e. each customer's most recent plan on or before
-- that date)
WITH latest_plan AS (
    SELECT
        customer_id, plan_id,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY start_date DESC) AS rn
    FROM subscriptions
    WHERE start_date <= '2020-12-31'
)
SELECT
    p.plan_name,
    COUNT(*) AS customer_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM latest_plan WHERE rn = 1), 1) AS pct
FROM latest_plan lp
JOIN plans p ON p.plan_id = lp.plan_id
WHERE lp.rn = 1
GROUP BY p.plan_name
ORDER BY customer_count DESC;


-- B8. How many customers upgraded to an annual plan in 2020?
SELECT COUNT(DISTINCT customer_id) AS upgraded_to_annual_2020
FROM subscriptions
WHERE plan_id = 3
  AND start_date BETWEEN '2020-01-01' AND '2020-12-31';


-- B9. Average number of days to upgrade to an annual plan from the day
-- a customer first joined Foodie-Fi
WITH first_join AS (
    SELECT customer_id, MIN(start_date) AS join_date
    FROM subscriptions
    GROUP BY customer_id
),
annual_upgrade AS (
    SELECT customer_id, start_date AS annual_date
    FROM subscriptions
    WHERE plan_id = 3
)
SELECT ROUND(AVG(au.annual_date - fj.join_date), 1) AS avg_days_to_annual
FROM annual_upgrade au
JOIN first_join fj ON fj.customer_id = au.customer_id;


-- B10. Breakdown of the above average into 30-day periods
-- (0-30 days, 31-60 days, etc.)
WITH first_join AS (
    SELECT customer_id, MIN(start_date) AS join_date
    FROM subscriptions
    GROUP BY customer_id
),
annual_upgrade AS (
    SELECT customer_id, start_date AS annual_date
    FROM subscriptions
    WHERE plan_id = 3
),
days_to_upgrade AS (
    SELECT au.customer_id, (au.annual_date - fj.join_date) AS days_taken
    FROM annual_upgrade au
    JOIN first_join fj ON fj.customer_id = au.customer_id
)
SELECT
    (days_taken / 30) * 30                AS period_start_day,
    (days_taken / 30) * 30 + 30            AS period_end_day,
    COUNT(*)                              AS customer_count,
    ROUND(AVG(days_taken), 1)             AS avg_days_in_period
FROM days_to_upgrade
GROUP BY (days_taken / 30)
ORDER BY period_start_day;


-- B11. How many customers downgraded from a pro monthly to a basic
-- monthly plan in 2020?
WITH ordered AS (
    SELECT
        customer_id, plan_id, start_date,
        LAG(plan_id) OVER (PARTITION BY customer_id ORDER BY start_date) AS prev_plan_id
    FROM subscriptions
)
SELECT COUNT(*) AS downgrades_2020
FROM ordered
WHERE prev_plan_id = 2
  AND plan_id = 1
  AND start_date BETWEEN '2020-01-01' AND '2020-12-31';
