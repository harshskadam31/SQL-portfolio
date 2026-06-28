"""
generate_data.py
Generates a realistic synthetic Foodie-Fi customer base, written out as
SQL INSERT statements (03_seed_data_synthetic.sql).

Business rules being modeled (per the case study):
- Every customer starts on a 7-day free trial (plan_id 0)
- If they take no action, the trial auto-converts to pro monthly (plan_id 2)
  on day 8
- During or after the trial, a customer can instead:
    - downgrade to basic monthly (plan_id 1)
    - upgrade directly to pro annual (plan_id 3)
    - churn (plan_id 4) - cancels, keeps access until period end
- From basic monthly, a customer can later upgrade to pro monthly or pro
  annual, or churn
- From pro monthly, a customer can upgrade to pro annual, downgrade to
  basic monthly, or churn
- pro annual is terminal except for churn (no further upgrades possible)
- churn is terminal - no further plan rows after it

Customer archetypes (drives realistic distribution, not pure randomness):
  - "annual_upgrader"   : trial -> pro monthly -> pro annual (the ideal funnel)
  - "loyal_pro"         : trial -> pro monthly, stays indefinitely
  - "budget_basic"      : trial -> basic monthly, stays indefinitely
  - "budget_to_pro"     : trial -> basic monthly -> pro monthly (upsell)
  - "trial_churn"       : trial -> churn immediately (never converts)
  - "early_churn"       : trial -> pro monthly -> churn within a few months
  - "late_churn"        : trial -> pro monthly -> pro annual -> churn
  - "downgrade"         : trial -> pro monthly -> basic monthly

Customer IDs 1-19 are reserved to match the published sample rows exactly
(see 02_seed_data_sample.sql); synthetic customers start at 101.
"""

import random
from datetime import date, timedelta

random.seed(42)

OUTPUT_FILE = "/home/claude/foodie-fi/sql/03_seed_data_synthetic.sql"

NUM_CUSTOMERS = 250
START_ID = 101

# Signups spread across the business's first ~16 months (matches the
# 2020-03 to 2021-04 range implied by the sample data)
SIGNUP_WINDOW_START = date(2020, 1, 1)
SIGNUP_WINDOW_END = date(2021, 6, 30)
DATA_END = date(2021, 12, 31)  # no events generated after this

ARCHETYPE_WEIGHTS = {
    "annual_upgrader": 0.16,
    "loyal_pro":        0.22,
    "budget_basic":     0.14,
    "budget_to_pro":    0.08,
    "trial_churn":      0.12,
    "early_churn":      0.12,
    "late_churn":       0.06,
    "downgrade":        0.10,
}

PRICES = {0: 0, 1: 9.90, 2: 19.90, 3: 199.00, 4: None}


def add_months(d, n):
    month = d.month - 1 + n
    year = d.year + month // 12
    month = month % 12 + 1
    day = min(d.day, 28)  # avoid month-length issues; fine for this purpose
    return date(year, month, day)


def random_signup():
    span = (SIGNUP_WINDOW_END - SIGNUP_WINDOW_START).days
    return SIGNUP_WINDOW_START + timedelta(days=random.randint(0, span))


def build_journey(customer_id, archetype, signup):
    """Returns a list of (customer_id, plan_id, start_date) tuples."""
    rows = [(customer_id, 0, signup)]
    trial_end = signup + timedelta(days=7)

    def cap(d):
        return min(d, DATA_END)

    if archetype == "annual_upgrader":
        rows.append((customer_id, 2, cap(trial_end)))
        months_to_upgrade = random.randint(1, 6)
        upgrade_date = add_months(trial_end, months_to_upgrade)
        if upgrade_date <= DATA_END:
            rows.append((customer_id, 3, upgrade_date))

    elif archetype == "loyal_pro":
        rows.append((customer_id, 2, cap(trial_end)))
        # no further changes - stays on pro monthly indefinitely

    elif archetype == "budget_basic":
        rows.append((customer_id, 1, cap(trial_end)))
        # stays on basic monthly indefinitely

    elif archetype == "budget_to_pro":
        rows.append((customer_id, 1, cap(trial_end)))
        months_to_upgrade = random.randint(1, 8)
        upgrade_date = add_months(trial_end, months_to_upgrade)
        if upgrade_date <= DATA_END:
            rows.append((customer_id, 2, upgrade_date))

    elif archetype == "trial_churn":
        rows.append((customer_id, 4, cap(trial_end)))

    elif archetype == "early_churn":
        rows.append((customer_id, 2, cap(trial_end)))
        months_to_churn = random.randint(1, 3)
        churn_date = add_months(trial_end, months_to_churn)
        if churn_date <= DATA_END:
            rows.append((customer_id, 4, churn_date))

    elif archetype == "late_churn":
        rows.append((customer_id, 2, cap(trial_end)))
        months_to_upgrade = random.randint(1, 4)
        upgrade_date = add_months(trial_end, months_to_upgrade)
        if upgrade_date <= DATA_END:
            rows.append((customer_id, 3, upgrade_date))
            months_to_churn = random.randint(2, 10)
            churn_date = add_months(upgrade_date, months_to_churn)
            if churn_date <= DATA_END:
                rows.append((customer_id, 4, churn_date))

    elif archetype == "downgrade":
        rows.append((customer_id, 2, cap(trial_end)))
        months_to_downgrade = random.randint(1, 5)
        downgrade_date = add_months(trial_end, months_to_downgrade)
        if downgrade_date <= DATA_END:
            rows.append((customer_id, 1, downgrade_date))

    return rows


def sql_str(s):
    return "'" + str(s) + "'"


all_rows = []
archetypes_assigned = random.choices(
    population=list(ARCHETYPE_WEIGHTS.keys()),
    weights=list(ARCHETYPE_WEIGHTS.values()),
    k=NUM_CUSTOMERS,
)

for i in range(NUM_CUSTOMERS):
    customer_id = START_ID + i
    archetype = archetypes_assigned[i]
    signup = random_signup()
    journey = build_journey(customer_id, archetype, signup)
    all_rows.extend(journey)

# Sanity assertion: every customer's rows must be in strictly increasing
# date order (no plan can start before the previous one)
by_customer = {}
for cid, pid, sd in all_rows:
    by_customer.setdefault(cid, []).append((pid, sd))
for cid, events in by_customer.items():
    dates = [sd for _, sd in events]
    assert dates == sorted(dates), f"Customer {cid} has out-of-order dates"
    assert len(set(dates)) == len(dates), f"Customer {cid} has duplicate dates"

lines = []
lines.append("-- ============================================================")
lines.append("-- Foodie-Fi - Synthetic Customer Base")
lines.append("-- File: 03_seed_data_synthetic.sql")
lines.append(f"-- Generated by scripts/generate_data.py, seed=42, {NUM_CUSTOMERS} customers")
lines.append("-- Customer IDs start at 101 to avoid colliding with the published")
lines.append("-- sample customers (1-19) loaded in 02_seed_data_sample.sql.")
lines.append("-- ============================================================")
lines.append("SET search_path TO foodie_fi;\n")

batch_size = 500
lines.append(f"-- subscriptions ({len(all_rows)} rows)")
for i in range(0, len(all_rows), batch_size):
    batch = all_rows[i:i + batch_size]
    lines.append("INSERT INTO subscriptions (customer_id, plan_id, start_date) VALUES")
    lines.append(",\n".join(
        f"({cid}, {pid}, {sql_str(sd)})" for cid, pid, sd in batch
    ) + ";\n")

with open(OUTPUT_FILE, "w") as f:
    f.write("\n".join(lines))

print(f"Generated {NUM_CUSTOMERS} synthetic customers, {len(all_rows)} subscription rows.")
print(f"Written to {OUTPUT_FILE}")
