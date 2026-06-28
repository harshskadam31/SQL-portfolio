-- ============================================================
-- FlavorMetrics: Multi-Location Restaurant Analytics Database
-- File: 01_schema.sql
-- Purpose: Defines all tables, constraints, and relationships
-- Author: Harsh
-- ============================================================

DROP SCHEMA IF EXISTS flavormetrics CASCADE;
CREATE SCHEMA flavormetrics;
SET search_path TO flavormetrics;

-- ------------------------------------------------------------
-- Table: stores
-- Each physical restaurant location
-- ------------------------------------------------------------
CREATE TABLE stores (
    store_id        SMALLINT PRIMARY KEY,
    store_name      VARCHAR(50) NOT NULL,
    city            VARCHAR(50) NOT NULL,
    opened_date     DATE NOT NULL
);

-- ------------------------------------------------------------
-- Table: customers
-- Master record for every customer who has ever ordered
-- ------------------------------------------------------------
CREATE TABLE customers (
    customer_id     INT PRIMARY KEY,
    first_name      VARCHAR(50) NOT NULL,
    signup_date     DATE NOT NULL,
    home_city       VARCHAR(50)
);

-- ------------------------------------------------------------
-- Table: loyalty_members
-- Tracks loyalty program membership; not every customer is a member
-- ------------------------------------------------------------
CREATE TABLE loyalty_members (
    customer_id     INT PRIMARY KEY REFERENCES customers(customer_id),
    join_date       DATE NOT NULL,
    tier            VARCHAR(20) NOT NULL DEFAULT 'Silver'
                    CHECK (tier IN ('Silver', 'Gold', 'Platinum'))
);

-- ------------------------------------------------------------
-- Table: menu_items
-- Product catalog with price AND cost (enables margin analysis)
-- ------------------------------------------------------------
CREATE TABLE menu_items (
    product_id      SMALLINT PRIMARY KEY,
    product_name    VARCHAR(50) NOT NULL,
    category        VARCHAR(30) NOT NULL,
    price           NUMERIC(6,2) NOT NULL CHECK (price > 0),
    cost            NUMERIC(6,2) NOT NULL CHECK (cost > 0)
);

-- ------------------------------------------------------------
-- Table: staff
-- Employees who fulfill orders (adds an operational dimension)
-- ------------------------------------------------------------
CREATE TABLE staff (
    staff_id        SMALLINT PRIMARY KEY,
    staff_name      VARCHAR(50) NOT NULL,
    store_id        SMALLINT NOT NULL REFERENCES stores(store_id),
    role            VARCHAR(30) NOT NULL
);

-- ------------------------------------------------------------
-- Table: orders
-- One row per order (header). Line items live in order_items.
-- ------------------------------------------------------------
CREATE TABLE orders (
    order_id        INT PRIMARY KEY,
    customer_id     INT NOT NULL REFERENCES customers(customer_id),
    store_id        SMALLINT NOT NULL REFERENCES stores(store_id),
    staff_id        SMALLINT REFERENCES staff(staff_id),
    order_date      DATE NOT NULL,
    order_time      TIME NOT NULL
);

-- ------------------------------------------------------------
-- Table: order_items
-- Line-item detail for every order (1 order -> many items)
-- ------------------------------------------------------------
CREATE TABLE order_items (
    order_item_id   INT PRIMARY KEY,
    order_id        INT NOT NULL REFERENCES orders(order_id),
    product_id      SMALLINT NOT NULL REFERENCES menu_items(product_id),
    quantity        SMALLINT NOT NULL CHECK (quantity > 0)
);

-- ------------------------------------------------------------
-- Indexes to support common analytical query patterns
-- ------------------------------------------------------------
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_date     ON orders(order_date);
CREATE INDEX idx_order_items_order   ON order_items(order_id);
CREATE INDEX idx_order_items_product ON order_items(product_id);
