"""
ingest.py
---------
Loads Zomato CSVs into pandas DataFrames. Two loaders, for two different
stages of the pipeline:

    load_raw(raw_dir)       -> the ORIGINAL, messy CSVs (before any cleaning)
    load_cleaned(clean_dir) -> the CSVs AFTER clean.py has run on them

Usage:
    from ingest import load_raw, load_cleaned

    raw = load_raw("data/raw/")
    cleaned = load_cleaned("data/cleaned/")
"""

import pandas as pd

FILE_NAMES = [
    "cities", "customers", "restaurants", "delivery_partners", "menu",
    "promotions", "orders", "order_items", "payments",
    "customer_feedback", "weather", "traffic",
]

# The already-cleaned CSVs (e.g. the ones exported for MySQL's LOAD DATA
# INFILE) use "\N" to mean missing/NULL. The original raw CSVs don't -
# blanks are already read as NaN by pandas' defaults, so load_raw doesn't
# need this.
CLEANED_NA_VALUES = ["\\N"]

# Columns that are proper dates once clean.py has parsed them. Only used
# by load_cleaned - in the raw files these are still messy text.
CLEANED_DATE_COLUMNS = {
    "orders": ["OrderDate"],
    "customers": ["RegistrationDate"],
    "delivery_partners": ["JoiningDate"],
    "promotions": ["StartDate", "EndDate"],
    "weather": ["Date"],
    "traffic": ["Date"],
    "payments": ["PaymentDate"],
}


def load_raw(raw_dir):
    """
    Read the original, untouched CSVs - exactly as they came out of the
    source system, with all their formatting problems (mixed date
    formats, negative numbers, inconsistent casing, etc.) still in place.
    This is the input clean.py expects.
    """
    return {name: pd.read_csv(f"{raw_dir}{name}.csv", low_memory=False) for name in FILE_NAMES}


def load_cleaned(clean_dir):
    """
    Read the CSVs that clean.py has already produced. Handles the "\\N"
    null marker and parses date columns, so this is the input
    features.py expects.
    """
    data = {}
    for name in FILE_NAMES:
        df = pd.read_csv(f"{clean_dir}{name}.csv", na_values=CLEANED_NA_VALUES, low_memory=False)
        for col in CLEANED_DATE_COLUMNS.get(name, []):
            if col in df.columns:
                df[col] = pd.to_datetime(df[col], errors="coerce")
        data[name] = df
    return data


if __name__ == "__main__":
    # Quick manual test: run "python ingest.py" to sanity-check row counts
    # (points at the cleaned files here, since that's what's on disk in this project)
    data = load_cleaned("/mnt/user-data/uploads/")
    for name, df in data.items():
        print(f"{name:20s} {df.shape}")
