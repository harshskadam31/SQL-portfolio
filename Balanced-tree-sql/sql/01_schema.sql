-- ============================================================
-- Balanced Tree Clothing Co.: Sales & Merchandising Analytics
-- File: 01_schema.sql
-- Purpose: Defines all tables, constraints, and indexes
-- Author: Harsh
-- ============================================================

DROP SCHEMA IF EXISTS balanced_tree CASCADE;
CREATE SCHEMA balanced_tree;
SET search_path TO balanced_tree;

-- ------------------------------------------------------------
-- Table: product_hierarchy
-- Recursive self-referencing table that stores the 3-level
-- product taxonomy: Category → Segment → Style.
-- parent_id is NULL for top-level category nodes.
-- Used in the bonus challenge to reconstruct product_details
-- using a recursive CTE.
-- ------------------------------------------------------------
CREATE TABLE product_hierarchy (
    id          INTEGER PRIMARY KEY,
    parent_id   INTEGER REFERENCES product_hierarchy(id),
    level_text  VARCHAR(30) NOT NULL,
    level_name  VARCHAR(20) NOT NULL CHECK (level_name IN ('Category', 'Segment', 'Style'))
);

-- ------------------------------------------------------------
-- Table: product_prices
-- Maps style-level hierarchy IDs to product_id codes and prices.
-- product_id is a 6-character alphanumeric code used in sales.
-- ------------------------------------------------------------
CREATE TABLE product_prices (
    id          INTEGER PRIMARY KEY REFERENCES product_hierarchy(id),
    product_id  VARCHAR(10) NOT NULL UNIQUE,
    price       INTEGER NOT NULL CHECK (price > 0)
);

-- ------------------------------------------------------------
-- Table: product_details
-- Denormalized product reference table — one row per product
-- with all hierarchy levels flattened for easy joins to sales.
-- In practice this is derived from product_hierarchy +
-- product_prices (see bonus challenge query).
-- ------------------------------------------------------------
CREATE TABLE product_details (
    product_id      VARCHAR(10) PRIMARY KEY,
    price           INTEGER NOT NULL CHECK (price > 0),
    product_name    VARCHAR(60) NOT NULL,
    category_id     INTEGER NOT NULL,
    segment_id      INTEGER NOT NULL,
    style_id        INTEGER NOT NULL,
    category_name   VARCHAR(20) NOT NULL,
    segment_name    VARCHAR(20) NOT NULL,
    style_name      VARCHAR(30) NOT NULL
);

-- ------------------------------------------------------------
-- Table: sales
-- Core fact table. One row per product line item per transaction.
-- A single transaction (txn_id) can have multiple rows —
-- one for each product purchased.
-- discount is stored as an integer percentage (e.g. 17 = 17%).
-- member = true means the customer is a loyalty member.
-- ------------------------------------------------------------
CREATE TABLE sales (
    prod_id         VARCHAR(10) NOT NULL REFERENCES product_details(product_id),
    qty             INTEGER NOT NULL CHECK (qty > 0),
    price           INTEGER NOT NULL CHECK (price > 0),
    discount        INTEGER NOT NULL CHECK (discount BETWEEN 0 AND 100),
    member          BOOLEAN NOT NULL,
    txn_id          VARCHAR(10) NOT NULL,
    start_txn_time  TIMESTAMP NOT NULL
);

-- ------------------------------------------------------------
-- Indexes
-- ------------------------------------------------------------
CREATE INDEX idx_sales_prod     ON sales(prod_id);
CREATE INDEX idx_sales_txn      ON sales(txn_id);
CREATE INDEX idx_sales_time     ON sales(start_txn_time);
CREATE INDEX idx_sales_member   ON sales(member);
