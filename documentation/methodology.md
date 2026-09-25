# Methodology

How the project was built, and why each choice was made. For column definitions see `feature_dictionary.md`;
for every cleaning decision see `cleaning_log.md`.

## 1. Pipeline overview

```
data/raw/*.csv ──► src/clean.py ──► data/cleaned/*.csv ──► src/features.py ──► data/analytical/*.csv
                                                                                     │
                                          EDA (03) ◄──────────────────────────────────┤
                                          Delivery model (04) ◄───────────────────────┤
                                          Churn model (05) ◄──────────────────────────┤
                                          Power BI ◄──────────────────────────────────┘
```

The analytical tables are built **once** and reused by EDA, both models and Power BI, so every number in the
project comes from the same source.

## 2. Data

Twelve tables, stored with plain names, one file per table: `cities`, `customers`, `restaurants`,
`delivery_partners`, `menu`, `promotions`, `orders`, `order_items`, `payments`, `customer_feedback`, `weather`,
`traffic` (`data/raw/orders.csv`, `data/cleaned/orders.csv`, and so on). Orders cover 1 Jan 2023 to 31 Dec 2024.
The loaders in `src/ingest.py` build the path as `<folder><name>.csv`, so pass the folder **with a trailing slash**
(for example `"../data/cleaned/"`).

## 3. Cleaning

Rule: fix what is clearly wrong, never guess what is missing. Duplicates were removed, text standardised,
impossible values (negative ages, ratings above 5, negative amounts) fixed or blanked, and ambiguous dates set to
blank rather than guessed. Details and counts: `cleaning_log.md`.

## 4. Analytical layer (`src/features.py`, notebook 02)

| Table | Grain | Rows |
|---|---|---|
| `order_analytics` | 1 order | 20,475 |
| `customer_analytics` | 1 customer | 9,254 |
| `restaurant_analytics` | 1 restaurant | 1,200 |

Key design choices:
- **No row duplication when joining.** `order_items` (many rows per order) and `customer_feedback` are aggregated to one row per order before joining.
- **Weather and traffic** are joined on city and date after averaging same-day duplicate readings. About 46% of orders have no reading; these are left blank, not filled.
- **Distance is not calculated.** Customers have no coordinates, so nothing was fabricated. `SameCity` (customer city equals restaurant city) is a documented proxy, though only about 4% of orders are same-city.
- **`DeliveryTimeTarget`** is `DeliveryTimeMinutes` kept only for Delivered and Delivered Late orders, so cancelled or undelivered orders are never used as training examples.
- **`PerformanceScore`** for restaurants is a weighted blend (0.40 rating, 0.30 revenue, 0.15 order volume, 0.15 one-minus-cancellation-rate, each min-max scaled). The weights are a design choice, not an industry standard.
- 25+ features were engineered; see `feature_dictionary.md`.
- Quality checks (unique IDs, no negative amounts or delivery times, valid churn label) are in `outputs/data_quality_report.csv`; null percentages per column are in `outputs/analytical_null_profile.csv`.

## 5. Revenue definition

**Revenue = `FinalAmount` of orders with status Delivered or Delivered Late** (Rs 5.31M). Cancelled and Food Not
Delivered orders are not revenue. Total order value placed is Rs 8.02M. Note that `RestaurantRevenue`,
`restaurant_analytics.TotalRevenue` and `CustomerLifetimeValue` in the analytical tables sum all orders, so
SQL, Power BI and Pandas must all use the same definition when compared.

## 6. Delivery-time model (`src/model_delivery.py`, notebook 04)

- **Target:** `DeliveryTimeTarget` (minutes).
- **Features (15):** TrafficScore, RainImpact, PeakHour, IsWeekend, BasketSize, DiscountRate, RestaurantRating, PartnerRating, DeliveryEfficiency, AverageSpeed, Temperature, Humidity, OrderHour, DayOfWeek, RestaurantPreparationTime.
- **Leakage control:** anything only known after delivery (`DeliveryTimeMinutes`, `LateDelivery`, `OrderStatus`) is excluded.
- **Preprocessing:** median fill for numeric columns, "Unknown" plus one-hot encoding for categorical columns, bundled with the model in one pipeline.
- **Split:** 80/20, `random_state=42`.
- **Models:** Linear Regression, Decision Tree, Random Forest, Gradient Boosting. Only the top two were tuned (`RandomizedSearchCV`, 6 iterations, 2-fold, scored on MAE), to keep tuning fast.
- **Metrics:** MAE, RMSE, R-squared.
- **Result:** MAE about 11.6 minutes, R-squared about 0. Predicting the average gives about the same error, so the features carry almost no usable signal.

## 7. Churn model (`src/model_churn.py`, notebook 05)

- **Time-aware design:** observation date = latest order date minus 60 days = **2024-11-01**. All features use only orders on or before this date. `Churn60 = 1` if the customer placed no order in the following 60 days. Only customers with history before the observation date are included (9,254 of 12,000).
- **Features (18):** age, order count, lifetime value, average order value, average delivery time and rating, recency, orders in the last 30 and 60 days and the 60 days before that, coupon, cancellation and weekend rates, tenure, gender, city, membership, preferred cuisine.
- **Fixes and exclusions:** negative `CustomerTenure` (about 400 customers registered after their first order) is set to 0; `OrderFrequency` is left out because it is built from that tenure; IDs and raw dates are excluded.
- **Class imbalance:** about 88% of customers churn. Handled with balanced class weights (balanced sample weights for Gradient Boosting) and a stratified 80/20 split.
- **Models:** Logistic Regression, Decision Tree, Random Forest, Gradient Boosting; top two tuned (6 iterations, 3-fold, scored on ROC-AUC).
- **Metrics:** Accuracy, Precision, Recall, F1, ROC-AUC, confusion matrix and ROC curve. ROC-AUC is the main metric, because accuracy and F1 are inflated by the majority class.
- **Baseline:** a rule of "everyone churns" scores 0.878 accuracy and 0.935 F1, higher than every model.
- **Result:** ROC-AUC about 0.50 for every model. Churn is about 88% in every recency and order-count group, so past behaviour in this data does not predict future orders.
- **Outputs:** `churn_predictions.csv` gives every customer a probability and a Low (below 0.33), Medium (0.33 to 0.66) or High (0.66 and above) segment, plus a `Split` column that marks Train or Test rows, since the training rows look better than they should.

## 8. EDA (notebook 03)

Thirty charts: 15 Matplotlib (charts 1 to 15) and 15 Seaborn (16 to 30), all saved to `images/eda/`. Revenue and
delivery-time charts use Delivered and Delivered Late orders only. Time-based charts exclude the 1,173 orders with
no valid date.

## 9. Power BI

Built from the analytical tables and model outputs. The measures, relationships and page layout are in
`powerbi_build_guide.md`, and each measure is validated against Pandas and SQL.

## 10. Reproducibility

- Fixed `random_state=42` for every split and model.
- Run order: `01_data_cleaning` (or `clean_all()`), `02_analytical_dataset`, `03_eda`, `04_delivery_time_model`, `05_churn_model`, each with Kernel then Restart and Run All from inside `notebooks/`.
- Install dependencies with `pip install -r requirements.txt`.

## 11. Limitations

- No customer coordinates, so distance is missing; `SameCity` is only a weak proxy.
- About 46% of orders lack weather and traffic readings (source gap), so these features are median-imputed for the delivery model.
- 1,173 orders have no valid date and 2,746 customers have no history before the observation date.
- Both models perform near chance. This reflects the dataset, not the code.
- Restaurant-level rates rest on about 17 orders per restaurant and are noisy.
- The data is observational: the reports describe patterns, not causes.
