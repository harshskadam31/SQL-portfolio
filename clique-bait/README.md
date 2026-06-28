# Clique Bait — Online Seafood Store Digital & Funnel Analytics

A PostgreSQL analytics project for Clique Bait, a fictional online seafood store. The core
business problem: understand how users move through the website funnel — from landing on the
home page to viewing products, adding to cart, and completing a purchase — and evaluate
whether the store's three marketing campaigns actually drove meaningful uplift in conversions.

Built as an end-to-end SQL case study covering digital traffic analysis, product-level funnel
metrics, cart abandonment, and campaign attribution — from basic aggregation through CTEs,
window functions, conditional aggregation, and multi-table joins across 5 related tables.

---

## 1. Business Context

Clique Bait runs an online seafood store with 9 products across three categories: Fish,
Luxury, and Shellfish. The store tracks every user interaction — page views, cart adds,
purchases, and ad events — at the visit level via cookie tracking.

The management team needs answers to two categories of questions:

**Traffic & behaviour questions:**
- How many users does the site have, and how many visits are they generating per month?
- Which pages and product categories are getting the most attention?
- Where exactly are users dropping off in the funnel — which products get viewed but not
  bought, and which get added to cart but abandoned at checkout?

**Campaign effectiveness questions:**
- Did users who visited during a campaign period convert at higher rates?
- Do ad impressions actually drive purchases, or do people just ignore them?
- Does clicking on an ad (vs just seeing it) make a measurable difference to purchase rates?
- Which of the three campaigns performed best, and by what metrics?

---

## 2. Schema Design

Five tables across two types — lookup tables and fact tables:

![ER Diagram](docs/er_diagram.png)

| Table | Type | Purpose |
|---|---|---|
| `event_identifier` | Lookup | Maps event_type codes (1-5) to readable names |
| `page_hierarchy` | Lookup | All 13 pages on the site; product pages include category and product_id |
| `campaign_identifier` | Lookup | The 3 campaigns with their date ranges and covered products |
| `users` | Dimension | One row per registered user; links to events via cookie_id |
| `events` | Fact | Every on-site interaction — one row per event, keyed by visit_id + sequence_number |

Key design decisions:

- **`events` is keyed at visit + sequence level, not user level** — users are tracked via
  `cookie_id`, not `user_id` directly. This means the same user can have multiple cookies
  (different devices/browsers), and the join to `users` goes through `cookie_id`. This is
  how real digital analytics systems work — the device is tracked, not the person, until
  they log in.

- **`sequence_number` within each visit** enables ordering events correctly without relying
  on timestamp alone (two events in the same second would be ambiguous). It's what makes
  the `cart_products` column in the campaign summary possible — products are listed in the
  order they were added to cart, not alphabetically.

- **Non-product pages have NULL `product_category` and `product_id`** in `page_hierarchy` —
  Home Page, All Products, Checkout, and Confirmation are navigational pages, not products.
  Every query that calculates product-level metrics filters on `product_id IS NOT NULL` to
  exclude these.

- **`campaign_identifier.products` is a text range string** (e.g. "1-3"), not a foreign key
  — this is a denormalized design choice in the original schema. The actual campaign-to-visit
  attribution is done by matching `event_time` to the campaign's `start_date`/`end_date`
  range, not by product matching.

---

## 3. Data

The dataset is synthetically generated (`scripts/generate_data.py`, seeded for
reproducibility) with realistic funnel behavior rather than random events:

- **500 users** with 1-3 cookies each (simulating multi-device browsing)
- **4,500+ visits** across the Jan–May 2020 observation window
- **36,000+ events** distributed across three user segments:
  - Buyers (35%) — frequently add to cart and complete purchases (85%+ checkout rate)
  - Cart Adders (40%) — browse and add to cart but abandon more often (~45% checkout rate)
  - Browsers (25%) — mostly view pages with low cart add and purchase rates
- Every visit follows a realistic page sequence: Home → All Products → product pages →
  (optional) Checkout → (optional) Confirmation
- Ad impressions and clicks are only generated for visits that fall within a campaign
  window, and at realistic rates (~40% of campaign-period visits see an ad, ~60% of those
  click it)

---

## 4. Analysis — What the Queries Show

All queries are in [`sql/03_analysis_queries.sql`](sql/03_analysis_queries.sql), organized
into three sections.

### Section 2 — Digital Analysis (9 questions)

Baseline traffic metrics: total user count, average cookies per user, monthly visit volume,
event type breakdown, purchase rate, checkout abandonment rate, top pages by views, views
and cart adds by product category, and top 3 products by purchases.

The checkout abandonment query (Q6) is the most business-critical of these — it identifies
what percentage of visits reached the checkout page but did not complete a purchase. This is
the single most actionable metric for a conversion optimization team.

### Section 3 — Product Funnel Analysis

Two summary tables are created:

`product_funnel` — one row per product with views, cart adds, abandoned (added to cart but
not purchased), and purchases. The abandoned calculation uses a LEFT JOIN between
cart-add events and completed-purchase visits — if the visit_id has no purchase event, any
cart add in that visit is an abandonment.

`category_funnel` — same metrics aggregated by product category (Fish, Luxury, Shellfish).

From these tables, five questions are answered: most viewed/added/purchased product,
highest abandonment rate, best view-to-purchase conversion, and average view-to-cart and
cart-to-purchase conversion rates across all products.

### Section 4 — Campaign Analysis

A `visit_summary` table is created with one row per visit containing: user_id, visit_id,
visit start time, page views, cart adds, purchase flag, campaign name (if applicable),
impression count, click count, and a comma-separated list of cart products in the order
they were added.

Five campaign insights are then derived from this table:

- Purchase rate during campaign vs non-campaign periods
- Impact of ad impressions and clicks on purchase rate (three-way split: impression+click,
  impression only, no impression)
- Campaign-by-campaign comparison: visits, impressions, clicks, click-through rate,
  purchases, and purchase rate
- Cart abandonment rate during campaign vs non-campaign periods
- Top 10 most engaged users by cart adds — highest-priority retargeting targets

---

## 5. Key Findings

| Question | Finding |
|---|---|
| Do ad impressions drive purchases? | Users who received an impression AND clicked converted at a significantly higher rate than those who only saw the impression, who in turn converted higher than users with no impression at all. Clicking is the critical step. |
| Which product category abandons most? | Luxury products (Russian Caviar, Black Truffle) have the highest view-to-cart rate but also the highest abandonment — high interest, high hesitation at purchase. |
| Which campaign performed best? | Evaluated by purchase rate and click-through rate across the three campaigns — see campaign comparison query output for the specific result from your data. |
| Where does the funnel lose the most users? | The biggest drop is between cart add and checkout, not between checkout and purchase. Reducing cart abandonment is a higher-leverage intervention than improving checkout flow. |
| Who should be retargeted? | Users with high cart adds and zero purchases — identified in Insight 5 — are the clearest re-engagement targets. They have demonstrated intent but have not converted. |

---

## 6. Tech Stack & How to Run

- **PostgreSQL 16**
- `sql/01_schema.sql` — DDL (5 tables, constraints, indexes)
- `sql/02_seed_data.sql` — 500 users, 4,500+ visits, 36,000+ events
- `sql/03_analysis_queries.sql` — all analysis queries for Sections 2, 3, and 4
- `scripts/generate_data.py` — Python script that generated the seed data
- `docs/er_diagram.png` — entity-relationship diagram

```bash
# 1. Create the database
createdb clique_bait_db

# 2. Load schema
psql -d clique_bait_db -f sql/01_schema.sql

# 3. Load seed data
psql -d clique_bait_db -f sql/02_seed_data.sql

# 4. Run the analysis
psql -d clique_bait_db -f sql/03_analysis_queries.sql
```

---

## 7. File Structure

```
clique-bait/
├── README.md
├── docs/
│   └── er_diagram.png
├── scripts/
│   └── generate_data.py
└── sql/
    ├── 01_schema.sql
    ├── 02_seed_data.sql
    └── 03_analysis_queries.sql
```

---

*Based on Case Study #6 from the [8 Week SQL Challenge](https://8weeksqlchallenge.com/case-study-6/)
by Danny Ma. Schema adapted, synthetic dataset and extended campaign analysis are original.*
