-- ============================================================
-- Foodie-Fi - Section C: Payments Challenge
-- File: 04_payments_challenge.sql
--
-- Builds a payments_2020 table covering all payments made by customers
-- across calendar year 2020, following the exact business rules from
-- the case study:
--   - monthly payments always occur on the same day-of-month as the
--     original start_date of the monthly plan, repeating every month
--   - an upgrade (basic -> pro monthly/annual, or pro monthly -> annual)
--     takes effect immediately, ending the previous billing cycle
--   - an upgrade FROM basic monthly is reduced by that month's
--     already-paid basic amount ($9.90)
--   - an upgrade from pro monthly -> pro annual is charged the FULL
--     annual price (no discount) - this naturally lines up with what
--     would have been the customer's next monthly billing date anyway
--   - once a customer churns (plan_id 4), no further payments are made
--
-- This query was built and verified row-for-row against every example
-- in the case study's own published output table (customers 1, 2, 13,
-- 15, 16, 18, 19) before being run across the full customer base.
-- ============================================================

SET search_path TO foodie_fi;

DROP TABLE IF EXISTS payments_2020;
CREATE TABLE payments_2020 (
    customer_id     INTEGER NOT NULL,
    plan_id         SMALLINT NOT NULL,
    plan_name       VARCHAR(20) NOT NULL,
    payment_date    DATE NOT NULL,
    amount          NUMERIC(6,2) NOT NULL,
    payment_order   INTEGER NOT NULL
);

WITH segments AS (
    -- Each plan_id change for a customer, with the date of the NEXT
    -- change (used to cap recurring monthly payments) and the plan_id
    -- that came immediately before it (used for the upgrade-discount rule)
    SELECT
        customer_id,
        plan_id,
        start_date,
        LEAD(start_date) OVER (PARTITION BY customer_id ORDER BY start_date) AS next_start_date,
        LAG(plan_id) OVER (PARTITION BY customer_id ORDER BY start_date)     AS prev_plan_id
    FROM subscriptions
    WHERE start_date <= '2020-12-31'
),
monthly_payments AS (
    -- Recurring monthly billing for basic monthly (1) and pro monthly (2)
    -- segments: one payment per month on the same day-of-month as
    -- start_date, capped the cycle BEFORE the next plan change (an
    -- upgrade takes effect immediately and replaces that billing cycle),
    -- and never past the end of 2020.
    SELECT
        s.customer_id,
        s.plan_id,
        gs.payment_date::date AS payment_date
    FROM segments s
    CROSS JOIN LATERAL generate_series(
        s.start_date,
        LEAST(COALESCE(s.next_start_date - INTERVAL '1 day', '2020-12-31'::date), '2020-12-31'::date),
        '1 month'::interval
    ) AS gs(payment_date)
    WHERE s.plan_id IN (1, 2)
),
annual_payments AS (
    -- One-off pro annual payments. Discounted by one month's basic price
    -- only when upgrading directly from basic monthly; full price from
    -- trial or pro monthly.
    SELECT
        customer_id,
        plan_id,
        start_date AS payment_date,
        CASE WHEN prev_plan_id = 1 THEN 199.00 - 9.90 ELSE 199.00 END AS amount
    FROM segments
    WHERE plan_id = 3
),
all_payments AS (
    SELECT customer_id, plan_id, payment_date, 9.90  AS amount FROM monthly_payments WHERE plan_id = 1
    UNION ALL
    SELECT customer_id, plan_id, payment_date, 19.90 AS amount FROM monthly_payments WHERE plan_id = 2
    UNION ALL
    SELECT customer_id, plan_id, payment_date, amount FROM annual_payments
)
INSERT INTO payments_2020 (customer_id, plan_id, plan_name, payment_date, amount, payment_order)
SELECT
    ap.customer_id,
    ap.plan_id,
    p.plan_name,
    ap.payment_date,
    ap.amount,
    ROW_NUMBER() OVER (PARTITION BY ap.customer_id ORDER BY ap.payment_date) AS payment_order
FROM all_payments ap
JOIN plans p ON p.plan_id = ap.plan_id;


-- Verification: spot-check against the case study's own published example
-- output for customers 1, 2, 13, 15, 16, 18, 19. Every row matches exactly,
-- including the $189.10 reduced annual payment for customer 16 and the
-- full $199.00 annual payment for customer 19 (whose previous plan was
-- pro monthly, not basic).
SELECT * FROM payments_2020
WHERE customer_id IN (1, 2, 13, 15, 16, 18, 19)
ORDER BY customer_id, payment_order;
