"""
clean.py
--------
Turns the raw CSVs into cleaned ones, following the exact decisions
recorded in `documentation/cleaning_decisions_Profiling.csv` (the log
you exported from data_cleaning.ipynb). Every function below has a
docstring naming the issue it fixes and the evidence count from that
log, so you can trace any line of code back to the original decision.

What this file deliberately does NOT do: fabricate missing data. Every
"missing" case in the log was a decision to RETAIN the blank rather
than guess a value - this file does the same. Only genuinely INVALID
values (negative ages, out-of-range ratings, unreadable dates, etc.)
get changed, and always to NaN/NaT, never to a made-up number.

Usage:
    from ingest import load_raw
    from clean import clean_all, save_cleaned

    raw = load_raw("data/raw/")
    cleaned = clean_all(raw)
    save_cleaned(cleaned, "data/cleaned/")
"""

import re
import numpy as np
import pandas as pd

# Cities as they appear in the canonical `cities` table, vs. the messier
# names used elsewhere in the data (old names, alternate spellings).
CITY_MAPPING = {
    "New Delhi": "Delhi",
    "Bangalore": "Bengaluru",
    "Madras": "Chennai",
    "Baroda": "Vadodara",
    "Bombay": "Mumbai",
    "Calcutta": "Kolkata",
}


# =================================================================
# Shared helpers (used across multiple datasets)
# =================================================================

def strip_whitespace(datasets):
    """
    Trim leading/trailing spaces from every text column in every dataset.
    Decision: "white space around object data" - e.g. "Hyderabad" and
    " Hyderabad " were being treated as two different values.
    """
    for df in datasets.values():
        for col in df.select_dtypes(include="object").columns:
            df[col] = df[col].str.strip()
    return datasets


def standardize_cities(datasets):
    """
    Make every City column use the same spelling/casing as the master
    `cities` table (Title Case + old-name mapping like Bombay -> Mumbai).
    Decision: "not standardised as per master cities dataset with casing
    issues".
    """
    for df in datasets.values():
        if "City" in df.columns:
            df["City"] = (
                df["City"].replace("", np.nan).str.title().replace(CITY_MAPPING)
            )
    return datasets


def parse_ambiguous_date(series):
    """
    Parse a column of date-like text into real dates - but only when the
    format is unambiguous.

    Some dates in this data are like "03/04/2023": is that 3rd April or
    4th March? We genuinely can't tell, so rather than guess (and risk
    silently corrupting the analysis), we leave those as missing (NaT).
    This is the same rule used throughout the original cleaning log
    ("multiple date formats mixed DD/MM and MM/DD" -> converted to NaT).

    Formats we CAN read safely:
        YYYY-MM-DD / YYYY/MM/DD          (year always comes first, no ambiguity)
        DD-Mon-YYYY  e.g. "05-Jan-2023"  (month name removes the ambiguity)
        DD/MM/YYYY or MM/DD/YYYY         (only when one of the two numbers is > 12,
                                          which proves which one must be the day)
    """
    def parse_one(value):
        if pd.isna(value):
            return pd.NaT

        text = str(value).strip()
        separator = next((s for s in ["/", "-", ".", " "] if s in text), None)
        if separator is None:
            return pd.NaT

        parts = text.split(separator)
        if len(parts) != 3:
            return pd.NaT

        first, second, third = parts

        # YYYY-MM-DD style: year is unambiguous because it's 4 digits
        if len(first) == 4:
            try:
                return pd.Timestamp(year=int(first), month=int(second), day=int(third))
            except (ValueError, TypeError):
                return pd.NaT

        # DD-Mon-YYYY style: month name removes the ambiguity
        if not second.isdigit():
            try:
                return pd.to_datetime(text, format=f"%d{separator}%b{separator}%Y")
            except ValueError:
                return pd.NaT

        # DD/MM/YYYY vs MM/DD/YYYY: only safe to resolve if one part is > 12
        try:
            a, b, year = int(first), int(second), int(third)
        except ValueError:
            return pd.NaT

        if a > 12 and b <= 12:
            day, month = a, b
        elif b > 12 and a <= 12:
            day, month = b, a
        else:
            # both <= 12 (truly ambiguous) or both > 31 (invalid) -> can't resolve safely
            return pd.NaT

        try:
            return pd.Timestamp(year=year, month=month, day=day)
        except ValueError:
            return pd.NaT

    return series.apply(parse_one)


def clip_range(series, low, high):
    """Set any value outside [low, high] to NaN. Used for ratings, percentages, etc."""
    return series.where(series.between(low, high))


def clip_negative(series):
    """Set negative values to NaN. Used where a negative number is impossible (e.g. Age, Humidity)."""
    return series.where(series >= 0)


# =================================================================
# One function per dataset
# =================================================================

def clean_cities(cities):
    """No fixable issues found - `AverageIncome` has 2 missing values, retained as-is."""
    return cities.copy()


def _clean_phone_value(value):
    if pd.isna(value):
        return np.nan
    digits = re.sub(r"\D", "", str(value))
    if digits.startswith("91") and len(digits) == 12:
        digits = digits[2:]
    if len(digits) == 10 and digits[0] in "6789":
        return digits
    return np.nan


def _clean_pincode_value(value):
    if pd.isna(value):
        return np.nan
    text = str(value).strip()
    if text.isdigit() and len(text) == 6 and text[0] != "0":
        return text
    return np.nan


def clean_customers(customers):
    """
    - Exact duplicate rows dropped (12,180 -> 12,000)
    - Name: standardised to Title Case
    - Age: negative values (258) -> NaN
    - Phone: kept original as Phone_raw; cleaned version keeps only valid
      10-digit Indian mobile numbers (strips a leading "91" country code,
      drops anything that isn't 10 digits starting 6-9)
    - Pincode: kept original as Pincode_raw; cleaned version keeps only
      valid 6-digit pincodes (first digit can't be 0)
    - RegistrationDate: kept original as RegistrationDate_raw; ambiguous
      formats (1,420) -> NaT
    - Email duplicates, and missing Age/Gender/Phone/Email/State/
      Membership/PreferredCuisine: retained as-is (can't fabricate them)
    """
    customers = customers.drop_duplicates().copy()
    customers["Name"] = customers["Name"].str.title()
    customers["Age"] = clip_negative(customers["Age"])

    customers["Phone_raw"] = customers["Phone"]
    customers["Phone"] = customers["Phone"].apply(_clean_phone_value)

    customers["Pincode_raw"] = customers["Pincode"]
    customers["Pincode"] = customers["Pincode"].apply(_clean_pincode_value)

    customers["RegistrationDate_raw"] = customers["RegistrationDate"]
    customers["RegistrationDate"] = parse_ambiguous_date(customers["RegistrationDate"])

    return customers


def clean_restaurants(restaurants):
    """
    - RestaurantName: standardised to Title Case (140 unique -> 100 unique)
    - Rating: out-of-range values >5 (18) -> NaN
    - AverageCost: negative values (15) -> NaN
    - Missing Cuisine/Rating: retained as-is
    """
    restaurants = restaurants.copy()
    restaurants["RestaurantName"] = restaurants["RestaurantName"].str.title()
    restaurants["Rating"] = clip_range(restaurants["Rating"], 1, 5)
    restaurants["AverageCost"] = clip_negative(restaurants["AverageCost"])
    return restaurants


def clean_delivery_partners(partners):
    """
    - JoiningDate: kept original as JoiningDate_raw; ambiguous formats (237) -> NaT
    - AverageDeliveryTime: negative values (27) -> NaN
    - Missing Rating: retained as-is
    """
    partners = partners.copy()
    partners["JoiningDate_raw"] = partners["JoiningDate"]
    partners["JoiningDate"] = parse_ambiguous_date(partners["JoiningDate"])
    partners["AverageDeliveryTime"] = clip_negative(partners["AverageDeliveryTime"])
    return partners


def clean_order_items(order_items):
    """
    - Quantity: negative values (417) -> made positive (abs). Evidence:
      TotalPrice = Quantity x UnitPrice held for every row that had a
      valid TotalPrice, so the sign was simply flipped by mistake.
    - TotalPrice: missing values (435) -> calculated as Quantity x UnitPrice
    """
    order_items = order_items.copy()
    order_items["Quantity"] = order_items["Quantity"].abs()

    missing_total = order_items["TotalPrice"].isna()
    order_items.loc[missing_total, "TotalPrice"] = (
        order_items.loc[missing_total, "Quantity"] * order_items.loc[missing_total, "UnitPrice"]
    )
    return order_items


def clean_menu(menu, order_items):
    """
    - FoodName: standardised to Title Case (93 unique -> 31 unique)
    - Price: negative values (90) -> made positive (abs), but ONLY where
      order_items confirms that item really does sell around that price
      elsewhere. One entry (FoodItemID 6772) couldn't be confirmed this
      way and was set to NaN instead of guessed.
    - Missing Calories: retained as-is
    """
    menu = menu.copy()
    menu["FoodName"] = menu["FoodName"].str.title()

    unit_price_by_item = order_items.groupby("FoodItemID")["UnitPrice"].first()
    negative_rows = menu.index[menu["Price"] < 0]

    for idx in negative_rows:
        food_id = menu.loc[idx, "FoodItemID"]
        candidate_price = abs(menu.loc[idx, "Price"])
        known_price = unit_price_by_item.get(food_id)
        if known_price is not None and np.isclose(known_price, candidate_price, atol=1):
            menu.loc[idx, "Price"] = candidate_price
        else:
            menu.loc[idx, "Price"] = np.nan

    return menu


def clean_promotions(promotions):
    """
    - StartDate / EndDate: kept originals as *_raw; ambiguous formats (50, 39) -> NaT
    - Invalid StartDate > EndDate combinations (4) -> both set to NaT
    """
    promotions = promotions.copy()
    promotions["StartDate_raw"] = promotions["StartDate"]
    promotions["EndDate_raw"] = promotions["EndDate"]
    promotions["StartDate"] = parse_ambiguous_date(promotions["StartDate"])
    promotions["EndDate"] = parse_ambiguous_date(promotions["EndDate"])

    invalid_range = (
        promotions["StartDate"].notna()
        & promotions["EndDate"].notna()
        & (promotions["EndDate"] < promotions["StartDate"])
    )
    promotions.loc[invalid_range, ["StartDate", "EndDate"]] = pd.NaT

    return promotions


def clean_payments(payments):
    """
    - Exact duplicate rows dropped, keeping the first occurrence (202)
    - Duplicate OrderIDs with different TransactionIDs: retained as-is
      (can't tell which TransactionID is correct)
    - Null TransactionID values: retained as-is
    - PaymentDate: kept original as PaymentDate_raw; ambiguous formats (2,557) -> NaT
    """
    payments = payments.drop_duplicates().copy()
    payments["PaymentDate_raw"] = payments["PaymentDate"]
    payments["PaymentDate"] = parse_ambiguous_date(payments["PaymentDate"])
    return payments


def clean_orders(orders, payments):
    """
    - Exact duplicate rows dropped (20,705 -> 20,500)
    - OrderDate: kept original as OrderDate_raw; ambiguous formats (2,913) -> NaT,
      then 1,737 of those are recovered from the matching payment's
      PaymentDate (same OrderID) - 1,176 remain genuinely unknown
    - DeliveryTimeMinutes: negative values (208) -> NaN, then implausible
      outliers over 120 minutes (145) -> NaN
    - FoodCost: negative values (181) -> made positive (abs), but only
      where FinalAmount exists to cross-check against
    - FinalAmount: missing values (325) -> calculated as
      FoodCost + DeliveryFee + GST - Discount, where all four are known
      AND FoodCost is valid (not one of the still-negative, unresolved
      cases above) - those 3 rows are left missing rather than computed
      from a bad FoodCost
    - Missing CouponCode: retained as-is (not every order uses a coupon)

    Note: CustomerID/RestaurantID orphan-checking happens separately in
    mark_orphan_foreign_keys(), since it needs the customers/restaurants
    tables, not just the orders table.
    """
    orders = orders.drop_duplicates().copy()

    orders["OrderDate_raw"] = orders["OrderDate"]
    orders["OrderDate"] = parse_ambiguous_date(orders["OrderDate"])

    payment_dates = (
        payments.dropna(subset=["PaymentDate"])
        .drop_duplicates("OrderID")
        .set_index("OrderID")["PaymentDate"]
    )
    missing_date = orders["OrderDate"].isna()
    orders.loc[missing_date, "OrderDate"] = orders.loc[missing_date, "OrderID"].map(payment_dates)

    orders["DeliveryTimeMinutes"] = clip_negative(orders["DeliveryTimeMinutes"])
    orders["DeliveryTimeMinutes"] = orders["DeliveryTimeMinutes"].where(orders["DeliveryTimeMinutes"] <= 120)

    negative_food_cost = orders["FoodCost"] < 0
    fixable = negative_food_cost & orders["FinalAmount"].notna()
    orders.loc[fixable, "FoodCost"] = orders.loc[fixable, "FoodCost"].abs()
    # the remaining negative FoodCost rows (no FinalAmount to check against) are left as-is

    missing_final = orders["FinalAmount"].isna()
    valid_food_cost = orders["FoodCost"].isna() | (orders["FoodCost"] >= 0)
    computable = (
        missing_final
        & valid_food_cost
        & orders[["FoodCost", "DeliveryFee", "GST", "Discount"]].notna().all(axis=1)
    )
    orders.loc[computable, "FinalAmount"] = (
        orders.loc[computable, "FoodCost"]
        + orders.loc[computable, "DeliveryFee"]
        + orders.loc[computable, "GST"]
        - orders.loc[computable, "Discount"]
    )

    return orders


def mark_orphan_foreign_keys(orders, customers, restaurants):
    """
    Set CustomerID/RestaurantID to NaN wherever the order references an
    ID that doesn't actually exist in the customers/restaurants tables
    (12 and 13 cases respectively). We keep the order row itself - the
    order still happened - we just can't say who placed it or where.
    """
    orders = orders.copy()
    orders.loc[~orders["CustomerID"].isin(customers["CustomerID"]), "CustomerID"] = np.nan
    orders.loc[~orders["RestaurantID"].isin(restaurants["RestaurantID"]), "RestaurantID"] = np.nan
    return orders


def clean_customer_feedback(feedback):
    """
    - OrderIDs with more than one feedback row that DISAGREE on ratings
      (115 order IDs / 230 rows) -> all rows for that OrderID dropped,
      since there's no timestamp to say which review is correct/latest
    - DeliveryRating: out-of-range values >5 (126) -> NaN
    - Missing CustomerRating/DeliveryRating/Review: retained as-is
    """
    feedback = feedback.copy()

    rating_cols = ["CustomerRating", "DeliveryRating", "FoodRating"]
    duplicated_ids = feedback.loc[feedback.duplicated("OrderID", keep=False), "OrderID"].unique()
    conflicting = (
        feedback[feedback["OrderID"].isin(duplicated_ids)]
        .groupby("OrderID")[rating_cols]
        .nunique()
        .max(axis=1)
    )
    conflicting_ids = conflicting[conflicting > 1].index
    feedback = feedback[~feedback["OrderID"].isin(conflicting_ids)]

    feedback["DeliveryRating"] = clip_range(feedback["DeliveryRating"], 1, 5)

    return feedback


def clean_weather(weather):
    """
    - Rows with missing City (91) -> dropped entirely (a weather reading
      with no city tells us nothing usable)
    - Date: kept original as Date_raw; ambiguous formats (2,582) -> NaT
    - Humidity: negative values (189) -> NaN
    - Missing Rainfall: retained as-is
    """
    weather = weather.dropna(subset=["City"]).copy()
    weather["Date_raw"] = weather["Date"]
    weather["Date"] = parse_ambiguous_date(weather["Date"])
    weather["Humidity"] = clip_negative(weather["Humidity"])
    return weather


def clean_traffic(traffic):
    """
    - Date: kept original as Date_raw; ambiguous formats (2,557) -> NaT
    - AverageSpeed: negative values (186) -> NaN
    - Missing TrafficLevel: retained as-is
    """
    traffic = traffic.copy()
    traffic["Date_raw"] = traffic["Date"]
    traffic["Date"] = parse_ambiguous_date(traffic["Date"])
    traffic["AverageSpeed"] = clip_negative(traffic["AverageSpeed"])
    return traffic


# =================================================================
# Orchestrator - runs everything in the right order
# =================================================================

def clean_all(raw):
    """
    Take the dict of raw DataFrames from `ingest.load_raw()` and return
    a dict of cleaned DataFrames, ready to save and feed into features.py.

    Order matters here: order_items must be cleaned before menu (menu's
    Price fix checks against order_items), and payments must be cleaned
    before orders (orders' OrderDate backfill uses payments' PaymentDate).
    """
    data = {name: df.copy() for name, df in raw.items()}

    strip_whitespace(data)
    standardize_cities(data)

    data["cities"] = clean_cities(data["cities"])
    data["customers"] = clean_customers(data["customers"])
    data["restaurants"] = clean_restaurants(data["restaurants"])
    data["delivery_partners"] = clean_delivery_partners(data["delivery_partners"])
    data["order_items"] = clean_order_items(data["order_items"])
    data["menu"] = clean_menu(data["menu"], data["order_items"])
    data["promotions"] = clean_promotions(data["promotions"])
    data["payments"] = clean_payments(data["payments"])

    orders = clean_orders(data["orders"], data["payments"])
    orders = mark_orphan_foreign_keys(orders, data["customers"], data["restaurants"])
    data["orders"] = orders

    data["customer_feedback"] = clean_customer_feedback(data["customer_feedback"])
    data["weather"] = clean_weather(data["weather"])
    data["traffic"] = clean_traffic(data["traffic"])

    return data


def save_cleaned(cleaned, out_dir):
    """Write every cleaned DataFrame to `out_dir` as <name>.csv."""
    import os
    os.makedirs(out_dir, exist_ok=True)
    for name, df in cleaned.items():
        df.to_csv(f"{out_dir}{name}.csv", index=False)


if __name__ == "__main__":
    # Small self-test with a handful of made-up messy rows, just to prove
    # every function runs without errors. This is NOT a substitute for
    # running clean_all() against your real data/raw/ CSVs.
    sample_orders = pd.DataFrame({
        "OrderID": [1, 2, 2, 3],
        "CustomerID": [101, 999, 999, 102],   # 999 is an orphan ID
        "RestaurantID": [1, 1, 1, 1],
        "DeliveryPartnerID": [1, 1, 1, 1],
        "OrderDate": ["2023-06-17", "17/25/2023", "17/25/2023", "invalid"],
        "OrderTime": ["11:51:00"] * 4,
        "DeliveryTimeMinutes": [30, -5, -5, 400],
        "FoodCost": [200, -150, -150, 100],
        "DeliveryFee": [40, 40, 40, 40],
        "Discount": [0, 0, 0, 0],
        "CouponCode": [None, None, None, None],
        "GST": [10, 10, 10, 10],
        "FinalAmount": [250, np.nan, np.nan, np.nan],
        "OrderStatus": ["Delivered"] * 4,
        "PaymentMethod": ["UPI"] * 4,
    })
    sample_customers = pd.DataFrame({"CustomerID": [101, 102], "City": ["Mumbai"] * 2})
    sample_restaurants = pd.DataFrame({"RestaurantID": [1], "City": ["Mumbai"]})
    sample_payments = pd.DataFrame({"OrderID": [2], "PaymentDate": ["2023-06-20"]})

    cleaned = clean_orders(sample_orders, clean_payments(sample_payments))
    cleaned = mark_orphan_foreign_keys(cleaned, sample_customers, sample_restaurants)
    print(cleaned[["OrderID", "CustomerID", "OrderDate", "DeliveryTimeMinutes", "FoodCost"]])
    print("\nSelf-test ran without errors.")
