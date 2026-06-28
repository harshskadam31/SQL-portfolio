-- ============================================================
-- Clique Bait: Online Seafood Store Digital Analytics
-- File: 01_schema.sql
-- Purpose: Defines all tables, constraints, and indexes
-- Author: Harsh
-- ============================================================

DROP SCHEMA IF EXISTS clique_bait CASCADE;
CREATE SCHEMA clique_bait;
SET search_path TO clique_bait;

-- ------------------------------------------------------------
-- Table: event_identifier
-- Lookup table mapping event_type codes to human-readable names.
-- 5 event types: Page View, Add to Cart, Purchase,
-- Ad Impression, Ad Click.
-- ------------------------------------------------------------
CREATE TABLE event_identifier (
    event_type      INTEGER PRIMARY KEY,
    event_name      VARCHAR(20) NOT NULL
);

-- ------------------------------------------------------------
-- Table: campaign_identifier
-- The 3 marketing campaigns run by Clique Bait in 2020.
-- products column stores which product_ids each campaign covers.
-- Visits whose start_time falls within start_date/end_date
-- are attributed to that campaign.
-- ------------------------------------------------------------
CREATE TABLE campaign_identifier (
    campaign_id     INTEGER PRIMARY KEY,
    products        VARCHAR(10) NOT NULL,
    campaign_name   VARCHAR(50) NOT NULL,
    start_date      TIMESTAMP NOT NULL,
    end_date        TIMESTAMP NOT NULL,
    CHECK (end_date > start_date)
);

-- ------------------------------------------------------------
-- Table: page_hierarchy
-- Every page on the Clique Bait website.
-- Non-product pages (Home, All Products, Checkout, Confirmation)
-- have NULL product_category and product_id.
-- Product pages (Salmon, Lobster, etc.) have both populated.
-- ------------------------------------------------------------
CREATE TABLE page_hierarchy (
    page_id             INTEGER PRIMARY KEY,
    page_name           VARCHAR(20) NOT NULL,
    product_category    VARCHAR(20),
    product_id          INTEGER
);

-- ------------------------------------------------------------
-- Table: users
-- One row per registered user. cookie_id links to the events
-- table — users can have multiple cookies (multiple devices/sessions).
-- ------------------------------------------------------------
CREATE TABLE users (
    user_id         INTEGER PRIMARY KEY,
    cookie_id       VARCHAR(10) NOT NULL,
    start_date      TIMESTAMP NOT NULL
);

-- ------------------------------------------------------------
-- Table: events
-- Core fact table. Every interaction a user has on the site
-- is logged here at the cookie_id level. One visit_id groups
-- all events from a single session. sequence_number orders
-- events within a visit.
-- ------------------------------------------------------------
CREATE TABLE events (
    visit_id            VARCHAR(10) NOT NULL,
    cookie_id           VARCHAR(10) NOT NULL,
    page_id             INTEGER NOT NULL REFERENCES page_hierarchy(page_id),
    event_type          INTEGER NOT NULL REFERENCES event_identifier(event_type),
    sequence_number     INTEGER NOT NULL CHECK (sequence_number > 0),
    event_time          TIMESTAMP NOT NULL
);

-- ------------------------------------------------------------
-- Indexes
-- ------------------------------------------------------------
CREATE INDEX idx_events_visit     ON events(visit_id);
CREATE INDEX idx_events_cookie    ON events(cookie_id);
CREATE INDEX idx_events_page      ON events(page_id);
CREATE INDEX idx_events_type      ON events(event_type);
CREATE INDEX idx_events_time      ON events(event_time);
CREATE INDEX idx_users_cookie     ON users(cookie_id);
