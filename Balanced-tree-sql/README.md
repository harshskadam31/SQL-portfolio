# Balanced Tree Clothing Co. — Sales & Merchandising Analytics

A PostgreSQL analytics project for Balanced Tree Clothing Co., a fictional fashion brand
selling lifestyle and adventure wear across two categories: Womens and Mens. The core
business problem: generate a complete monthly financial and merchandising report covering
sales volume, revenue, discount impact, transaction behaviour, and product performance
across the full product hierarchy.

Built as an end-to-end SQL case study covering high-level sales metrics, transaction
analysis, product and segment revenue breakdowns, transaction penetration, product
combination analysis, and a reusable monthly reporting script — from basic aggregation
through window functions, CTEs, self-joins, and a recursive CTE for hierarchy reconstruction.

---

## 1. Business Context

Balanced Tree sells 12 products organized into a 3-level hierarchy: Category → Segment →
Style. The merchandising team needs a monthly report covering:

**Sales & revenue questions:**
- How much did we sell in total, what was gross revenue, and how much did discounts cost us?
- What does the revenue split look like across categories and segments?
- Which products are driving the most revenue, and which are losing margin to discounts?

**Transaction behaviour questions:**
- How many transactions are members generating vs non-members, and do members spend more?
- What is the revenue distribution across transactions — what does a typical basket look like?

**Product intelligence questions:**
- Which products appear in the most transactions (penetration), regardless of quantity?
- What are the most common 3-product combinations bought together?
- Which product is the top seller within each segment and category?

---

## 2. Schema Design

Four tables — two core, two used for the bonus challenge:

![ER Diagram](docs/er_diagram.png)

| Table | Purpose |
|---|---|
| `product_details` | Denormalized product reference — one row per product with all hierarchy levels flattened |
| `sales` | Core fact table — one row per product line item per transaction |
| `product_hierarchy` | Recursive self-referencing taxonomy: Category → Segment → Style |
| `product_prices` | Maps hierarchy leaf nodes (styles) to product_id codes and prices |

Key design decisions:

- **`product_details` is a denormalized flat table** — it duplicates data from
  `product_hierarchy` and `product_prices` but makes every analytical join simple.
  Instead of joining 3 tables for every query, you join one. This is a classic trade-off:
  normalization is better for storage and updates; denormalization is better for read-heavy
  analytics workloads, which this is.

- **`product_hierarchy` is a self-referencing adjacency list** — `parent_id` points to
  another row in the same table. This is the standard way to store trees in SQL. The bonus
  challenge uses a recursive CTE to walk this tree and reconstruct `product_details` from
  scratch, which demonstrates how the denormalized table was originally derived.

- **`discount` is stored as an integer percentage, not a decimal** — `17` means 17%, not
  0.17. Every revenue calculation in the analysis queries divides by 100: 
  `qty * price * (1 - discount / 100.0)`. This is a common pattern in retail datasets and
  a source of easy bugs if you forget the division.

- **`sales` has no explicit primary key** — a transaction (txn_id) has multiple rows, one
  per product. The natural key would be `(txn_id, prod_id)` but the case study schema does
  not enforce this. Analytical queries always GROUP BY or use DISTINCT on txn_id.

---

## 3. Data

The product catalog (hierarchy, prices, product_details) matches the case study exactly —
12 products, same IDs, names, and prices. The sales data is synthetically generated
(`scripts/generate_data.py`, seeded for reproducibility):

- **2,500 unique transactions** across January–March 2021
- **9,300+ sales line items** (average ~3.7 products per transaction)
- Monthly volume is weighted: January heaviest (~42% of transactions — post-holiday sales),
  February lightest (~28%), March mid (~30%). This creates visible month-over-month patterns
  in the reporting challenge output.
- **~60% member transactions** — the loyalty program majority, matching realistic program
  penetration rates
- Discount distribution follows the case study sample data pattern: 17% and 21% are the
  most common discount levels, with a spread from 0% to 30%
- Higher-priced products (Grey Fashion Jacket at $54, Blue Polo at $57) are sold in lower
  quantities per line item; cheaper items (socks, basic jeans) move in higher volumes

---

## 4. Analysis — What the Queries Show

All queries are in [`sql/03_analysis_queries.sql`](sql/03_analysis_queries.sql), organized
into four sections plus the bonus.

### Section 1 — High Level Sales Analysis

Three baseline metrics: total quantity sold, total gross revenue (before discounts), and
total discount amount. These form the top line of any financial report — gross revenue
minus total discounts gives net revenue.

### Section 2 — Transaction Analysis

Six questions covering unique transaction count, average basket size (unique products per
transaction), revenue percentile distribution (25th/50th/75th using `PERCENTILE_CONT`),
average discount per transaction, member vs non-member transaction split, and average net
revenue by customer type.

The percentile query is particularly useful for the CFO — it shows not just the average
basket value but the shape of the distribution, which helps identify whether revenue is
concentrated in a few large orders or spread evenly.

### Section 3 — Product Analysis

Ten questions of increasing complexity. The most technically interesting are:

**P9 — Transaction penetration**: measures how broadly each product appears across all
transactions, regardless of quantity. A product bought once in every transaction has 100%
penetration. This is different from revenue contribution — a cheap, widely-bought product
can have high penetration but low revenue impact.

**P10 — Most common 3-product combination**: uses a triple self-join on `sales`
(`s1 JOIN s2 JOIN s3 ON txn_id`) with ascending `prod_id` ordering to generate all unique
3-product combinations per transaction, then counts frequency. This is computationally
expensive on large datasets but correct and readable.

**P6/P7 — Revenue percentage splits**: use `SUM() OVER (PARTITION BY segment/category)`
window functions to calculate each product's share within its segment, and each segment's
share within its category — all in a single query without subqueries.

### Section 4 — Reporting Challenge

A parameterized monthly script — change two date values at the top and the entire report
regenerates for a different month. The script produces three output tables: high-level
summary (qty, gross, net, discounts, transactions), product performance table, and
member vs non-member breakdown. Demonstrated for January 2021 with instructions to
switch to February by changing the date filter.

### Bonus — Recursive CTE

A recursive CTE walks the `product_hierarchy` adjacency list from the top (Category nodes
with no parent) downward through Segments to Styles, carrying the category and segment
names along at each level. At the Style level, it joins `product_prices` to get the
product_id and price. The result is identical to `product_details` — generated purely
from the normalized source tables with no hardcoded values.

---

## 5. Key Findings

| Question | Finding |
|---|---|
| What percentage of revenue is lost to discounts? | Total discount amount as a share of gross revenue is approximately 20-22%, consistent with the 17-21% modal discount rates in the data. |
| Do members spend more per transaction? | Members generate slightly higher average net revenue per transaction than non-members, consistent with loyalty program behavior (members tend to be higher-intent shoppers). |
| Which segment drives the most revenue? | Shirts (Mens) and Jackets (Womens) lead by revenue due to higher unit prices, even though Socks and Jeans move higher volumes. |
| Which product has the highest penetration? | Lower-priced, broadly appealing products (socks, basic jeans) tend to appear in the most transactions — high penetration, moderate revenue contribution. |
| What is a typical transaction worth? | The median (P50) net revenue per transaction gives the truest picture of a "normal" basket — check the percentile query output for the specific value from this dataset. |

---

## 6. Tech Stack & How to Run

- **PostgreSQL 16**
- `sql/01_schema.sql` — DDL (4 tables, constraints, indexes)
- `sql/02_seed_data.sql` — 12 products (exact from case study), 2,500 transactions, 9,300+ sales rows
- `sql/03_analysis_queries.sql` — all analysis queries + monthly reporting script + bonus recursive CTE
- `scripts/generate_data.py` — Python script that generated the seed data
- `docs/er_diagram.png` — entity-relationship diagram

```bash
# 1. Create the database
createdb balanced_tree_db

# 2. Load schema
psql -d balanced_tree_db -f sql/01_schema.sql

# 3. Load seed data
psql -d balanced_tree_db -f sql/02_seed_data.sql

# 4. Run the analysis
psql -d balanced_tree_db -f sql/03_analysis_queries.sql
```

---

## 7. File Structure

```
balanced-tree/
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

*Based on Case Study #7 from the [8 Week SQL Challenge](https://8weeksqlchallenge.com/case-study-7/)
by Danny Ma. Schema adapted, synthetic dataset and extended analysis are original.*
