-- =====================================================================
-- BUSINESS QUERY BANK
-- =====================================================================


-- =====================================================================
-- SECTION A: CORE QUERYING
-- SELECT, WHERE, GROUP BY, ORDER BY, HAVING
-- =====================================================================

-- A1. Restaurant revenue and order volume.
-- Uses only delivered orders with a known restaurant.
SELECT
    r.RestaurantID,
    r.RestaurantName,
    r.City,
    COUNT(o.OrderID) AS delivered_orders,
    ROUND(SUM(o.FinalAmount), 2) AS total_revenue,
    ROUND(AVG(o.FinalAmount), 2) AS avg_order_value
FROM restaurants r
JOIN orders o
    ON o.RestaurantID = r.RestaurantID
WHERE o.OrderStatus = 'Delivered'
  AND o.FinalAmount IS NOT NULL
GROUP BY
    r.RestaurantID,
    r.RestaurantName,
    r.City
ORDER BY total_revenue DESC
LIMIT 10;


-- A2. Average delivery time by city.
SELECT
    r.City,
    COUNT(o.OrderID) AS orders_with_delivery_time,
    ROUND(AVG(o.DeliveryTimeMinutes), 2) AS avg_delivery_time,
    MIN(o.DeliveryTimeMinutes) AS fastest_delivery,
    MAX(o.DeliveryTimeMinutes) AS slowest_delivery
FROM orders o
JOIN restaurants r
    ON r.RestaurantID = o.RestaurantID
WHERE o.DeliveryTimeMinutes IS NOT NULL
GROUP BY r.City
ORDER BY avg_delivery_time DESC;


-- A3. Cuisine performance based on actual delivered-order volume.
SELECT
    r.Cuisine,
    COUNT(o.OrderID) AS delivered_orders,
    ROUND(SUM(o.FinalAmount), 2) AS revenue,
    ROUND(AVG(r.Rating), 2) AS avg_restaurant_rating
FROM orders o
JOIN restaurants r
    ON r.RestaurantID = o.RestaurantID
WHERE o.OrderStatus = 'Delivered'
GROUP BY r.Cuisine
HAVING COUNT(o.OrderID) >= 100
ORDER BY delivered_orders DESC;


-- A4. Cancellation rate by cuisine.
SELECT
    r.Cuisine,
    COUNT(o.OrderID) AS total_orders,
    SUM(CASE WHEN o.OrderStatus = 'Cancelled' THEN 1 ELSE 0 END)
        AS cancelled_orders,
    ROUND(
        100.0 *
        SUM(CASE WHEN o.OrderStatus = 'Cancelled' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(o.OrderID), 0),
        2
    ) AS cancellation_rate_pct
FROM orders o
JOIN restaurants r
    ON r.RestaurantID = o.RestaurantID
GROUP BY r.Cuisine
ORDER BY cancellation_rate_pct DESC;


-- A5. Orders by order status.
SELECT
    OrderStatus,
    COUNT(*) AS order_count,
    ROUND(
        100.0 * COUNT(*) / (SELECT COUNT(*) FROM orders),
        2
    ) AS percentage_of_orders
FROM orders
GROUP BY OrderStatus
ORDER BY order_count DESC;


-- =====================================================================
-- SECTION B: JOINS
-- =====================================================================

-- B1. INNER JOIN: orders with customer and restaurant details.
SELECT
    o.OrderID,
    c.CustomerID,
    c.Name AS customer_name,
    r.RestaurantID,
    r.RestaurantName,
    o.OrderDate,
    o.FinalAmount,
    o.OrderStatus
FROM orders o
JOIN customers c
    ON c.CustomerID = o.CustomerID
JOIN restaurants r
    ON r.RestaurantID = o.RestaurantID
LIMIT 100;


-- B2. LEFT JOIN: all restaurants, including restaurants with no orders.
SELECT
    r.RestaurantID,
    r.RestaurantName,
    r.City,
    COUNT(o.OrderID) AS order_count,
    ROUND(AVG(o.FinalAmount), 2) AS avg_order_value
FROM restaurants r
LEFT JOIN orders o
    ON o.RestaurantID = r.RestaurantID
GROUP BY
    r.RestaurantID,
    r.RestaurantName,
    r.City
ORDER BY order_count ASC;


-- B3. RIGHT JOIN: every payment, even if an order record is missing.
SELECT
    p.PaymentID,
    p.OrderID,
    p.PaymentStatus,
    p.PaymentDate,
    o.OrderStatus,
    o.FinalAmount
FROM orders o
RIGHT JOIN payments p
    ON p.OrderID = o.OrderID
ORDER BY p.PaymentID
LIMIT 100;


-- B4. SELF JOIN: delivery partners in the same city with materially
-- different average delivery times.
SELECT
    dp1.DeliveryPartnerID AS partner_a,
    dp2.DeliveryPartnerID AS partner_b,
    dp1.City,
    dp1.AverageDeliveryTime AS partner_a_avg_time,
    dp2.AverageDeliveryTime AS partner_b_avg_time,
    ROUND(
        ABS(dp1.AverageDeliveryTime - dp2.AverageDeliveryTime),
        2
    ) AS time_difference
FROM delivery_partners dp1
JOIN delivery_partners dp2
    ON dp1.City = dp2.City
   AND dp1.DeliveryPartnerID < dp2.DeliveryPartnerID
WHERE dp1.AverageDeliveryTime IS NOT NULL
  AND dp2.AverageDeliveryTime IS NOT NULL
  AND ABS(
      dp1.AverageDeliveryTime - dp2.AverageDeliveryTime
  ) > 20
LIMIT 100;


-- B5. UNION: restaurants and delivery partners below a rating threshold.
SELECT
    RestaurantID AS entity_id,
    RestaurantName AS entity_name,
    'Restaurant' AS entity_type,
    Rating
FROM restaurants
WHERE Rating < 3.0

UNION

SELECT
    DeliveryPartnerID AS entity_id,
    Name AS entity_name,
    'Delivery Partner' AS entity_type,
    Rating
FROM delivery_partners
WHERE Rating < 3.0

ORDER BY Rating ASC;


-- =====================================================================
-- SECTION C: CASE EXPRESSIONS
-- =====================================================================

-- C1. Delivery-time buckets.
SELECT
    OrderID,
    DeliveryTimeMinutes,
    CASE
        WHEN DeliveryTimeMinutes IS NULL THEN 'Unknown'
        WHEN DeliveryTimeMinutes <= 20 THEN '0-20 min'
        WHEN DeliveryTimeMinutes <= 40 THEN '21-40 min'
        WHEN DeliveryTimeMinutes <= 60 THEN '41-60 min'
        WHEN DeliveryTimeMinutes <= 90 THEN '61-90 min'
        ELSE '90+ min'
    END AS delivery_time_bucket
FROM orders;


-- C2. Customer lifetime-value segments.
-- Only customers with known order/customer relationships are included.
SELECT
    c.CustomerID,
    c.Name,
    ROUND(SUM(o.FinalAmount), 2) AS lifetime_spend,
    CASE
        WHEN SUM(o.FinalAmount) >= 20000 THEN 'High Value'
        WHEN SUM(o.FinalAmount) >= 10000 THEN 'Medium Value'
        WHEN SUM(o.FinalAmount) >= 3000 THEN 'Low Value'
        ELSE 'Very Low Value'
    END AS value_segment
FROM customers c
JOIN orders o
    ON o.CustomerID = c.CustomerID
WHERE o.FinalAmount IS NOT NULL
GROUP BY c.CustomerID, c.Name
ORDER BY lifetime_spend DESC;


-- C3. Classify restaurants by rating.
SELECT
    RestaurantID,
    RestaurantName,
    Rating,
    CASE
        WHEN Rating IS NULL THEN 'Unrated'
        WHEN Rating >= 4.5 THEN '4.5-5.0'
        WHEN Rating >= 4.0 THEN '4.0-4.4'
        WHEN Rating >= 3.0 THEN '3.0-3.9'
        ELSE 'Below 3.0'
    END AS rating_band
FROM restaurants
ORDER BY Rating DESC;


-- C4. Identify orders with unusually high discounts.
SELECT
    OrderID,
    FinalAmount,
    Discount,
    CASE
        WHEN Discount IS NULL OR Discount = 0 THEN 'No Discount'
        WHEN Discount <= 100 THEN 'Small Discount'
        WHEN Discount <= 300 THEN 'Medium Discount'
        ELSE 'Large Discount'
    END AS discount_band
FROM orders;


-- =====================================================================
-- SECTION D: SUBQUERIES AND CTEs
-- =====================================================================

-- D1. Restaurants whose average cost is above the platform average.
SELECT
    RestaurantID,
    RestaurantName,
    City,
    AverageCost
FROM restaurants
WHERE AverageCost > (
    SELECT AVG(AverageCost)
    FROM restaurants
    WHERE AverageCost IS NOT NULL
)
ORDER BY AverageCost DESC;


-- D2. Customers whose most recent order was cancelled.
SELECT
    c.CustomerID,
    c.Name,
    latest.OrderDate,
    latest.OrderStatus
FROM customers c
JOIN (
    SELECT
        CustomerID,
        OrderDate,
        OrderTime,
        OrderStatus,
        ROW_NUMBER() OVER (
            PARTITION BY CustomerID
            ORDER BY OrderDate DESC, OrderTime DESC
        ) AS rn
    FROM orders
    WHERE CustomerID IS NOT NULL
) latest
    ON latest.CustomerID = c.CustomerID
   AND latest.rn = 1
WHERE latest.OrderStatus = 'Cancelled';


-- D3. Monthly delivered-order revenue by city.
WITH monthly_revenue AS (
    SELECT
        r.City,
        DATE_FORMAT(o.OrderDate, '%Y-%m-01') AS order_month,
        SUM(o.FinalAmount) AS revenue
    FROM orders o
    JOIN restaurants r
        ON r.RestaurantID = o.RestaurantID
    WHERE o.OrderStatus = 'Delivered'
      AND o.OrderDate IS NOT NULL
      AND o.FinalAmount IS NOT NULL
    GROUP BY
        r.City,
        DATE_FORMAT(o.OrderDate, '%Y-%m-01')
)
SELECT
    City,
    order_month,
    ROUND(revenue, 2) AS revenue,
    ROUND(
        LAG(revenue) OVER (
            PARTITION BY City
            ORDER BY order_month
        ),
        2
    ) AS previous_month_revenue
FROM monthly_revenue
ORDER BY City, order_month;


-- D4. Repeat-customer summary.
WITH order_counts AS (
    SELECT
        CustomerID,
        COUNT(*) AS order_count
    FROM orders
    WHERE CustomerID IS NOT NULL
    GROUP BY CustomerID
),
customer_segments AS (
    SELECT
        CustomerID,
        order_count,
        CASE
            WHEN order_count = 1 THEN 'One-Time'
            ELSE 'Repeat'
        END AS segment
    FROM order_counts
)
SELECT
    segment,
    COUNT(*) AS customer_count,
    ROUND(AVG(order_count), 2) AS avg_orders
FROM customer_segments
GROUP BY segment;


-- D5. Customers whose spend is above the average customer spend.
WITH customer_spend AS (
    SELECT
        CustomerID,
        SUM(FinalAmount) AS total_spend
    FROM orders
    WHERE CustomerID IS NOT NULL
      AND FinalAmount IS NOT NULL
    GROUP BY CustomerID
)
SELECT
    CustomerID,
    ROUND(total_spend, 2) AS total_spend
FROM customer_spend
WHERE total_spend > (
    SELECT AVG(total_spend)
    FROM customer_spend
)
ORDER BY total_spend DESC;


-- =====================================================================
-- SECTION E: WINDOW FUNCTIONS
-- =====================================================================

-- E1. Rank restaurants within each city by delivered revenue.
WITH restaurant_revenue AS (
    SELECT
        r.RestaurantID,
        r.RestaurantName,
        r.City,
        SUM(o.FinalAmount) AS total_revenue
    FROM restaurants r
    JOIN orders o
        ON o.RestaurantID = r.RestaurantID
    WHERE o.OrderStatus = 'Delivered'
      AND o.FinalAmount IS NOT NULL
    GROUP BY
        r.RestaurantID,
        r.RestaurantName,
        r.City
)
SELECT
    RestaurantID,
    RestaurantName,
    City,
    ROUND(total_revenue, 2) AS total_revenue,
    ROW_NUMBER() OVER (
        PARTITION BY City
        ORDER BY total_revenue DESC
    ) AS row_num,
    RANK() OVER (
        PARTITION BY City
        ORDER BY total_revenue DESC
    ) AS rank_num,
    DENSE_RANK() OVER (
        PARTITION BY City
        ORDER BY total_revenue DESC
    ) AS dense_rank_num
FROM restaurant_revenue;


-- E2. Top 3 restaurants in each city by revenue.
WITH restaurant_revenue AS (
    SELECT
        r.RestaurantID,
        r.RestaurantName,
        r.City,
        SUM(o.FinalAmount) AS total_revenue
    FROM restaurants r
    JOIN orders o
        ON o.RestaurantID = r.RestaurantID
    WHERE o.OrderStatus = 'Delivered'
      AND o.FinalAmount IS NOT NULL
    GROUP BY
        r.RestaurantID,
        r.RestaurantName,
        r.City
),
city_ranks AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY City
            ORDER BY total_revenue DESC
        ) AS city_rank
    FROM restaurant_revenue
)
SELECT
    RestaurantID,
    RestaurantName,
    City,
    ROUND(total_revenue, 2) AS total_revenue,
    city_rank
FROM city_ranks
WHERE city_rank <= 3
ORDER BY City, city_rank;


-- E3. Previous and next delivered order value for each customer.
SELECT
    CustomerID,
    OrderID,
    OrderDate,
    FinalAmount,
    LAG(FinalAmount) OVER (
        PARTITION BY CustomerID
        ORDER BY OrderDate, OrderTime, OrderID
    ) AS previous_order_amount,
    LEAD(FinalAmount) OVER (
        PARTITION BY CustomerID
        ORDER BY OrderDate, OrderTime, OrderID
    ) AS next_order_amount,
    FinalAmount -
        LAG(FinalAmount) OVER (
            PARTITION BY CustomerID
            ORDER BY OrderDate, OrderTime, OrderID
        ) AS change_vs_previous
FROM orders
WHERE CustomerID IS NOT NULL
  AND OrderStatus = 'Delivered'
  AND FinalAmount IS NOT NULL;


-- E4. Customer recency.
WITH last_orders AS (
    SELECT
        CustomerID,
        MAX(OrderDate) AS last_order_date
    FROM orders
    WHERE CustomerID IS NOT NULL
      AND OrderDate IS NOT NULL
    GROUP BY CustomerID
)
SELECT
    CustomerID,
    last_order_date,
    DATEDIFF(CURRENT_DATE, last_order_date) AS days_since_last_order,
    RANK() OVER (
        ORDER BY last_order_date DESC
    ) AS recency_rank
FROM last_orders
ORDER BY days_since_last_order DESC;


-- E5. Running revenue by month.
WITH monthly_revenue AS (
    SELECT
        DATE_FORMAT(OrderDate, '%Y-%m-01') AS order_month,
        SUM(FinalAmount) AS monthly_revenue
    FROM orders
    WHERE OrderStatus = 'Delivered'
      AND OrderDate IS NOT NULL
      AND FinalAmount IS NOT NULL
    GROUP BY DATE_FORMAT(OrderDate, '%Y-%m-01')
)
SELECT
    order_month,
    ROUND(monthly_revenue, 2) AS monthly_revenue,
    ROUND(
        SUM(monthly_revenue) OVER (
            ORDER BY order_month
        ),
        2
    ) AS cumulative_revenue
FROM monthly_revenue
ORDER BY order_month;





-- =====================================================================
-- SECTION F: VIEWS
-- =====================================================================

DROP VIEW IF EXISTS vw_order_base;

CREATE VIEW vw_order_base AS
SELECT
    o.OrderID,
    o.CustomerID,
    o.RestaurantID,
    o.DeliveryPartnerID,
    o.OrderDate,
    o.OrderTime,
    o.DeliveryTimeMinutes,
    o.FoodCost,
    o.DeliveryFee,
    o.Discount,
    o.CouponCode,
    o.GST,
    o.FinalAmount,
    o.OrderStatus,
    o.PaymentMethod,

    c.Name AS customer_name,
    c.City AS customer_city,
    c.Membership,

    r.RestaurantName,
    r.City AS restaurant_city,
    r.Cuisine,
    r.Rating AS restaurant_rating,

    dp.Name AS delivery_partner_name,
    dp.VehicleType,
    dp.Rating AS partner_rating
FROM orders o
LEFT JOIN customers c
    ON c.CustomerID = o.CustomerID
LEFT JOIN restaurants r
    ON r.RestaurantID = o.RestaurantID
LEFT JOIN delivery_partners dp
    ON dp.DeliveryPartnerID = o.DeliveryPartnerID;


-- Example:
-- SELECT restaurant_city, AVG(DeliveryTimeMinutes)
-- FROM vw_order_base
-- GROUP BY restaurant_city;


DROP VIEW IF EXISTS vw_restaurant_scorecard;

CREATE VIEW vw_restaurant_scorecard AS
SELECT
    r.RestaurantID,
    r.RestaurantName,
    r.City,
    r.Cuisine,
    r.Rating,

    COUNT(o.OrderID) AS total_orders,

    SUM(
        CASE
            WHEN o.OrderStatus = 'Delivered' THEN 1
            ELSE 0
        END
    ) AS delivered_orders,

    SUM(
        CASE
            WHEN o.OrderStatus = 'Cancelled' THEN 1
            ELSE 0
        END
    ) AS cancelled_orders,

    ROUND(
        100.0 *
        SUM(
            CASE
                WHEN o.OrderStatus = 'Cancelled' THEN 1
                ELSE 0
            END
        ) /
        NULLIF(COUNT(o.OrderID), 0),
        2
    ) AS cancellation_rate_pct,

    ROUND(AVG(o.DeliveryTimeMinutes), 2) AS avg_delivery_time,

    ROUND(SUM(
        CASE
            WHEN o.OrderStatus = 'Delivered'
            THEN o.FinalAmount
            ELSE 0
        END
    ), 2) AS delivered_revenue

FROM restaurants r
LEFT JOIN orders o
    ON o.RestaurantID = r.RestaurantID
GROUP BY
    r.RestaurantID,
    r.RestaurantName,
    r.City,
    r.Cuisine,
    r.Rating;


-- =====================================================================
-- SECTION G: DATE AND TIME ANALYSIS
-- =====================================================================

-- G1. Orders by day of week.
SELECT
    WEEKDAY(OrderDate) AS weekday_number,
    DAYNAME(OrderDate) AS day_of_week,
    COUNT(*) AS order_count,
    ROUND(SUM(FinalAmount), 2) AS revenue
FROM orders
WHERE OrderDate IS NOT NULL
GROUP BY
    WEEKDAY(OrderDate),
    DAYNAME(OrderDate)
ORDER BY weekday_number;


-- G2. Month-level delivered revenue.
SELECT
    YEAR(OrderDate) AS order_year,
    MONTH(OrderDate) AS order_month,
    COUNT(*) AS delivered_orders,
    ROUND(SUM(FinalAmount), 2) AS revenue
FROM orders
WHERE OrderStatus = 'Delivered'
  AND OrderDate IS NOT NULL
  AND FinalAmount IS NOT NULL
GROUP BY YEAR(OrderDate), MONTH(OrderDate)
ORDER BY order_year, order_month;


-- G3. Quarter-level delivered revenue.
SELECT
    YEAR(OrderDate) AS order_year,
    QUARTER(OrderDate) AS order_quarter,
    COUNT(*) AS delivered_orders,
    ROUND(SUM(FinalAmount), 2) AS revenue
FROM orders
WHERE OrderStatus = 'Delivered'
  AND OrderDate IS NOT NULL
  AND FinalAmount IS NOT NULL
GROUP BY
    YEAR(OrderDate),
    QUARTER(OrderDate)
ORDER BY order_year, order_quarter;


-- G4. Customer tenure.
SELECT
    CustomerID,
    RegistrationDate,
    DATEDIFF(CURRENT_DATE, RegistrationDate) AS tenure_days,
    ROUND(
        DATEDIFF(CURRENT_DATE, RegistrationDate) / 365.25,
        2
    ) AS tenure_years
FROM customers
WHERE RegistrationDate IS NOT NULL
ORDER BY tenure_days DESC;


-- G5. Order volume by hour.
SELECT
    HOUR(OrderTime) AS order_hour,
    COUNT(*) AS order_count,
    ROUND(AVG(FinalAmount), 2) AS avg_order_value
FROM orders
WHERE OrderTime IS NOT NULL
GROUP BY HOUR(OrderTime)
ORDER BY order_hour;


-- =====================================================================
-- SECTION H: WEATHER AND TRAFFIC
-- =====================================================================

-- IMPORTANT:
-- traffic contains many rows per city/date. Do NOT join raw traffic
-- directly to orders on City + Date, or each order can be duplicated.
-- The following queries aggregate traffic to city/date first.


-- H1. Delivery time by weather condition.
SELECT
    w.WeatherCondition,
    COUNT(o.OrderID) AS order_count,
    ROUND(AVG(o.DeliveryTimeMinutes), 2) AS avg_delivery_time,
    ROUND(AVG(w.Temperature), 2) AS avg_temperature,
    ROUND(AVG(w.Rainfall), 2) AS avg_rainfall,
    ROUND(AVG(w.Humidity), 2) AS avg_humidity
FROM orders o
JOIN restaurants r
    ON r.RestaurantID = o.RestaurantID
JOIN weather w
    ON w.City = r.City
   AND w.Date = o.OrderDate
WHERE o.DeliveryTimeMinutes IS NOT NULL
GROUP BY w.WeatherCondition
ORDER BY avg_delivery_time DESC;


-- H2. Delivery time by daily traffic level.
WITH daily_traffic AS (
    SELECT
        City,
        Date,
        TrafficLevel,
        AVG(AverageSpeed) AS avg_speed
    FROM traffic
    GROUP BY
        City,
        Date,
        TrafficLevel
)
SELECT
    t.TrafficLevel,
    COUNT(o.OrderID) AS order_count,
    ROUND(AVG(o.DeliveryTimeMinutes), 2) AS avg_delivery_time,
    ROUND(AVG(t.avg_speed), 2) AS avg_traffic_speed
FROM orders o
JOIN restaurants r
    ON r.RestaurantID = o.RestaurantID
JOIN daily_traffic t
    ON t.City = r.City
   AND t.Date = o.OrderDate
WHERE o.DeliveryTimeMinutes IS NOT NULL
GROUP BY t.TrafficLevel
ORDER BY avg_delivery_time DESC;


-- H3. Weather condition by city.
SELECT
    w.City,
    w.WeatherCondition,
    COUNT(*) AS weather_records,
    ROUND(AVG(w.Temperature), 2) AS avg_temperature,
    ROUND(AVG(w.Rainfall), 2) AS avg_rainfall,
    ROUND(AVG(w.Humidity), 2) AS avg_humidity
FROM weather w
GROUP BY
    w.City,
    w.WeatherCondition
ORDER BY w.City, weather_records DESC;


-- H4. Compare delivery time on high-rainfall vs lower-rainfall days.
WITH daily_weather AS (
    SELECT
        City,
        Date,
        AVG(Rainfall) AS avg_rainfall
    FROM weather
    GROUP BY City, Date
)
SELECT
    CASE
        WHEN w.avg_rainfall >= 10 THEN 'Higher Rainfall'
        ELSE 'Lower Rainfall'
    END AS rainfall_group,
    COUNT(o.OrderID) AS order_count,
    ROUND(AVG(o.DeliveryTimeMinutes), 2) AS avg_delivery_time
FROM orders o
JOIN restaurants r
    ON r.RestaurantID = o.RestaurantID
JOIN daily_weather w
    ON w.City = r.City
   AND w.Date = o.OrderDate
WHERE o.DeliveryTimeMinutes IS NOT NULL
GROUP BY
    CASE
        WHEN w.avg_rainfall >= 10 THEN 'Higher Rainfall'
        ELSE 'Lower Rainfall'
    END;


-- =====================================================================
-- SECTION I: PAYMENTS, PROMOTIONS AND FEEDBACK
-- =====================================================================

-- I1. Payment-status distribution.
SELECT
    PaymentStatus,
    COUNT(*) AS payment_count,
    ROUND(
        100.0 * COUNT(*) / (SELECT COUNT(*) FROM payments),
        2
    ) AS percentage
FROM payments
GROUP BY PaymentStatus
ORDER BY payment_count DESC;


-- I2. Payment methods used in orders.
SELECT
    PaymentMethod,
    COUNT(*) AS order_count,
    ROUND(AVG(FinalAmount), 2) AS avg_order_value
FROM orders
WHERE PaymentMethod IS NOT NULL
GROUP BY PaymentMethod
ORDER BY order_count DESC;


-- I3. Promotion/coupon performance.
SELECT
    p.CampaignName,
    p.CouponCode,
    p.DiscountPercentage,
    COUNT(o.OrderID) AS orders_using_coupon,
    ROUND(SUM(o.Discount), 2) AS total_discount,
    ROUND(SUM(o.FinalAmount), 2) AS revenue
FROM promotions p
LEFT JOIN orders o
    ON o.CouponCode = p.CouponCode
GROUP BY
    p.CampaignName,
    p.CouponCode,
    p.DiscountPercentage
ORDER BY orders_using_coupon DESC;


-- I4. Feedback summary by sentiment.
SELECT
    Sentiment,
    COUNT(*) AS feedback_count,
    ROUND(AVG(CustomerRating), 2) AS avg_customer_rating,
    ROUND(AVG(DeliveryRating), 2) AS avg_delivery_rating,
    ROUND(AVG(FoodRating), 2) AS avg_food_rating
FROM customer_feedback
GROUP BY Sentiment
ORDER BY feedback_count DESC;


-- I5. Restaurants with their customer-feedback ratings.
SELECT
    r.RestaurantID,
    r.RestaurantName,
    COUNT(f.FeedbackID) AS feedback_count,
    ROUND(AVG(f.CustomerRating), 2) AS avg_customer_rating,
    ROUND(AVG(f.DeliveryRating), 2) AS avg_delivery_rating,
    ROUND(AVG(f.FoodRating), 2) AS avg_food_rating
FROM restaurants r
LEFT JOIN orders o
    ON o.RestaurantID = r.RestaurantID
LEFT JOIN customer_feedback f
    ON f.OrderID = o.OrderID
GROUP BY
    r.RestaurantID,
    r.RestaurantName
HAVING COUNT(f.FeedbackID) > 0
ORDER BY avg_customer_rating DESC;


-- I6. Feedback coverage: what percentage of orders have feedback?
SELECT
    COUNT(DISTINCT o.OrderID) AS total_orders,
    COUNT(DISTINCT f.OrderID) AS orders_with_feedback,
    ROUND(
        100.0 * COUNT(DISTINCT f.OrderID)
        / NULLIF(COUNT(DISTINCT o.OrderID), 0),
        2
    ) AS feedback_coverage_pct
FROM orders o
LEFT JOIN customer_feedback f
    ON f.OrderID = o.OrderID;


-- =====================================================================
-- SECTION J: ORDER-ITEM ANALYSIS
-- =====================================================================

-- J1. Most frequently ordered food items.
SELECT
    m.FoodItemID,
    m.FoodName,
    m.Category,
    COUNT(oi.OrderItemID) AS line_item_count,
    SUM(oi.Quantity) AS total_quantity,
    ROUND(SUM(oi.TotalPrice), 2) AS item_revenue
FROM order_items oi
JOIN menu m
    ON m.FoodItemID = oi.FoodItemID
GROUP BY
    m.FoodItemID,
    m.FoodName,
    m.Category
ORDER BY total_quantity DESC
LIMIT 20;


-- J2. Restaurant/category sales.
SELECT
    r.RestaurantID,
    r.RestaurantName,
    m.Category,
    SUM(oi.Quantity) AS total_quantity,
    ROUND(SUM(oi.TotalPrice), 2) AS category_revenue
FROM order_items oi
JOIN menu m
    ON m.FoodItemID = oi.FoodItemID
JOIN restaurants r
    ON r.RestaurantID = m.RestaurantID
GROUP BY
    r.RestaurantID,
    r.RestaurantName,
    m.Category
ORDER BY category_revenue DESC;


-- J3. Check whether TotalPrice approximately matches Quantity * UnitPrice.
SELECT
    COUNT(*) AS checked_rows,
    SUM(
        CASE
            WHEN UnitPrice IS NOT NULL
             AND Quantity IS NOT NULL
             AND TotalPrice IS NOT NULL
             AND ABS(TotalPrice - (Quantity * UnitPrice)) > 0.01
            THEN 1
            ELSE 0
        END
    ) AS inconsistent_rows
FROM order_items;


-- =====================================================================
-- SECTION K: DATA-QUALITY / BUSINESS-INTEGRITY QUERIES
-- =====================================================================

-- K1. Orders with missing customer or restaurant relationships.
SELECT
    OrderID,
    CustomerID,
    RestaurantID,
    DeliveryPartnerID,
    OrderDate,
    OrderStatus
FROM orders
WHERE CustomerID IS NULL
   OR RestaurantID IS NULL
ORDER BY OrderID;


-- K2. Payments where the OrderID appears more than once.
SELECT
    OrderID,
    COUNT(*) AS payment_rows
FROM payments
GROUP BY OrderID
HAVING COUNT(*) > 1
ORDER BY payment_rows DESC;


-- K3. Duplicate TransactionIDs.
SELECT
    TransactionID,
    COUNT(*) AS occurrence_count
FROM payments
WHERE TransactionID IS NOT NULL
GROUP BY TransactionID
HAVING COUNT(*) > 1
ORDER BY occurrence_count DESC;


-- K4. Orders whose financial components do not approximately reconcile.
-- Expected amount = FoodCost + DeliveryFee - Discount + GST.
SELECT
    OrderID,
    FoodCost,
    DeliveryFee,
    Discount,
    GST,
    FinalAmount,
    ROUND(
        FoodCost + DeliveryFee - Discount + GST,
        2
    ) AS calculated_amount,
    ROUND(
        FinalAmount -
        (FoodCost + DeliveryFee - Discount + GST),
        2
    ) AS difference
FROM orders
WHERE FoodCost IS NOT NULL
  AND DeliveryFee IS NOT NULL
  AND Discount IS NOT NULL
  AND GST IS NOT NULL
  AND FinalAmount IS NOT NULL
  AND ABS(
      FinalAmount -
      (FoodCost + DeliveryFee - Discount + GST)
  ) > 1;


-- K5. Orders with unusually long delivery times.
SELECT
    OrderID,
    DeliveryTimeMinutes,
    OrderDate,
    OrderStatus
FROM orders
WHERE DeliveryTimeMinutes > 120
ORDER BY DeliveryTimeMinutes DESC;


-- K6. Promotion dates that are incomplete or invalid.
SELECT
    PromotionID,
    CouponCode,
    StartDate,
    EndDate,
    CASE
        WHEN StartDate IS NULL OR EndDate IS NULL
            THEN 'Missing Date'
        WHEN EndDate < StartDate
            THEN 'Invalid Date Range'
        ELSE 'Valid'
    END AS date_status
FROM promotions
WHERE StartDate IS NULL
   OR EndDate IS NULL
   OR EndDate < StartDate;


-- K7. Customers with missing contact information.
SELECT
    CustomerID,
    Name,
    Phone,
    Email
FROM customers
WHERE Phone IS NULL
   AND Email IS NULL;


-- K8. Restaurants with missing operational information.
SELECT
    RestaurantID,
    RestaurantName,
    City,
    Cuisine,
    Rating,
    AverageCost
FROM restaurants
WHERE Cuisine IS NULL
   OR Rating IS NULL
   OR AverageCost IS NULL;


-- =====================================================================
-- END OF MYSQL 9+ QUERY BANK
-- =====================================================================