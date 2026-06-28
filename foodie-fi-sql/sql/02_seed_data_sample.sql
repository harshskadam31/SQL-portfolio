-- ============================================================
-- Foodie-Fi - Seed Data: plans + the 8 sample customers
-- File: 02_seed_data_sample.sql
--
-- The plans table and these 8 customers (1, 2, 11, 13, 15, 16, 18, 19)
-- are reproduced exactly as published in the case study itself - these
-- are the rows the "Customer Journey" question (Section A) refers to.
-- The full synthetic customer base is loaded separately in
-- 03_seed_data_synthetic.sql.
-- ============================================================

SET search_path TO foodie_fi;

INSERT INTO plans (plan_id, plan_name, price) VALUES
    (0, 'trial', 0),
    (1, 'basic monthly', 9.90),
    (2, 'pro monthly', 19.90),
    (3, 'pro annual', 199.00),
    (4, 'churn', NULL);

INSERT INTO subscriptions (customer_id, plan_id, start_date) VALUES
    (1,  0, '2020-08-01'),
    (1,  1, '2020-08-08'),
    (2,  0, '2020-09-20'),
    (2,  3, '2020-09-27'),
    (11, 0, '2020-11-19'),
    (11, 4, '2020-11-26'),
    (13, 0, '2020-12-15'),
    (13, 1, '2020-12-22'),
    (13, 2, '2021-03-29'),
    (15, 0, '2020-03-17'),
    (15, 2, '2020-03-24'),
    (15, 4, '2020-04-29'),
    (16, 0, '2020-05-31'),
    (16, 1, '2020-06-07'),
    (16, 3, '2020-10-21'),
    (18, 0, '2020-07-06'),
    (18, 2, '2020-07-13'),
    (19, 0, '2020-06-22'),
    (19, 2, '2020-06-29'),
    (19, 3, '2020-08-29');
