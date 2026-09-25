# Cleaning Log

Every cleaning decision made on the 12 source tables, in one place. This file is generated from
`cleaning_decisions_Profiling.csv` (the log exported from the original cleaning notebook); the code that applies
the decisions is `src/clean.py`, and the reasoning is explained in plain language in `cleaning_guide.md`.

**Files:** raw tables are in `data/raw/` and cleaned tables in `data/cleaned/`, using the same 12 plain names in both:
`cities`, `customers`, `restaurants`, `delivery_partners`, `menu`, `promotions`, `orders`, `order_items`, `payments`,
`customer_feedback`, `weather`, `traffic` (each as `<name>.csv`).

## Summary

| | Count |
|---|---|
| Log entries | 61 |
| Completed (data was changed) | 39 |
| Profiled only (issue found, value deliberately left as is) | 22 |

## Principles

1. **Fix what is clearly wrong; never guess what is missing.** Negative ages, ratings above 5 and impossible dates are fixed or blanked. Blank emails, cuisines or genders are left blank.
2. **Ambiguous dates are not guessed.** A date like `03/04/2023` (3 April or 4 March?) becomes blank unless the format makes it unambiguous (year first, month as a name, or one part above 12).
3. **Original values are kept.** Where a column's values change, the original stays alongside it in a `_raw` column.
4. **Duplicates:** only exact duplicate rows are dropped, keeping the first. Contradictory duplicates (for example two feedback rows with different ratings and no timestamp) are removed because neither can be trusted.
5. **Recover only from a trusted second source.** Missing order dates are filled from the payment date of the same order; negative food costs are flipped only when `FinalAmount` confirms it.

## Decisions by dataset


### All tables

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| all object columns | white space around object data | Example: "Hyderabad" and " Hyderabad " carry the same value but are considered unique | removed white space around all object columns |  |  |  | Completed |
| City | not standardised as per master cities dataset with casing issues | there are City values not canonically aligned with the City values listed in the cities dataset | standardised the casing to title and mapped the cities with Canonical values | >25 |  | 25 | Completed |

### customers

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| all | exact row duplicates found | count of duplicate customers rows: 180 | dropped duplicate rows | 12,180 | 180 | 12,000 | Completed |
| Email | duplicates | there are 297 rows with duplicated Email entries | retained | 297 | 0 | 297 | Profiled |
| Age | missing | 168 missing values found | retain | 168 | 0 | 168 | Profiled |
| Gender | missing | 120 missing values found | retain | 120 | 0 | 120 | Profiled |
| Phone | missing | 142 missing values found | retain | 142 | 0 | 142 | Profiled |
| Email | missing | 328 missing values found | retain | 328 | 0 | 328 | Profiled |
| State | missing | 180 missing values found | retain | 180 | 0 | 180 | Profiled |
| Membership | missing | 120 missing values found | retain | 120 | 0 | 120 | Profiled |
| PreferredCuisine | missing | 240 missing values found | retain | 240 | 0 | 240 | Profiled |
| Name | inconsistent casing | there are 11749 unique Name entries in the customers dataset without standard casing and 17 unique entries changed to duplicates with title casing | converted all the entries to have title casing | 11,749 | 17 | 11,732 | Completed |
| Age | negative Age entries | there are 258 negative entries in the Age column | converted negative entries to NaN | 258 | 258 | 0 | Completed |
| Phone | invalid Phone entries | there are Phone entries that contain wrong digit count, invalid start numbers, contain letters | converted numbers starting with country code 91 to standard 10 digits, converted invalid entries to NaN and retained original as Raw | 11,858 | 6,129 | 5,729 | Completed |
| Pincode | invalid Pincode entries | there are invalid Pincode entries that have letters and invalid start value | converted the invalid entries to NaT | 11,667 | 276 | 11,391 | Completed |
| City-State | each city is mapped with multiple states | all 25 cities listed are mapped with all 28 unique states listed in the customers dataset | retain | 12,000 | 0 | 12,000 | Profiled |
| RegistrationDate | multiple date formats mixed DD/MM and MM/DD | 1420 date values are ambiguous where we cannot determine if the date format is DD/MM or MM/DD | converted the ambiguous Date formats to NaT | 1,420 | 1,420 | 0 | Completed |

### orders

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| all | exact row duplicates found | count of duplicate orders rows: 205 | dropped duplicate rows | 20,705 | 205 | 20,500 | Completed |
| CouponCode | missing | 13281 missing values found | retain | 13,281 | 0 | 13,281 | Profiled |
| CustomerID | non-existent CustomerID in the customers dataset | there are 12 orphan CustomerID entries in the orders dataset | converted the 12 orphan CustomerID to NA | 12 | 12 | 0 | Completed |
| RestaurantID | non-existent RestaurantID in the restaurants dataset | there are 13 orphan RestaurantID entries in the orders dataset | converted the 13 orphan RestaurantID to NA | 13 | 13 | 0 | Completed |
| OrderDate | multiple date formats mixed DD/MM and MM/DD | 2913 date values are ambiguous where we cannot determine if the date format is DD/MM or MM/DD | converted the ambiguous Date formats to NaT | 2,913 | 2,913 | 0 | Completed |
| DeliveryTimeMinutes | negative DeliveryTimeMinutes entries | there are 208 negative entries in the DeliveryTimeMinutes column | converted the negative entries in the DeliveryTimeMinutes column to NA | 208 | 208 | 0 | Completed |
| DeliveryTimeMinutes | outliers >120 minutes leading to 399 minutes | there are 145 entries with DeliveryTimeMinutes > 120 minutes | converted DeliveryTimeMinutes > 120 to NA | 145 | 145 | 0 | Completed |
| FoodCost | negative FoodCost entries | there are 181 negative records in FoodCost columns | converted the negative records to abs where we have FinalAmount value not as NA | 181 | 178 | 3 | Completed |
| FinalAmount | missing values | there are 325 missing entries in the FinalAmount column | calculated the missing FinalAmount values based on other entries | 325 | 322 | 3 | Completed |
| OrderDate | missing/converted NaT values | there are NaT values in the orders table that can be replaced with the help of payments table | replaced 1737 values in the OrderDate column of the orders dataset | 2,913 | 1,737 | 1,176 | Completed |

### order_items

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| Quantity | negative values | there are 417 negative values in the Quantity column of order_items dataset | converted to the absolute values | 417 | 417 | 0 | Completed |
| TotalPrice | missing TotalPrice values | there are 435 missing values in the TotalPrice column | replaced with the calculation based on TotalPrice = Quantity * UnitPrice | 435 | 435 | 0 | Completed |

### payments

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| all | same information tracked under different PaymentID values | there are 202 duplicate rows of data giving the same information on an order | dropping entire duplicate rows and retaining the 1st occurrence | 202 | 202 | 0 | Completed |
| OrderID | duplicate successful order payments found with different TransactionID values | there are 246 duplicate OrderID with same PaymentStatus 148 genuine duplicate OrderID values | retained all the duplicate OrderID entries | 394 | 0 | 394 | Profiled |
| TransactionID | Null TransactionID values | there are 182 Null values that are the only duplicates | Retained | 182 | 0 | 182 | Profiled |
| PaymentDate | multiple date formats mixed DD/MM and MM/DD | 2557 date values are ambiguous where we cannot determine if the date format is DD/MM or MM/DD | converted the ambiguous Date formats to NaT | 2,557 | 2,557 | 0 | Completed |

### menu

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| FoodName | inconsistent casing found | there are 93 unique values with inconsistent casing in FoodName column | standardised casing to title across the column | 93 | 62 | 31 | Completed |
| Price | negative Price entries | there are 90 rows where the Price is negative | converted the negative Price entries to abs where supported by order_items dataset | 90 | 89 | 1 | Completed |
| Price | unsupported negative entry | the FoodItemID - 6772 have an unsupported negative entry | converted to NaN | 1 | 1 | 0 | Completed |
| Calories | missing Calories entries | there are 132 missing entries | retained | 132 | 0 | 132 | Profiled |

### restaurants

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| Cuisine | missing | 12 missing values found | retain | 12 | 0 | 12 | Profiled |
| Rating | missing | 22 missing values found | retain | 22 | 0 | 22 | Profiled |
| RestaurantName | inconsistent casing across the entries | identified 140 unique values without standard casing and 100 unique values found with standard casing | converted all the entries to have standard title casing | 140 | 40 | 100 | Completed |
| Rating | out-of-range range | there are 18 entries in the Rating column that are over 5 | converted the out-of-range entries to NaN | 18 | 18 | 0 | Completed |
| AverageCost | negative AverageCost | there are 15 AverageCost entries that are negative | converted the negative entries to NaN | 15 | 15 | 0 | Completed |

### delivery_partners

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| JoiningDate | multiple date formats mixed DD/MM and MM/DD | 237 date values are ambiguous where we cannot determine if the date format is DD/MM or MM/DD | converted the ambiguous Date formats to NaT | 237 | 237 | 0 | Completed |
| AverageDeliveryTime | negative AverageDeliveryTime entries | there are 27 negative entries | converted to NaN | 27 | 27 | 0 | Completed |
| Rating | missing | 34 missing values found | retain | 34 | 0 | 34 | Profiled |

### promotions

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| StartDate | multiple date formats mixed DD/MM and MM/DD | 50 date values are ambiguous where we cannot determine if the date format is DD/MM or MM/DD | converted the ambiguous Date formats to NaT | 50 | 50 | 0 | Completed |
| EndDate | multiple date formats mixed DD/MM and MM/DD | 39 date values are ambiguous where we cannot determine if the date format is DD/MM or MM/DD | converted the ambiguous Date formats to NaT | 39 | 39 | 0 | Completed |
| StartDate-EndDate | StartDate and EndDate combination is invalid | there are 4 invalid StartDate and EndDate combinations | converted the invalid date ranges to NaT | 4 | 4 | 0 | Completed |

### customer_feedback

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| OrderID | inconsistent duplicate reviews for the same order | 115 duplicated orderid rows and the reviews for the same order are contradicting | removed the entire rows with duplicated rows | 14,200 | 230 | 13,970 | Completed |
| DeliveryRating | ratings >5 found | DeliveryRating: 126 invalid ratings found | converted the invalid range values to NaN | 126 | 126 | 0 | Completed |
| CustomerRating | missing | 287 missing values found | retain | 287 | 0 | 287 | Profiled |
| DeliveryRating | missing | 126 missing values found | retain | 126 | 0 | 126 | Profiled |
| Review | missing | 1045 missing values found | retain | 1,045 | 0 | 1,045 | Profiled |

### weather

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| City | missing City values | there are 91 rows with missing City values | removed the entire rows with missing City values | 18,264 | 91 | 18,173 | Completed |
| Date | multiple date formats mixed DD/MM and MM/DD | 2582 date values are ambiguous where we cannot determine if the date format is DD/MM or MM/DD | converted the ambiguous Date formats to NaT | 2,582 | 2,582 | 0 | Completed |
| Humidity | negative Humidity values | 189 negative Humidity values | converted the negative values to NaN | 189 | 189 | 0 | Completed |
| Rainfall | missing | 268 missing values found | retain | 268 | 0 | 268 | Profiled |

### traffic

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| Date | multiple date formats mixed DD/MM and MM/DD | 2557 date values are ambiguous where we cannot determine if the date format is DD/MM or MM/DD | converted the ambiguous Date formats to NaT | 2,557 | 2,557 | 0 | Completed |
| TrafficLevel | missing | 147 missing values found | retain | 147 | 0 | 147 | Profiled |
| AverageSpeed | negative AverageSpeed values | 186 negative AverageSpeed values in the traffic dataset | converted the negative AverageSpeed values to NaN | 186 | 186 | 0 | Completed |

### cities

| Column | Issue | Evidence | Action | Before | Changed | After | Status |
|---|---|---|---|---|---|---|---|
| AverageIncome | missing AverageIncome entries | there are 2 entries with missing AverageIncome | retained missing | 2 | 0 | 2 | Profiled |

## After the cleaning step

- **Orphan keys:** 12 orders had a `CustomerID` and 13 had a `RestaurantID` that do not exist in the customers / restaurants tables (set to blank above). When the analytical tables are built, orders left with no valid customer or restaurant (about 25) are dropped, which takes orders from 20,500 to **20,475**.
- **Order dates:** 2,913 order dates were ambiguous; 1,737 were recovered from `payments.PaymentDate` and 1,176 stay blank (1,173 remain after the orphan orders are dropped). These orders are left out of time-based charts.
- **Feedback:** 230 contradictory rows were removed (14,200 to 13,970).

## Known items left as they are (by design)

- Duplicate customer emails (297) and missing emails, phones, ages, genders, memberships, states and preferred cuisines are kept as blank or as found.
- Every customer city is linked to every state in the customers table, so `State` is not reliable and is not used for analysis.
- Payments with a repeated `OrderID` (246 flagged) are kept, because the repeats carry different transaction IDs.

## How to check a number

If a count differs after re-running `clean_all()`, compare it with the **Before** column above for that dataset. A mismatch usually means the raw file differs from the one the log was written against.
