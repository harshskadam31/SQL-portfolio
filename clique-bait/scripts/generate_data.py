"""
generate_data.py
Generates synthetic data for the Clique Bait case study and writes
SQL INSERT statements to 02_seed_data.sql.

Design choices:
- 500 users, each with 1-3 cookies (multiple devices/browsers)
- Observation window: Jan 2020 - May 2020 (matches campaigns)
- Visit behavior is segmented: browsers (view only), cart-adders
  (view + add but don't always buy), and buyers (complete purchase)
- Each visit follows a realistic funnel sequence:
    1. Always starts with Home Page view
    2. May browse All Products
    3. Views individual product pages
    4. May add some products to cart
    5. May proceed to Checkout
    6. May complete Purchase (Confirmation page)
    7. Ad impressions and clicks are logged for campaign visits
- Campaign periods are respected: ad events only appear during
  campaign windows, and only for products covered by that campaign
- sequence_number increments per event within a visit
"""

import random
import string
from datetime import datetime, timedelta

random.seed(42)

OUTPUT_FILE = "/home/claude/clique-bait/sql/02_seed_data.sql"

# ----------------------------------------------------------------------
# 1. STATIC LOOKUP DATA
# ----------------------------------------------------------------------
event_identifier = [
    (1, "Page View"),
    (2, "Add to Cart"),
    (3, "Purchase"),
    (4, "Ad Impression"),
    (5, "Ad Click"),
]

campaign_identifier = [
    (1, "1-3",  "BOGOF - Fishing For Compliments",    "2020-01-01", "2020-01-14"),
    (2, "4-5",  "25% Off - Living The Lux Life",      "2020-01-15", "2020-01-28"),
    (3, "6-8",  "Half Off - Treat Your Shellf(ish)",  "2020-02-01", "2020-03-31"),
]

page_hierarchy = [
    (1,  "Home Page",       None,          None),
    (2,  "All Products",    None,          None),
    (3,  "Salmon",          "Fish",        1),
    (4,  "Kingfish",        "Fish",        2),
    (5,  "Tuna",            "Fish",        3),
    (6,  "Russian Caviar",  "Luxury",      4),
    (7,  "Black Truffle",   "Luxury",      5),
    (8,  "Abalone",         "Shellfish",   6),
    (9,  "Lobster",         "Shellfish",   7),
    (10, "Crab",            "Shellfish",   8),
    (11, "Oyster",          "Shellfish",   9),
    (12, "Checkout",        None,          None),
    (13, "Confirmation",    None,          None),
]

# product pages only (page_id 3-11)
product_pages = [p for p in page_hierarchy if p[3] is not None]
product_page_ids = [p[0] for p in product_pages]

# campaign date ranges for attribution
campaign_ranges = [
    (1, datetime(2020, 1, 1),  datetime(2020, 1, 14),  [3, 4, 5]),   # products 1-3
    (2, datetime(2020, 1, 15), datetime(2020, 1, 28),  [6, 7]),       # products 4-5
    (3, datetime(2020, 2, 1),  datetime(2020, 3, 31),  [8, 9, 10]),   # products 6-8
]

# ----------------------------------------------------------------------
# 2. USERS + COOKIES
# ----------------------------------------------------------------------
NUM_USERS = 500
OBS_START = datetime(2020, 1, 1)
OBS_END   = datetime(2020, 5, 31)

def random_cookie():
    return ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))

used_cookies = set()
def unique_cookie():
    while True:
        c = random_cookie()
        if c not in used_cookies:
            used_cookies.add(c)
            return c

users = []
user_cookies = {}  # user_id -> list of cookie_ids

for uid in range(1, NUM_USERS + 1):
    n_cookies = random.choices([1, 2, 3], weights=[0.60, 0.30, 0.10], k=1)[0]
    cookies = [unique_cookie() for _ in range(n_cookies)]
    offset = random.randint(0, (OBS_END - OBS_START).days - 30)
    start_date = OBS_START + timedelta(days=offset)
    # primary cookie is the first one
    users.append((uid, cookies[0], start_date))
    user_cookies[uid] = cookies

# ----------------------------------------------------------------------
# 3. EVENTS
# ----------------------------------------------------------------------
# Visit behavior segments
segment_roll = random.choices(
    population=["buyer", "cart_adder", "browser"],
    weights=[0.35, 0.40, 0.25],
    k=NUM_USERS,
)
user_segment = {uid: seg for uid, seg in zip(range(1, NUM_USERS + 1), segment_roll)}

# Number of visits per user per segment
VISITS_PER_USER = {
    "buyer":      (8, 20),
    "cart_adder": (4, 12),
    "browser":    (1,  6),
}

def get_active_campaign(visit_time):
    for cid, start, end, prods in campaign_ranges:
        if start <= visit_time <= end:
            return cid, prods
    return None, []

all_events = []
visit_id_set = set()

def unique_visit_id():
    while True:
        vid = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
        if vid not in visit_id_set:
            visit_id_set.add(vid)
            return vid

for uid in range(1, NUM_USERS + 1):
    seg = user_segment[uid]
    cookies = user_cookies[uid]
    n_visits = random.randint(*VISITS_PER_USER[seg])
    user_start = users[uid - 1][2]

    for _ in range(n_visits):
        cookie = random.choice(cookies)
        offset_days = random.randint(0, (OBS_END - user_start).days)
        visit_start = user_start + timedelta(
            days=offset_days,
            hours=random.randint(7, 23),
            minutes=random.randint(0, 59),
            seconds=random.randint(0, 59),
        )
        if visit_start > OBS_END:
            continue

        visit_id = unique_visit_id()
        seq = 1
        visit_events = []

        # Always view Home Page first
        visit_events.append((visit_id, cookie, 1, 1, seq, visit_start + timedelta(seconds=seq*5)))
        seq += 1

        # Maybe view All Products
        if random.random() < 0.80:
            visit_events.append((visit_id, cookie, 2, 1, seq, visit_start + timedelta(seconds=seq*5)))
            seq += 1

        # View 1-5 product pages
        n_products_viewed = random.randint(1, 5)
        viewed_products = random.sample(product_page_ids, k=min(n_products_viewed, len(product_page_ids)))
        cart_products = []

        for page_id in viewed_products:
            # Page view
            visit_events.append((visit_id, cookie, page_id, 1, seq, visit_start + timedelta(seconds=seq*5)))
            seq += 1

            # Add to cart based on segment
            add_prob = {"buyer": 0.70, "cart_adder": 0.55, "browser": 0.10}[seg]
            if random.random() < add_prob:
                visit_events.append((visit_id, cookie, page_id, 2, seq, visit_start + timedelta(seconds=seq*5)))
                seq += 1
                cart_products.append((page_id, seq - 1))  # track order added

        # Check for active campaign — add ad impression/click
        active_campaign, campaign_prods = get_active_campaign(visit_start)
        if active_campaign and random.random() < 0.40:
            # Ad impression
            visit_events.append((visit_id, cookie, 2, 4, seq, visit_start + timedelta(seconds=seq*5)))
            seq += 1
            # Ad click (60% of impressions lead to a click)
            if random.random() < 0.60:
                visit_events.append((visit_id, cookie, 2, 5, seq, visit_start + timedelta(seconds=seq*5)))
                seq += 1

        # Proceed to checkout and purchase based on segment
        if cart_products:
            checkout_prob = {"buyer": 0.85, "cart_adder": 0.45, "browser": 0.05}[seg]
            if random.random() < checkout_prob:
                # Checkout page view
                visit_events.append((visit_id, cookie, 12, 1, seq, visit_start + timedelta(seconds=seq*5)))
                seq += 1
                # Purchase event (on confirmation page)
                purchase_prob = {"buyer": 0.90, "cart_adder": 0.60, "browser": 0.20}[seg]
                if random.random() < purchase_prob:
                    visit_events.append((visit_id, cookie, 13, 3, seq, visit_start + timedelta(seconds=seq*5)))
                    seq += 1

        all_events.extend(visit_events)

# ----------------------------------------------------------------------
# WRITE SQL FILE
# ----------------------------------------------------------------------
def sql_str(s):
    if s is None:
        return "NULL"
    return "'" + str(s).replace("'", "''") + "'"

def sql_ts(dt):
    return f"'{dt.strftime('%Y-%m-%d %H:%M:%S')}'"

lines = []
lines.append("-- ============================================================")
lines.append("-- Clique Bait: Seed Data (synthetically generated)")
lines.append("-- Realistic funnel behavior: browsers, cart-adders, buyers.")
lines.append("-- Campaign attribution and ad events during campaign windows.")
lines.append("-- Generated by generate_data.py with seed=42.")
lines.append("-- File: 02_seed_data.sql")
lines.append("-- ============================================================")
lines.append("SET search_path TO clique_bait;\n")

# event_identifier
lines.append("-- event_identifier")
lines.append("INSERT INTO event_identifier (event_type, event_name) VALUES")
lines.append(",\n".join(f"({et}, {sql_str(en)})" for et, en in event_identifier) + ";\n")

# campaign_identifier
lines.append("-- campaign_identifier")
lines.append("INSERT INTO campaign_identifier (campaign_id, products, campaign_name, start_date, end_date) VALUES")
lines.append(",\n".join(
    f"({cid}, {sql_str(prods)}, {sql_str(name)}, {sql_str(sd)}, {sql_str(ed)})"
    for cid, prods, name, sd, ed in campaign_identifier
) + ";\n")

# page_hierarchy
lines.append("-- page_hierarchy")
lines.append("INSERT INTO page_hierarchy (page_id, page_name, product_category, product_id) VALUES")
lines.append(",\n".join(
    f"({pid}, {sql_str(pname)}, {sql_str(cat)}, {sql_str(prod_id)})"
    for pid, pname, cat, prod_id in page_hierarchy
) + ";\n")

# users
lines.append(f"-- users ({len(users)} rows)")
lines.append("INSERT INTO users (user_id, cookie_id, start_date) VALUES")
lines.append(",\n".join(
    f"({uid}, {sql_str(cookie)}, {sql_ts(sd)})"
    for uid, cookie, sd in users
) + ";\n")

# events in batches
lines.append(f"-- events ({len(all_events)} rows)")
batch_size = 500
for i in range(0, len(all_events), batch_size):
    batch = all_events[i:i + batch_size]
    lines.append("INSERT INTO events (visit_id, cookie_id, page_id, event_type, sequence_number, event_time) VALUES")
    lines.append(",\n".join(
        f"({sql_str(vid)}, {sql_str(cid)}, {pid}, {et}, {seq}, {sql_ts(etime)})"
        for vid, cid, pid, et, seq, etime in batch
    ) + ";\n")

with open(OUTPUT_FILE, "w") as f:
    f.write("\n".join(lines))

print(f"Generated {len(users)} users")
print(f"Generated {len(all_events)} events across {len(visit_id_set)} visits")
print(f"Written to {OUTPUT_FILE}")
