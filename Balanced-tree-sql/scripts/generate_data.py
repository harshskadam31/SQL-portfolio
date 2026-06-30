"""
generate_data.py
Generates synthetic sales data for the Balanced Tree Clothing Co. case study
and writes SQL INSERT statements to 02_seed_data.sql.

Design choices:
- All 12 products are taken exactly from the case study (fixed IDs, prices, names)
- 2,500 unique transactions over Jan-Mar 2021 (3 months — allows monthly reporting demo)
- Each transaction has 2-6 product line items (realistic basket size for a clothing store)
- Discount is per line item (not per transaction), ranging 0-30%
- ~60% of transactions are from members (loyalty program majority)
- Higher-priced items (jackets, polo shirts) sell in lower quantities per line
- Socks and jeans move in higher volumes — typical fast-fashion pattern
- Transaction volume is slightly higher in Jan (post-holiday) and dips in Feb
"""

import random
import string
from datetime import datetime, timedelta

random.seed(42)

OUTPUT_FILE = "/home/claude/balanced-tree/sql/02_seed_data.sql"

# ----------------------------------------------------------------------
# 1. STATIC LOOKUP DATA — exact from case study
# ----------------------------------------------------------------------
product_hierarchy = [
    # Categories (no parent)
    (1,  None, "Womens", "Category"),
    (2,  None, "Mens",   "Category"),
    # Segments
    (3,  1,    "Jeans",  "Segment"),
    (4,  1,    "Jacket", "Segment"),
    (5,  2,    "Shirt",  "Segment"),
    (6,  2,    "Socks",  "Segment"),
    # Styles
    (7,  3,    "Navy Oversized",      "Style"),
    (8,  3,    "Black Straight",      "Style"),
    (9,  3,    "Cream Relaxed",       "Style"),
    (10, 4,    "Khaki Suit",          "Style"),
    (11, 4,    "Indigo Rain",         "Style"),
    (12, 4,    "Grey Fashion",        "Style"),
    (13, 5,    "White Tee",           "Style"),
    (14, 5,    "Teal Button Up",      "Style"),
    (15, 5,    "Blue Polo",           "Style"),
    (16, 6,    "Navy Solid",          "Style"),
    (17, 6,    "White Striped",       "Style"),
    (18, 6,    "Pink Fluro Polkadot", "Style"),
]

product_prices = [
    (7,  "c4a632", 13),
    (8,  "e83aa3", 32),
    (9,  "e31d39", 10),
    (10, "d5e9a6", 23),
    (11, "72f5d4", 19),
    (12, "9ec847", 54),
    (13, "5d267b", 40),
    (14, "c8d436", 10),
    (15, "2a2353", 57),
    (16, "f084eb", 36),
    (17, "b9a74d", 17),
    (18, "2feb6b", 29),
]

product_details = [
    ("c4a632", 13, "Navy Oversized Jeans - Womens",    1, 3, 7,  "Womens", "Jeans",  "Navy Oversized"),
    ("e83aa3", 32, "Black Straight Jeans - Womens",    1, 3, 8,  "Womens", "Jeans",  "Black Straight"),
    ("e31d39", 10, "Cream Relaxed Jeans - Womens",     1, 3, 9,  "Womens", "Jeans",  "Cream Relaxed"),
    ("d5e9a6", 23, "Khaki Suit Jacket - Womens",       1, 4, 10, "Womens", "Jacket", "Khaki Suit"),
    ("72f5d4", 19, "Indigo Rain Jacket - Womens",      1, 4, 11, "Womens", "Jacket", "Indigo Rain"),
    ("9ec847", 54, "Grey Fashion Jacket - Womens",     1, 4, 12, "Womens", "Jacket", "Grey Fashion"),
    ("5d267b", 40, "White Tee Shirt - Mens",           2, 5, 13, "Mens",   "Shirt",  "White Tee"),
    ("c8d436", 10, "Teal Button Up Shirt - Mens",      2, 5, 14, "Mens",   "Shirt",  "Teal Button Up"),
    ("2a2353", 57, "Blue Polo Shirt - Mens",           2, 5, 15, "Mens",   "Shirt",  "Blue Polo"),
    ("f084eb", 36, "Navy Solid Socks - Mens",          2, 6, 16, "Mens",   "Socks",  "Navy Solid"),
    ("b9a74d", 17, "White Striped Socks - Mens",       2, 6, 17, "Mens",   "Socks",  "White Striped"),
    ("2feb6b", 29, "Pink Fluro Polkadot Socks - Mens", 2, 6, 18, "Mens",   "Socks",  "Pink Fluro Polkadot"),
]

# product_id -> price lookup
price_lookup = {pid: price for _, pid, price in product_prices}
all_product_ids = [pid for _, pid, _ in product_prices]

# ----------------------------------------------------------------------
# 2. SALES GENERATION
# ----------------------------------------------------------------------
NUM_TRANSACTIONS = 2500
OBS_START = datetime(2021, 1, 1)
OBS_END   = datetime(2021, 3, 31, 23, 59, 59)

# Monthly transaction volume weights: Jan heavier, Feb lighter, Mar mid
def random_txn_time():
    month = random.choices([1, 2, 3], weights=[0.42, 0.28, 0.30], k=1)[0]
    if month == 1:
        start = datetime(2021, 1, 1)
        end   = datetime(2021, 1, 31, 23, 59, 59)
    elif month == 2:
        start = datetime(2021, 2, 1)
        end   = datetime(2021, 2, 28, 23, 59, 59)
    else:
        start = datetime(2021, 3, 1)
        end   = datetime(2021, 3, 31, 23, 59, 59)
    delta = end - start
    return start + timedelta(seconds=random.randint(0, int(delta.total_seconds())))

def unique_txn_id(used):
    while True:
        tid = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
        if tid not in used:
            used.add(tid)
            return tid

used_txn_ids = set()
sales = []

# Quantity weights per product — cheaper/lighter items sell more units per line
qty_weights = {
    "c4a632": [3,3,2,1,1],   # cheap jeans — higher qty
    "e83aa3": [3,3,2,1,1],
    "e31d39": [4,3,2,1],
    "d5e9a6": [3,3,2,1,1],
    "72f5d4": [3,3,2,1,1],
    "9ec847": [4,3,2,1],      # most expensive jacket — lower qty
    "5d267b": [3,3,2,1,1],
    "c8d436": [4,3,2,1,1],
    "2a2353": [4,3,2,1],      # most expensive shirt — lower qty
    "f084eb": [3,3,2,2,1],    # socks — higher qty
    "b9a74d": [3,3,3,2,1],
    "2feb6b": [3,3,3,2,1],
}

for _ in range(NUM_TRANSACTIONS):
    txn_id   = unique_txn_id(used_txn_ids)
    txn_time = random_txn_time()
    is_member = random.random() < 0.60
    n_products = random.choices([2, 3, 4, 5, 6], weights=[0.15, 0.30, 0.30, 0.17, 0.08], k=1)[0]
    chosen = random.sample(all_product_ids, k=n_products)

    for prod_id in chosen:
        price    = price_lookup[prod_id]
        wts      = qty_weights[prod_id]
        qty      = random.choices(range(1, len(wts) + 1), weights=wts, k=1)[0]
        discount = random.choices(
            population=[0, 10, 15, 17, 20, 21, 25, 30],
            weights   =[0.10, 0.10, 0.15, 0.20, 0.15, 0.15, 0.10, 0.05],
            k=1
        )[0]
        sales.append((prod_id, qty, price, discount, is_member, txn_id, txn_time))

# ----------------------------------------------------------------------
# WRITE SQL FILE
# ----------------------------------------------------------------------
def sql_str(s):
    if s is None:
        return "NULL"
    return "'" + str(s).replace("'", "''") + "'"

def sql_ts(dt):
    return f"'{dt.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]}'"

def sql_bool(b):
    return "true" if b else "false"

lines = []
lines.append("-- ============================================================")
lines.append("-- Balanced Tree Clothing Co.: Seed Data")
lines.append("-- Product hierarchy and prices match the case study exactly.")
lines.append("-- Sales data synthetically generated: 2,500 transactions over")
lines.append("-- Jan-Mar 2021 with realistic basket sizes, discount patterns,")
lines.append("-- and member ratios. Generated by generate_data.py seed=42.")
lines.append("-- File: 02_seed_data.sql")
lines.append("-- ============================================================")
lines.append("SET search_path TO balanced_tree;\n")

# product_hierarchy
lines.append("-- product_hierarchy")
lines.append("INSERT INTO product_hierarchy (id, parent_id, level_text, level_name) VALUES")
lines.append(",\n".join(
    f"({row[0]}, {sql_str(row[1])}, {sql_str(row[2])}, {sql_str(row[3])})"
    for row in product_hierarchy
) + ";\n")

# product_prices
lines.append("-- product_prices")
lines.append("INSERT INTO product_prices (id, product_id, price) VALUES")
lines.append(",\n".join(
    f"({id_}, {sql_str(pid)}, {price})"
    for id_, pid, price in product_prices
) + ";\n")

# product_details
lines.append("-- product_details")
lines.append("INSERT INTO product_details (product_id, price, product_name, category_id, segment_id, style_id, category_name, segment_name, style_name) VALUES")
lines.append(",\n".join(
    f"({sql_str(pid)}, {price}, {sql_str(pname)}, {cid}, {sid}, {stid}, {sql_str(cname)}, {sql_str(sname)}, {sql_str(stname)})"
    for pid, price, pname, cid, sid, stid, cname, sname, stname in product_details
) + ";\n")

# sales
lines.append(f"-- sales ({len(sales)} rows)")
batch_size = 500
for i in range(0, len(sales), batch_size):
    batch = sales[i:i + batch_size]
    lines.append("INSERT INTO sales (prod_id, qty, price, discount, member, txn_id, start_txn_time) VALUES")
    lines.append(",\n".join(
        f"({sql_str(pid)}, {qty}, {price}, {disc}, {sql_bool(mem)}, {sql_str(tid)}, {sql_ts(ts)})"
        for pid, qty, price, disc, mem, tid, ts in batch
    ) + ";\n")

with open(OUTPUT_FILE, "w") as f:
    f.write("\n".join(lines))

print(f"Generated {len(product_hierarchy)} hierarchy rows")
print(f"Generated {len(product_prices)} product prices")
print(f"Generated {len(product_details)} products")
print(f"Generated {len(sales)} sales rows across {NUM_TRANSACTIONS} transactions")
print(f"Written to {OUTPUT_FILE}")
