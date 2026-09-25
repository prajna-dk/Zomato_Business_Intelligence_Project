# Analytical Layer — Reference Guide

Plain-language answers to "how did this work again?" and "why does this look weird?".
For exact column definitions, see `feature_dictionary.md` instead — this doc is about
the *process*, not every column.

---

## 1. How the pieces fit together

```
data/cleaned/*.csv   (your 12 already-cleaned tables)
        │
        ▼
   src/ingest.py      loads every CSV, fixes "\N" -> blank, parses dates
        │
        ▼
   src/clean.py       drops the ~25 orders with no valid customer/restaurant link
        │
        ▼
   src/features.py    all the joins + feature engineering, as small functions
        │
        ▼
notebooks/02_analytical_dataset.ipynb   calls the functions above, shows the
                                          result, checks it, saves the CSVs
        │
        ▼
data/analytical/order_analytics.csv
data/analytical/customer_analytics.csv
data/analytical/restaurant_analytics.csv
```

Why split it this way instead of one long notebook: if a column looks wrong later, you
only have to check one small function in `features.py` — not scroll through a giant
notebook trying to find where a number came from.

---

## 2. "How did you build X?" — quick answers

**Q: Why does `order_analytics.csv` have both `DeliveryTimeMinutes` and `DeliveryTimeTarget`?**
`DeliveryTimeMinutes` is the raw column. `DeliveryTimeTarget` is the same number, but blanked
out for orders that were Cancelled or Food-Not-Delivered — those never had a real delivery
time, so they shouldn't be used as a training example for the delivery-time model. Use
`DeliveryTimeTarget` when you build the ML model; use `DeliveryTimeMinutes` for descriptive
stuff (EDA, Power BI) if you want to see the raw values.

**Q: Why is `SameCity` there instead of an actual distance in km?**
Customers don't have latitude/longitude anywhere in the data — only restaurants do. Rather
than invent fake customer coordinates (which would make every distance number fictional),
we use `SameCity` (1 if customer and restaurant are in the same city) as an honest,
documented substitute.

**Q: Why is the churn rate 88%? That seems really high.**
It's not a bug — most customers in this dataset only order 1-2 times across two full years.
So in any given 60-day window, most customers naturally show "no order". This is realistic
for the data you have, but it does mean the churn model needs class imbalance handling
(class weights or resampling), and you should judge it on F1 / ROC-AUC, not plain accuracy.

**Q: Why does `customer_analytics.csv` have fewer rows (9,254) than the full customer list (12,000)?**
Those 9,254 are customers who had at least one order on or before the "observation date"
(2024-11-01 — see below). The other ~2,750 customers only ordered *after* that date, so
there's no history to compute features from — including them would mean guessing.

**Q: What's the "observation date" and why does it matter?**
It's the cutoff we use to build churn features fairly: everything used to predict churn
(order count, recency, ratings, etc.) is calculated only from data *before* this date, and
the churn label looks at the 60 days *after* it. If we mixed past and future data together,
the model would be cheating — it'd effectively already know the answer.

**Q: Why do ~46% of orders have blank weather/traffic columns?**
The weather.csv and traffic.csv files don't have a reading for every city on every single
day — some days/cities are just missing from the source data. We didn't fill these in with
guesses; they're left blank so you can see exactly what's really known vs. not.

**Q: I changed a raw CSV — do I have to redo everything by hand?**
No. Put the updated file in `data/cleaned/`, then re-run `02_analytical_dataset.ipynb` top
to bottom (Kernel → Restart & Run All). It rebuilds all three analytical CSVs fresh.

---

## 3. If a number looks wrong, check here first

| Symptom | Likely cause | Where to look |
|---|---|---|
| A column is entirely blank | Source file genuinely has no data there, or a join didn't match | `feature_dictionary.md` — check the "Source" column |
| Row counts changed after a re-run | You edited a `data/cleaned/*.csv` file | Compare with `outputs/data_quality_report.csv` |
| Churn rate looks different after a re-run | The dataset's date range changed, so the observation date shifted | Check the printed "Observation date" line in the notebook's Step 4 |
| Two different notebooks give different totals for "revenue" | One is using `FinalAmount` (all orders) vs. filtering to `OrderStatus == 'Delivered'` | Check the filter each notebook applies before summing |
| PerformanceScore ranks look off | It's a weighted blend (rating/revenue/volume/cancellation), not a single metric | See the formula in `feature_dictionary.md` under restaurant_analytics |

---

## 4. Where to look next

- Exact column-by-column definitions → `documentation/feature_dictionary.md`
- Data quality pass/fail results → `outputs/data_quality_report.csv`
- Null-percentage per column → `outputs/analytical_null_profile.csv`
- The actual code → `src/ingest.py`, `src/clean.py`, `src/features.py`
- The walkthrough with output shown → `notebooks/02_analytical_dataset.ipynb`
