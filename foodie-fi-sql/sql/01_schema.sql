-- ============================================================
-- Foodie-Fi - Schema
-- File: 01_schema.sql
--
-- Matches the case study's 2-table design exactly:
--   plans          - the 5 possible subscription plans (trial, basic
--                     monthly, pro monthly, pro annual, churn)
--   subscriptions  - one row per plan CHANGE for a customer (not one
--                     row per billing cycle) - start_date is the date
--                     a customer's plan_id changed to this value
-- ============================================================

DROP SCHEMA IF EXISTS foodie_fi CASCADE;
CREATE SCHEMA foodie_fi;
SET search_path TO foodie_fi;

CREATE TABLE plans (
    plan_id     SMALLINT PRIMARY KEY,
    plan_name   VARCHAR(20) NOT NULL,
    price       NUMERIC(6,2)  -- NULL for the 'churn' plan, by design
);

CREATE TABLE subscriptions (
    customer_id INTEGER NOT NULL,
    plan_id     SMALLINT NOT NULL REFERENCES plans(plan_id),
    start_date  DATE NOT NULL,
    PRIMARY KEY (customer_id, plan_id, start_date)
);

CREATE INDEX idx_subscriptions_customer ON subscriptions(customer_id);
CREATE INDEX idx_subscriptions_date     ON subscriptions(start_date);
