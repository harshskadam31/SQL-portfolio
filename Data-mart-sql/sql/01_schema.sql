-- ============================================================
-- Data Mart - Raw Schema
-- File: 01_schema.sql
--
-- A single raw table, exactly as given by the case study:
-- weekly_sales. week_date is intentionally stored as TEXT here (not
-- DATE) because the case study's own example data uses a D/M/YY style
-- string format ("9/9/20", "29/7/20") - converting it properly to a
-- real DATE type is the FIRST data cleaning step (Question 1), not
-- something to silently fix at the schema level.
-- ============================================================

DROP SCHEMA IF EXISTS data_mart CASCADE;
CREATE SCHEMA data_mart;
SET search_path TO data_mart;

CREATE TABLE weekly_sales (
    week_date      VARCHAR(10) NOT NULL,
    region         VARCHAR(20) NOT NULL,
    platform       VARCHAR(10) NOT NULL,
    segment        VARCHAR(10),          -- NULL is valid - cleaned to 'unknown' later
    customer_type  VARCHAR(10) NOT NULL,
    transactions    INTEGER NOT NULL,
    sales          NUMERIC(14, 2) NOT NULL
);
