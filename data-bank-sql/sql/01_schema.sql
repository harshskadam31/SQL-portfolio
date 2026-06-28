-- ============================================================
-- Data Bank: Neo-Bank Customer & Data Storage Analytics
-- File: 01_schema.sql
-- Purpose: Defines all tables, constraints, and indexes
-- Author: Harsh
-- ============================================================

DROP SCHEMA IF EXISTS data_bank CASCADE;
CREATE SCHEMA data_bank;
SET search_path TO data_bank;

-- ------------------------------------------------------------
-- Table: regions
-- Geographic regions where Data Bank nodes are distributed
-- ------------------------------------------------------------
CREATE TABLE regions (
    region_id       SMALLINT PRIMARY KEY,
    region_name     VARCHAR(50) NOT NULL
);

-- ------------------------------------------------------------
-- Table: customer_nodes
-- Tracks which node each customer is assigned to over time.
-- Customers are periodically reallocated to different nodes
-- for security purposes. One customer can have many rows
-- (one per allocation period).
-- end_date = '9999-12-31' means currently active allocation.
-- ------------------------------------------------------------
CREATE TABLE customer_nodes (
    customer_id     INT NOT NULL,
    region_id       SMALLINT NOT NULL REFERENCES regions(region_id),
    node_id         SMALLINT NOT NULL CHECK (node_id BETWEEN 1 AND 5),
    start_date      DATE NOT NULL,
    end_date        DATE NOT NULL,
    CHECK (end_date >= start_date)
);

-- ------------------------------------------------------------
-- Table: customer_transactions
-- Every deposit, withdrawal, and purchase made by customers.
-- Deposits are positive cash inflows; withdrawals and purchases
-- reduce the customer's balance.
-- ------------------------------------------------------------
CREATE TABLE customer_transactions (
    customer_id     INT NOT NULL,
    txn_date        DATE NOT NULL,
    txn_type        VARCHAR(20) NOT NULL CHECK (txn_type IN ('deposit', 'withdrawal', 'purchase')),
    txn_amount      INT NOT NULL CHECK (txn_amount > 0)
);

-- ------------------------------------------------------------
-- Indexes to support common analytical query patterns
-- ------------------------------------------------------------
CREATE INDEX idx_nodes_customer    ON customer_nodes(customer_id);
CREATE INDEX idx_nodes_region      ON customer_nodes(region_id);
CREATE INDEX idx_nodes_dates       ON customer_nodes(start_date, end_date);
CREATE INDEX idx_txn_customer      ON customer_transactions(customer_id);
CREATE INDEX idx_txn_date          ON customer_transactions(txn_date);
CREATE INDEX idx_txn_type          ON customer_transactions(txn_type);
