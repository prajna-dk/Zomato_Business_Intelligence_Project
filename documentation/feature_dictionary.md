# Feature Dictionary — Zomato Analytical Layer

Three analytical tables sit between the cleaned CSVs and every downstream EDA/ML/Power BI
step: `order_analytics.csv` (grain: 1 row = 1 order), `customer_analytics.csv` (grain: 1 row = 1 customer),
`restaurant_analytics.csv` (grain: 1 row = 1 restaurant).

## Known limitation — distance
Customers have no latitude/longitude in the source data (only restaurants do). Restaurant-to-customer
distance could not be calculated and was **not fabricated**. `SameCity` (customer city == restaurant city)
is provided as a documented proxy instead.

---

## order_analytics.csv

| Feature | Definition | Source | Type |
|---|---|---|---|
| OrderHour | Hour extracted from OrderTime | orders | numeric |
| DayOfWeek | Day name of OrderDate | orders | categorical |
| IsWeekend | 1 if DayOfWeek is Sat/Sun | orders | binary |
| PeakHour | 1 if OrderHour in 12–14 or 19–21 (lunch/dinner rush) | orders | binary |
| DiscountRate | Discount / (FoodCost+DeliveryFee+GST) | orders | numeric |
| HasCoupon | 1 if CouponCode present | orders | binary |
| CustomerTenure | OrderDate − customer's RegistrationDate, in days | customers/orders | numeric |
| CustomerOrderCount | Total orders by this customer, all-time | orders | numeric |
| CustomerLifetimeValue | Sum of FinalAmount by this customer, all-time | orders | numeric |
| AverageBasketValue | Mean FinalAmount per order, this customer | orders | numeric |
| OrderFrequency | CustomerOrderCount / CustomerTenure | orders | numeric |
| RecencyDays | Days since this customer's *previous* order (gap, not snapshot-recency) | orders | numeric |
| RestaurantOrderCount | Total orders ever placed at this restaurant | orders | numeric |
| RestaurantRevenue | Total FinalAmount ever earned by this restaurant | orders | numeric |
| RestaurantPopularity | Percentile rank (0–100) of RestaurantOrderCount vs all restaurants | orders | numeric |
| DeliveryEfficiency | Partner's AverageDeliveryTime ÷ average AverageDeliveryTime of all partners in partner's city | delivery_partners | numeric (ratio; <1 = faster than city peers) |
| TrafficScore | Ordinal map of TrafficLevel: Low=1, Moderate=2, High=3, Severe=4 | traffic | numeric |
| RainImpact | Rainfall bucketed: None (0mm), Light (≤2.5mm), Moderate (≤7.6mm), Heavy (>7.6mm) | weather | categorical |
| HasRain | 1 if Rainfall > 0 | weather | binary |
| TotalQuantity / BasketSize | Sum of item quantities in the order (from order_items) | order_items | numeric |
| UniqueItems | Distinct food items in the order | order_items | numeric |
| ItemRevenue | Sum of TotalPrice across the order's items | order_items | numeric |
| RestaurantPreparationTime | Mean menu PreparationTime across items ordered | menu | numeric |
| LateDelivery | 1 if OrderStatus == 'Delivered Late' | orders | binary |
| DeliveryTimeTarget | DeliveryTimeMinutes, kept only for Delivered/Delivered Late orders (ML regression target) | orders | numeric |
| SameCity | 1 if CustomerCity == RestaurantCity (distance proxy — see limitation above) | customers/restaurants | binary |
| CustomerRating / DeliveryRating / FoodRating / Sentiment | From customer_feedback, left-joined (null where no feedback exists) | customer_feedback | numeric/categorical |

Weather and traffic are joined on (City, Date) after averaging same-day duplicate readings; both source
files cover ~90% of city-days in the order date range, so ~46% of orders (mostly on days/cities with no
recorded reading) will show null weather/traffic — this is a source-data gap, not a join error.

## customer_analytics.csv — time-aware churn design

To avoid leaking future information into the churn label:
- **Observation date** = (latest order date in the dataset) − 60 days = **2024-11-01**.
- All features (TotalOrders, spend, ratings, recency, rolling windows, etc.) are computed **only from
  orders on/before the observation date**.
- **Churn60** = 1 if the customer placed **no** order in the 60 days *after* the observation date, else 0.
- Only customers with at least one order on/before the observation date are included (9,254 of 12,000
  customers) — there's no historical window to build features for the rest.
- Resulting churn rate is **87.8%**, i.e. heavily imbalanced — most customers order very infrequently
  (~1.7 orders/customer over 2 years). This needs explicit handling (class weighting / resampling) in the
  churn model step — flagged here so it isn't a surprise later.

| Feature | Definition |
|---|---|
| RecencyDays | Days between observation date and customer's last pre-cutoff order |
| OrdersLast30Days / OrdersLast60Days | Orders in the 30/60 days immediately before the cutoff |
| OrdersPrevious60Days | Orders in the 60-day window *before that* (for trend/momentum features) |
| CouponUsageRate | Share of pre-cutoff orders that used a coupon |
| CancellationRate | Share of pre-cutoff orders that were cancelled |
| WeekendOrderRate | Share of pre-cutoff orders placed on Sat/Sun |
| AverageRating | Mean CustomerRating from feedback on pre-cutoff orders only |

## restaurant_analytics.csv

| Feature | Definition |
|---|---|
| CancellationRate | CancelledOrders / TotalOrders |
| LateDeliveryRate | Orders with status 'Delivered Late' / TotalOrders |
| RestaurantPopularity | Percentile rank (0–100) of TotalOrders vs all restaurants |
| RevenueRankCity | Restaurant's revenue rank within its own city (1 = highest) |
| PerformanceScore | 0.40×norm(Rating) + 0.30×norm(TotalRevenue) + 0.15×norm(TotalOrders) + 0.15×(1−CancellationRate), each min-max normalized 0–1 across all restaurants. **These weights are an analytical design choice made for this project, not an industry standard.** |
| PerformanceCategory | PerformanceScore split into quartiles: Poor / Average / Good / Top |
