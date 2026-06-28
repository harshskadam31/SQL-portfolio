"""
generate_data.py
Generates synthetic data for the Data Bank case study and writes
SQL INSERT statements to 02_seed_data.sql.

Design choices:
- 500 customers distributed across 5 regions with realistic skew
  (America and Asia have more customers than Africa or Europe)
- Each customer gets 3-8 node reallocations over the observation period
  (Jan 2020 - Apr 2020), simulating real security reshuffling
- A sentinel end_date of '9999-12-31' marks the current active node
- Transaction behavior is segmented: active customers deposit frequently,
  moderate customers mix deposits with purchases, low-activity customers
  have sparse transactions
- Deposit amounts are higher on average than withdrawals/purchases,
  ensuring most customers maintain a positive running balance
  (realistic for a bank dataset)
"""

import random
from datetime import date, timedelta

random.seed(42)

OUTPUT_FILE = "/home/claude/data-bank/sql/02_seed_data.sql"

# ----------------------------------------------------------------------
# 1. REGIONS
# ----------------------------------------------------------------------
regions = [
    (1, "Africa"),
    (2, "America"),
    (3, "Asia"),
    (4, "Europe"),
    (5, "Oceania"),
]

# ----------------------------------------------------------------------
# 2. CUSTOMER DISTRIBUTION ACROSS REGIONS
# Weighted so America and Asia have more customers (realistic)
# ----------------------------------------------------------------------
NUM_CUSTOMERS = 500
REGION_WEIGHTS = [0.12, 0.28, 0.26, 0.18, 0.16]  # Africa, America, Asia, Europe, Oceania

customer_regions = random.choices(
    population=[1, 2, 3, 4, 5],
    weights=REGION_WEIGHTS,
    k=NUM_CUSTOMERS,
)

# ----------------------------------------------------------------------
# 3. CUSTOMER NODES
# Each customer is assigned to a node (1-5) within their region.
# They get reallocated every few days to weeks for security.
# Observation window: Jan 2020 - Apr 2020
# ----------------------------------------------------------------------
OBS_START = date(2020, 1, 1)
OBS_END   = date(2020, 4, 30)
SENTINEL  = date(9999, 12, 31)

customer_nodes = []

for cid in range(1, NUM_CUSTOMERS + 1):
    region_id = customer_regions[cid - 1]
    current_date = OBS_START
    n_reallocations = random.randint(3, 8)

    allocation_dates = sorted(
        random.sample(
            [OBS_START + timedelta(days=d) for d in range((OBS_END - OBS_START).days)],
            k=n_reallocations
        )
    )

    for i, start in enumerate(allocation_dates):
        node_id = random.randint(1, 5)
        if i < len(allocation_dates) - 1:
            end = allocation_dates[i + 1] - timedelta(days=1)
        else:
            end = SENTINEL  # currently active allocation
        customer_nodes.append((cid, region_id, node_id, start, end))

# ----------------------------------------------------------------------
# 4. CUSTOMER TRANSACTIONS
# Three segments: active, moderate, low-activity
# Observation window matches: Jan 2020 - Apr 2020
# ----------------------------------------------------------------------
segment_roll = random.choices(
    population=["active", "moderate", "low"],
    weights=[0.25, 0.45, 0.30],
    k=NUM_CUSTOMERS,
)
customer_segment = {cid: seg for cid, seg in zip(range(1, NUM_CUSTOMERS + 1), segment_roll)}

TXN_COUNT = {
    "active":   (15, 30),
    "moderate": (5, 14),
    "low":      (1, 4),
}

# Transaction type weights per segment
# Active customers deposit more; low-activity ones mostly just deposit once
TXN_TYPE_WEIGHTS = {
    "active":   {"deposit": 0.50, "withdrawal": 0.25, "purchase": 0.25},
    "moderate": {"deposit": 0.55, "withdrawal": 0.22, "purchase": 0.23},
    "low":      {"deposit": 0.70, "withdrawal": 0.15, "purchase": 0.15},
}

# Amount ranges per transaction type
# Deposits are intentionally higher to keep balances positive on average
AMOUNT_RANGES = {
    "deposit":    (100, 2000),
    "withdrawal": (50,  800),
    "purchase":   (20,  600),
}

customer_transactions = []
total_days = (OBS_END - OBS_START).days

for cid in range(1, NUM_CUSTOMERS + 1):
    seg = customer_segment[cid]
    n_txns = random.randint(*TXN_COUNT[seg])
    type_weights = TXN_TYPE_WEIGHTS[seg]

    txn_types = random.choices(
        population=list(type_weights.keys()),
        weights=list(type_weights.values()),
        k=n_txns,
    )

    for txn_type in txn_types:
        offset = random.randint(0, total_days)
        txn_date = OBS_START + timedelta(days=offset)
        amount = random.randint(*AMOUNT_RANGES[txn_type])
        customer_transactions.append((cid, txn_date, txn_type, amount))

# Sort by customer then date for cleaner SQL output
customer_transactions.sort(key=lambda x: (x[0], x[1]))

# ----------------------------------------------------------------------
# WRITE SQL FILE
# ----------------------------------------------------------------------
def sql_str(s):
    return "'" + str(s).replace("'", "''") + "'"

lines = []
lines.append("-- ============================================================")
lines.append("-- Data Bank: Seed Data (synthetically generated)")
lines.append("-- Realistic distributions: region skew, node reallocation")
lines.append("-- frequency, customer transaction segments.")
lines.append("-- Generated by generate_data.py with seed=42.")
lines.append("-- File: 02_seed_data.sql")
lines.append("-- ============================================================")
lines.append("SET search_path TO data_bank;\n")

# Regions
lines.append("-- regions")
lines.append("INSERT INTO regions (region_id, region_name) VALUES")
lines.append(",\n".join(f"({rid}, {sql_str(rname)})" for rid, rname in regions) + ";\n")

# Customer nodes
lines.append(f"-- customer_nodes ({len(customer_nodes)} rows)")
batch_size = 500
for i in range(0, len(customer_nodes), batch_size):
    batch = customer_nodes[i:i + batch_size]
    lines.append("INSERT INTO customer_nodes (customer_id, region_id, node_id, start_date, end_date) VALUES")
    lines.append(",\n".join(
        f"({cid}, {rid}, {nid}, {sql_str(sd)}, {sql_str(ed)})"
        for cid, rid, nid, sd, ed in batch
    ) + ";\n")

# Customer transactions
lines.append(f"-- customer_transactions ({len(customer_transactions)} rows)")
for i in range(0, len(customer_transactions), batch_size):
    batch = customer_transactions[i:i + batch_size]
    lines.append("INSERT INTO customer_transactions (customer_id, txn_date, txn_type, txn_amount) VALUES")
    lines.append(",\n".join(
        f"({cid}, {sql_str(td)}, {sql_str(tt)}, {amt})"
        for cid, td, tt, amt in batch
    ) + ";\n")

with open(OUTPUT_FILE, "w") as f:
    f.write("\n".join(lines))

print(f"Generated {len(regions)} regions")
print(f"Generated {len(customer_nodes)} customer node allocations")
print(f"Generated {len(customer_transactions)} customer transactions")
print(f"Written to {OUTPUT_FILE}")
