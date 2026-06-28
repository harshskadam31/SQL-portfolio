# Data Bank — Neo-Bank Customer & Data Storage Analytics

A PostgreSQL analytics project based on a fictional neo-bank called Data Bank, which links
customer cloud storage allocation directly to their account balance. The central business
problem: how much data storage should the bank provision, and which allocation model makes
the most financial sense?

Built as an end-to-end SQL case study covering customer node distribution, transaction
behaviour analysis, running balance calculations, and financial modelling with interest
compounding — from basic aggregation through window functions, CTEs, and multi-option
scenario comparison.

---

## 1. Business Context

Data Bank operates like a digital bank with one unique twist — customers are allocated cloud
data storage proportional to their account balance. The bank runs on a distributed node
network across 5 global regions, and customers are periodically reallocated between nodes for
security.

The management team needs answers to two categories of questions:

**Operational questions:**
- How are customers distributed across regions and nodes?
- How frequently are customers being reallocated between nodes, and does it vary by region?

**Financial & storage planning questions:**
- What does customer transaction behaviour look like across deposits, withdrawals, and purchases?
- What is each customer's running and closing balance over time?
- If data allocation is tied to balance, how much storage would each of three possible
  allocation models require — and which is most cost-efficient for the business?
- How does daily interest compounding affect storage allocation projections?

---

## 2. Schema Design

Three tables, intentionally kept lean to mirror a real banking core system:

![ER Diagram](docs/er_diagram.png)

| Table | Purpose |
|---|---|
| `regions` | Five global regions where Data Bank nodes operate |
| `customer_nodes` | Tracks each customer's node assignment over time — one row per allocation period, with a sentinel `end_date` of `9999-12-31` marking the currently active node |
| `customer_transactions` | Every financial event: deposits, withdrawals, and purchases, with date and amount |

Key design decisions:
- **`customer_nodes` uses a start/end date pattern** rather than a single current-node column.
  This is a slowly changing dimension (Type 2 SCD) approach — it preserves the full history
  of reallocation events, which is what makes questions about reallocation frequency and
  duration answerable at all.
- **Sentinel `end_date = '9999-12-31'`** marks the currently active row without needing a
  separate `is_current` flag. Every query that needs current node assignment filters on this.
- **`txn_type` is constrained** to exactly three values (`deposit`, `withdrawal`, `purchase`)
  via a CHECK constraint — the schema enforces valid states rather than relying on the
  application layer.
- **Signed amount logic lives in the queries, not the table** — `txn_amount` is always
  positive (constrained), and analysis queries apply `+/-` sign based on transaction type.
  This is cleaner than storing negative numbers for withdrawals, which creates ambiguity.

---

## 3. Data

The dataset is synthetically generated (`scripts/generate_data.py`, seeded for
reproducibility) with realistic distributions rather than purely random values:

- **500 customers** distributed across 5 regions with a realistic skew — America and Asia
  have a higher share (~28% and ~26%) reflecting larger customer bases; Africa and Oceania
  are smaller markets
- **2,700+ node allocation records** — each customer has 3-8 reallocation events across the
  observation window (Jan 2020–Apr 2020), simulating real security reshuffling behaviour
- **5,200+ transactions** across three segments: active customers (25%) with 15-30
  transactions, moderate customers (45%) with 5-14, and low-activity customers (30%) with
  1-4 — deposit amounts are intentionally higher on average than withdrawals and purchases
  so that most customers maintain a positive running balance, which makes the interest
  calculations in Section D meaningful
- **Observation window: January 2020 to April 2020** — 4 months, matching the original
  case study timeframe

---

## 4. Analysis — What the Queries Show

All queries are in [`sql/03_analysis_queries.sql`](sql/03_analysis_queries.sql), organized
into four sections.

### Section A — Customer Nodes Exploration
Baseline understanding of the node network: unique node count, distribution by region,
customer allocation per region, average reallocation duration, and percentile analysis
(median, 80th, 95th) of reallocation days per region. The percentile query uses
`PERCENTILE_CONT` — the continuous interpolation variant — which is standard for operational
metrics where fractional days are meaningful.

### Section B — Customer Transactions
Five questions of increasing complexity: transaction volume by type, average deposit
behaviour per customer, identifying "engaged" customers (more than 1 deposit + at least 1
purchase or withdrawal in a month), closing balance at month-end using a running SUM window
function, and the percentage of customers who grew their balance by more than 5% over the
observation period.

The closing balance query is the core building block for everything in Sections C and D —
it applies signed amounts (deposits positive, withdrawals and purchases negative) inside a
`SUM() OVER (PARTITION BY customer_id ORDER BY month ROWS UNBOUNDED PRECEDING)` window to
produce a true running balance.

### Section C — Data Allocation Challenge
The business needs to choose between three storage allocation models:

- **Option 1** — allocate based on prior month's closing balance. Predictable and simple to
  implement, but lags real behaviour by a month.
- **Option 2** — allocate based on average running balance over the previous 30 days. More
  representative of actual usage; harder to game with a single large deposit.
- **Option 3** — real-time allocation that updates with every transaction. Most accurate but
  requires infrastructure that scales with transaction volume rather than monthly snapshots.

The final query in this section puts all three options side by side in one table so the
business can directly compare monthly storage requirements across models.

### Section D — Interest Compounding
If Data Bank rewards customers with data storage based on 6% annual interest, how much
additional storage is needed? Two versions are calculated: simple daily interest
(balance × 0.06 / 365) and daily compound interest using the precise formula
`balance × ((1.06)^(1/365) - 1)`. The cumulative interest column in the simple version
shows total interest accrued over the full observation window.

---

## 5. Key Findings

| Question | Finding |
|---|---|
| Which region has the most customers? | America leads with ~28% of customers, followed closely by Asia at ~26%. Africa has the smallest share at ~12%. |
| How long do customers stay on a node before reallocation? | Average reallocation period is approximately 14-16 days. The 95th percentile is significantly higher, indicating a tail of customers who remain on the same node for extended periods. |
| Which transaction type dominates by volume? | Deposits account for the majority of transactions and total value, as expected — the deposit-heavy design ensures most customers maintain positive balances. |
| Which allocation option requires the least storage? | Option 1 (prior month end balance) generally requires the least provisioned storage since it lags actual balances. Option 3 (real-time) requires the most. The right choice depends on whether the business wants to minimise storage cost or minimise the risk of under-provisioning. |
| Does compounding meaningfully change storage needs? | Over a 4-month window, simple vs compound interest produces similar results. The difference becomes significant over longer horizons — the compound formula is correct for multi-year projections. |

---

## 6. Tech Stack & How to Run

- **PostgreSQL 16**
- `sql/01_schema.sql` — DDL (tables, constraints, indexes)
- `sql/02_seed_data.sql` — synthetic seed data (~2,700 node records, ~5,200 transactions)
- `sql/03_analysis_queries.sql` — all analysis queries for Sections A through D
- `scripts/generate_data.py` — Python script that generated the seed data (re-runnable, seeded for reproducibility)
- `docs/er_diagram.png` — entity-relationship diagram

```bash
# 1. Create the database
createdb data_bank_db

# 2. Load schema
psql -d data_bank_db -f sql/01_schema.sql

# 3. Load seed data
psql -d data_bank_db -f sql/02_seed_data.sql

# 4. Run the analysis
psql -d data_bank_db -f sql/03_analysis_queries.sql
```

---

## 7. File Structure

```
data-bank/
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

*Based on Case Study #4 from the [8 Week SQL Challenge](https://8weeksqlchallenge.com/case-study-4/)
by Danny Ma. Schema, synthetic dataset, and extended analysis are original.*
