"""
generate_data.py
Generates a realistic synthetic data_mart.weekly_sales dataset, written
out as SQL INSERT statements (02_seed_data.sql).

Design choices:
- Weekly grain, every Monday, from the first Monday of 2018 through the
  last Monday of 2020 (matches the case study's "2018, 2019, or 2020"
  calendar_year requirement)
- week_date is written in the SAME D/M/YY string format as the case
  study's own example rows (e.g. "9/9/20"), so the date-parsing step in
  the cleaning script is a genuine, necessary step rather than a no-op
- Dimensions: region, platform, segment, customer_type - all drawn from
  the exact value sets implied by the case study's example rows and
  column dictionary
- A DELIBERATE sales dip is built in starting the week of 2020-06-15 (the
  real packaging-change event date), so the before/after analysis in
  Section 3 has a genuine signal to detect rather than just noise.
  The dip is NOT uniform - some regions/platforms/segments are hit harder
  than others, so the bonus "which area was hit hardest" question
  (Section 4) has a real, non-trivial answer.
- ~5% of rows have a NULL segment (matches the case study's own example
  rows, several of which show "null" for segment)
"""

import random
from datetime import date, timedelta

random.seed(42)

OUTPUT_FILE = "/home/claude/data-mart/sql/02_seed_data.sql"

REGIONS = ["AFRICA", "ASIA", "OCEANIA", "EUROPE", "SOUTH AMERICA", "CANADA", "USA"]
PLATFORMS = ["Retail", "Shopify"]
SEGMENTS = ["C1", "C2", "C3", "C4", "F1", "F2", "F3"]
CUSTOMER_TYPES = ["New", "Existing", "Guest"]

# Each region has a different base weekly transaction volume and a
# different platform mix - bigger/more developed regions skew more Retail,
# smaller/newer ones skew more Shopify. This isn't load-bearing for the
# analysis, just there to avoid every region looking identical.
REGION_BASE_VOLUME = {
    "AFRICA": 28000,
    "ASIA": 32000,
    "OCEANIA": 38000,
    "EUROPE": 22000,
    "SOUTH AMERICA": 9000,
    "CANADA": 7000,
    "USA": 5500,
}
REGION_RETAIL_SHARE = {
    "AFRICA": 0.82, "ASIA": 0.80, "OCEANIA": 0.78, "EUROPE": 0.74,
    "SOUTH AMERICA": 0.55, "CANADA": 0.45, "USA": 0.40,
}

# Per-region impact multiplier applied to the post-change dip (1.0 = average
# dip, >1.0 = hit harder, <1.0 = hit less). Chosen so OCEANIA (Danny's real-
# world basis, Australia) is hit hardest, matching the case study's framing.
REGION_IMPACT = {
    "OCEANIA": 1.6, "EUROPE": 1.2, "AFRICA": 1.0, "ASIA": 0.9,
    "SOUTH AMERICA": 0.7, "CANADA": 0.6, "USA": 0.5,
}
PLATFORM_IMPACT = {"Retail": 1.3, "Shopify": 0.6}
SEGMENT_IMPACT = {  # retirees (3/4) assumed more sensitive to packaging changes than young adults
    "C1": 0.7, "C2": 0.9, "C3": 1.3, "C4": 1.3,
    "F1": 0.7, "F2": 0.9, "F3": 1.2,
}
CUSTOMER_TYPE_IMPACT = {"New": 1.4, "Existing": 0.8, "Guest": 1.0}

CHANGE_DATE = date(2020, 6, 15)
START_DATE = date(2018, 1, 1)
END_DATE = date(2020, 12, 31)


def all_mondays(start, end):
    # first Monday on/after start
    d = start + timedelta(days=(7 - start.weekday()) % 7)
    out = []
    while d <= end:
        out.append(d)
        d += timedelta(days=7)
    return out


# Deliberately drop a handful of weeks so the "which week numbers are
# missing" exploration question (Section 2, Q2) has a genuine, non-trivial
# answer rather than "none are missing" - this mirrors the real published
# dataset, which is also missing several week numbers by design.
DROPPED_WEEK_NUMBERS = {1, 53}  # drop the partial first/last weeks of each year


def week_number_of(d):
    return -(-d.timetuple().tm_yday // 7)  # ceil(day_of_year / 7), no imports needed


def fmt_date(d):
    # D/M/YY, no leading zeros - matches the case study's own example rows
    return f"{d.day}/{d.month}/{d.year % 100}"


def sql_str(s):
    return "'" + str(s).replace("'", "''") + "'"


weeks = all_mondays(START_DATE, END_DATE)
weeks = [w for w in weeks if week_number_of(w) not in DROPPED_WEEK_NUMBERS]
rows = []

for week_date in weeks:
    # Mild overall year-over-year growth + small seasonal wave, applied
    # before any post-change dip
    year_growth = 1.0 + 0.06 * (week_date.year - 2018)
    seasonal = 1.0 + 0.10 * (1 if week_date.month in (11, 12) else 0)  # holiday bump

    is_post_change = week_date >= CHANGE_DATE
    weeks_since_change = (week_date - CHANGE_DATE).days / 7 if is_post_change else 0
    # dip is strongest right at the change, recovers gradually over ~20 weeks
    recovery_factor = max(0.0, 1 - weeks_since_change / 20) if is_post_change else 0.0

    for region in REGIONS:
        base_region_volume = REGION_BASE_VOLUME[region]
        retail_share = REGION_RETAIL_SHARE[region]

        for platform in PLATFORMS:
            platform_share = retail_share if platform == "Retail" else (1 - retail_share)
            platform_volume = base_region_volume * platform_share

            for segment in SEGMENTS + [None]:
                # NULL segment rows are rarer (~8% of combinations) and lower volume
                if segment is None:
                    segment_share = 0.08
                else:
                    segment_share = (1 - 0.08) / len(SEGMENTS)

                for customer_type in CUSTOMER_TYPES:
                    ct_share = {"New": 0.35, "Existing": 0.45, "Guest": 0.20}[customer_type]

                    expected_transactions = (
                        platform_volume * segment_share * ct_share
                        * year_growth * seasonal
                    )
                    if expected_transactions < 1:
                        continue  # skip negligible combinations entirely, not every combo needs a row

                    # Apply the post-change dip, scaled by region/platform/segment/customer_type
                    # sensitivity, only to rows after the change date
                    if is_post_change and recovery_factor > 0:
                        seg_key = segment if segment is not None else "C2"  # treat unknowns as average
                        impact = (
                            REGION_IMPACT[region]
                            * PLATFORM_IMPACT[platform]
                            * SEGMENT_IMPACT[seg_key]
                            * CUSTOMER_TYPE_IMPACT[customer_type]
                        )
                        # normalize impact roughly around 1.0, cap the max dip at 35%
                        dip_pct = min(0.35, 0.12 * impact) * recovery_factor
                        expected_transactions *= (1 - dip_pct)

                    # add noise so weeks aren't perfectly smooth
                    noise = random.uniform(0.85, 1.15)
                    transactions = max(1, int(expected_transactions * noise))

                    # average transaction value varies a bit by platform/segment,
                    # is NOT affected by the dip (the dip hits transaction COUNT,
                    # i.e. fewer purchases, not basket size - a deliberate and
                    # realistic modeling choice worth calling out in the README)
                    base_avg_value = {
                        "Retail": random.uniform(22, 30),
                        "Shopify": random.uniform(16, 24),
                    }[platform]
                    sales = round(transactions * base_avg_value * random.uniform(0.95, 1.05), 2)

                    rows.append((
                        fmt_date(week_date), region, platform,
                        segment, customer_type, transactions, sales
                    ))

lines = []
lines.append("-- ============================================================")
lines.append("-- Data Mart - Seed Data (synthetically generated)")
lines.append("-- File: 02_seed_data.sql")
lines.append(f"-- Generated by scripts/generate_data.py, seed=42, {len(rows)} rows")
lines.append("--")
lines.append("-- week_date is written in the same D/M/YY string format as the case")
lines.append("-- study's own example rows on purpose - parsing this into a real DATE")
lines.append("-- is the first required cleaning step, not something assumed away here.")
lines.append("--")
lines.append("-- A deliberate, non-uniform sales dip is built in starting the week of")
lines.append("-- 2020-06-15 (the real packaging-change date), strongest in OCEANIA /")
lines.append("-- Retail / older-skewing segments / New customers, recovering gradually")
lines.append("-- over about 20 weeks - so the before/after and bonus questions in this")
lines.append("-- case study have a genuine signal to detect.")
lines.append("-- ============================================================")
lines.append("SET search_path TO data_mart;\n")

batch_size = 1000
for i in range(0, len(rows), batch_size):
    batch = rows[i:i + batch_size]
    lines.append("INSERT INTO weekly_sales (week_date, region, platform, segment, customer_type, transactions, sales) VALUES")
    row_strs = []
    for wd, region, platform, segment, ctype, txn, sales in batch:
        seg_sql = sql_str(segment) if segment is not None else "NULL"
        row_strs.append(
            f"({sql_str(wd)}, {sql_str(region)}, {sql_str(platform)}, {seg_sql}, {sql_str(ctype)}, {txn}, {sales})"
        )
    lines.append(",\n".join(row_strs) + ";\n")

with open(OUTPUT_FILE, "w") as f:
    f.write("\n".join(lines))

print(f"Generated {len(rows)} rows across {len(weeks)} weeks "
      f"({weeks[0]} to {weeks[-1]}, with week numbers {sorted(DROPPED_WEEK_NUMBERS)} dropped from every year).")
print(f"Written to {OUTPUT_FILE}")
