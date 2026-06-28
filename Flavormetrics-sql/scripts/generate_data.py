"""
generate_data.py
Generates realistic synthetic data for the FlavorMetrics project and
writes it out as SQL INSERT statements (02_seed_data.sql).

Design choices made to keep the data "realistic" rather than purely random:
- Customer behavior follows an 80/20-ish pattern: a minority of customers
  order far more frequently than the majority (regulars vs. occasional visitors)
- Order volume has weekly seasonality (weekends busier) and a mild
  month-over-month growth trend (the chain is growing)
- Loyalty members are a subset of customers, and members get a small
  spending bump after their join_date (simulates real loyalty lift)
- Each store has a different launch date, so total transaction volume
  per store differs naturally
"""

import random
from datetime import date, timedelta

random.seed(42)  # reproducible dataset

OUTPUT_FILE = "/home/claude/restaurant-analytics/sql/02_seed_data.sql"

# ----------------------------------------------------------------------
# 1. STORES
# ----------------------------------------------------------------------
stores = [
    (1, "FlavorMetrics - Koramangala", "Bengaluru", date(2023, 1, 15)),
    (2, "FlavorMetrics - Andheri",      "Mumbai",    date(2023, 4, 1)),
    (3, "FlavorMetrics - Hauz Khas",    "Delhi",     date(2023, 7, 10)),
]

# ----------------------------------------------------------------------
# 2. MENU ITEMS  (price > cost always, margin varies by category)
# ----------------------------------------------------------------------
menu_items = [
    (1,  "Veg Sushi Roll",       "Sushi",      220.00, 95.00),
    (2,  "Salmon Sushi Roll",    "Sushi",      320.00, 160.00),
    (3,  "Chicken Katsu Curry",  "Curry",      280.00, 110.00),
    (4,  "Paneer Butter Curry",  "Curry",      250.00, 90.00),
    (5,  "Tonkotsu Ramen",       "Ramen",      310.00, 130.00),
    (6,  "Veg Miso Ramen",       "Ramen",      270.00, 95.00),
    (7,  "Edamame",              "Starter",     90.00, 30.00),
    (8,  "Gyoza (6 pc)",         "Starter",    160.00, 60.00),
    (9,  "Iced Matcha Latte",    "Beverage",   150.00, 45.00),
    (10, "Lychee Soda",          "Beverage",   120.00, 35.00),
    (11, "Mochi Ice Cream",      "Dessert",    140.00, 50.00),
    (12, "Dorayaki",             "Dessert",    110.00, 35.00),
]

# ----------------------------------------------------------------------
# 3. STAFF
# ----------------------------------------------------------------------
staff = [
    (1, "Aarav Mehta",   1, "Chef"),
    (2, "Priya Nair",    1, "Server"),
    (3, "Rohan Kapoor",  1, "Server"),
    (4, "Sneha Iyer",    2, "Chef"),
    (5, "Kunal Verma",   2, "Server"),
    (6, "Isha Reddy",    2, "Server"),
    (7, "Vivaan Shah",   3, "Chef"),
    (8, "Ananya Joshi",  3, "Server"),
]

# ----------------------------------------------------------------------
# 4. CUSTOMERS
# ----------------------------------------------------------------------
FIRST_NAMES = [
    "Aditi","Arjun","Diya","Kabir","Meera","Rahul","Sara","Vikram","Tanya","Ishaan",
    "Neha","Rohit","Pooja","Aman","Riya","Karan","Simran","Yash","Anjali","Dev",
    "Naina","Siddharth","Ritika","Manav","Pallavi","Gaurav","Shreya","Nikhil","Tara","Aryan",
    "Bhavna","Chirag","Divya","Eshan","Falguni","Gautam","Hema","Imran","Jaya","Kunal",
    "Lakshmi","Madhav","Nisha","Om","Preeti","Qasim","Radhika","Sahil","Tanvi","Uday",
]

CITIES = ["Bengaluru", "Mumbai", "Delhi", "Pune", "Hyderabad"]

NUM_CUSTOMERS = 120
customers = []
start_window = date(2023, 1, 15)
end_window = date(2024, 12, 31)
total_days = (end_window - start_window).days

for cid in range(1, NUM_CUSTOMERS + 1):
    name = random.choice(FIRST_NAMES)
    signup_offset = random.randint(0, total_days - 30)  # leave room for activity after signup
    signup_date = start_window + timedelta(days=signup_offset)
    home_city = random.choice(CITIES)
    customers.append((cid, name, signup_date, home_city))

# ----------------------------------------------------------------------
# 5. CUSTOMER SEGMENTS (drives realistic order frequency distribution)
#    ~15% regulars, ~35% occasional, ~50% one-to-few-timers
# ----------------------------------------------------------------------
segment_roll = random.choices(
    population=["regular", "occasional", "rare"],
    weights=[0.15, 0.35, 0.50],
    k=NUM_CUSTOMERS,
)
customer_segment = {cid: seg for cid, seg in zip(range(1, NUM_CUSTOMERS + 1), segment_roll)}

ORDERS_RANGE = {
    "regular":    (25, 60),
    "occasional": (6, 18),
    "rare":       (1, 5),
}

# ----------------------------------------------------------------------
# 6. LOYALTY MEMBERS
#    ~40% of customers are members; they join sometime after signup
# ----------------------------------------------------------------------
loyalty_members = []
is_member = {}
for cid, name, signup_date, home_city in customers:
    if random.random() < 0.40:
        join_offset = random.randint(3, 90)
        join_date = signup_date + timedelta(days=join_offset)
        if join_date > end_window:
            join_date = end_window
        tier = random.choices(
            population=["Silver", "Gold", "Platinum"],
            weights=[0.55, 0.32, 0.13],
            k=1,
        )[0]
        loyalty_members.append((cid, join_date, tier))
        is_member[cid] = join_date
    else:
        is_member[cid] = None

# ----------------------------------------------------------------------
# 7. ORDERS + ORDER_ITEMS
#    Weekly seasonality: Fri/Sat/Sun busier.
#    Members get a mild post-join order-frequency bump.
# ----------------------------------------------------------------------
DOW_WEIGHTS = {0: 0.9, 1: 0.85, 2: 0.9, 3: 1.0, 4: 1.3, 5: 1.5, 6: 1.4}  # Mon=0 ... Sun=6

orders = []
order_items = []
order_id_counter = 1
order_item_id_counter = 1

store_open_dates = {sid: opened for sid, _, _, opened in stores}

for cid, name, signup_date, home_city in customers:
    seg = customer_segment[cid]
    n_orders = random.randint(*ORDERS_RANGE[seg])

    member_join = is_member[cid]
    if member_join:
        n_orders = int(n_orders * 1.15)  # loyalty lift

    active_start = signup_date
    active_end = end_window
    active_days = max((active_end - active_start).days, 1)

    # Assign customer to a "home store" (most of their orders happen there)
    eligible_stores = [sid for sid, opened in store_open_dates.items() if opened <= active_start]
    if not eligible_stores:
        eligible_stores = [1]  # fallback to flagship store
    home_store = random.choice(eligible_stores)

    placed_dates = set()
    attempts = 0
    while len(placed_dates) < n_orders and attempts < n_orders * 8:
        attempts += 1
        offset = random.randint(0, active_days)
        candidate_date = active_start + timedelta(days=offset)
        dow = candidate_date.weekday()
        weight = DOW_WEIGHTS[dow]
        if random.random() <= (weight / 1.5):
            placed_dates.add(candidate_date)

    for od in sorted(placed_dates):
        # 90% of the time order at home store, 10% a different (open) store
        open_stores_now = [sid for sid, opened in store_open_dates.items() if opened <= od]
        if not open_stores_now:
            continue
        if random.random() < 0.9 and home_store in open_stores_now:
            store_id = home_store
        else:
            store_id = random.choice(open_stores_now)

        hour = random.choices(
            population=[12, 13, 19, 20, 21],
            weights=[0.15, 0.15, 0.25, 0.25, 0.20],
            k=1,
        )[0]
        minute = random.randint(0, 59)
        order_time = f"{hour:02d}:{minute:02d}:00"

        eligible_staff = [s for s in staff if s[2] == store_id]
        staff_id = random.choice(eligible_staff)[0] if eligible_staff else None

        orders.append((order_id_counter, cid, store_id, staff_id, od, order_time))

        # 1-4 line items per order, weighted toward 1-2
        n_items = random.choices([1, 2, 3, 4], weights=[0.35, 0.40, 0.18, 0.07], k=1)[0]
        chosen_products = random.sample([m[0] for m in menu_items], k=min(n_items, len(menu_items)))
        for pid in chosen_products:
            qty = random.choices([1, 2, 3], weights=[0.75, 0.20, 0.05], k=1)[0]
            order_items.append((order_item_id_counter, order_id_counter, pid, qty))
            order_item_id_counter += 1

        order_id_counter += 1

# ----------------------------------------------------------------------
# WRITE SQL FILE
# ----------------------------------------------------------------------
def sql_str(s):
    return "'" + str(s).replace("'", "''") + "'"

lines = []
lines.append("-- ============================================================")
lines.append("-- FlavorMetrics: Seed Data (synthetically generated, but with")
lines.append("-- realistic distributions: customer segments, weekly seasonality,")
lines.append("-- loyalty lift). Generated by generate_data.py with seed=42.")
lines.append("-- File: 02_seed_data.sql")
lines.append("-- ============================================================")
lines.append("SET search_path TO flavormetrics;\n")

lines.append("-- stores")
lines.append("INSERT INTO stores (store_id, store_name, city, opened_date) VALUES")
lines.append(",\n".join(
    f"({sid}, {sql_str(name)}, {sql_str(city)}, {sql_str(opened)})"
    for sid, name, city, opened in stores
) + ";\n")

lines.append("-- menu_items")
lines.append("INSERT INTO menu_items (product_id, product_name, category, price, cost) VALUES")
lines.append(",\n".join(
    f"({pid}, {sql_str(pname)}, {sql_str(cat)}, {price:.2f}, {cost:.2f})"
    for pid, pname, cat, price, cost in menu_items
) + ";\n")

lines.append("-- staff")
lines.append("INSERT INTO staff (staff_id, staff_name, store_id, role) VALUES")
lines.append(",\n".join(
    f"({sid}, {sql_str(name)}, {store_id}, {sql_str(role)})"
    for sid, name, store_id, role in staff
) + ";\n")

lines.append("-- customers")
lines.append("INSERT INTO customers (customer_id, first_name, signup_date, home_city) VALUES")
lines.append(",\n".join(
    f"({cid}, {sql_str(name)}, {sql_str(signup_date)}, {sql_str(home_city)})"
    for cid, name, signup_date, home_city in customers
) + ";\n")

lines.append("-- loyalty_members")
lines.append("INSERT INTO loyalty_members (customer_id, join_date, tier) VALUES")
lines.append(",\n".join(
    f"({cid}, {sql_str(join_date)}, {sql_str(tier)})"
    for cid, join_date, tier in loyalty_members
) + ";\n")

# Orders in batches (could be thousands of rows)
lines.append(f"-- orders ({len(orders)} rows)")
batch_size = 500
for i in range(0, len(orders), batch_size):
    batch = orders[i:i+batch_size]
    lines.append("INSERT INTO orders (order_id, customer_id, store_id, staff_id, order_date, order_time) VALUES")
    lines.append(",\n".join(
        f"({oid}, {cid}, {sid}, {staff_id if staff_id else 'NULL'}, {sql_str(od)}, {sql_str(ot)})"
        for oid, cid, sid, staff_id, od, ot in batch
    ) + ";\n")

lines.append(f"-- order_items ({len(order_items)} rows)")
for i in range(0, len(order_items), batch_size):
    batch = order_items[i:i+batch_size]
    lines.append("INSERT INTO order_items (order_item_id, order_id, product_id, quantity) VALUES")
    lines.append(",\n".join(
        f"({oiid}, {oid}, {pid}, {qty})"
        for oiid, oid, pid, qty in batch
    ) + ";\n")

with open(OUTPUT_FILE, "w") as f:
    f.write("\n".join(lines))

print(f"Generated {len(stores)} stores, {len(menu_items)} menu items, {len(staff)} staff,")
print(f"{len(customers)} customers, {len(loyalty_members)} loyalty members,")
print(f"{len(orders)} orders, {len(order_items)} order_items.")
print(f"Written to {OUTPUT_FILE}")
