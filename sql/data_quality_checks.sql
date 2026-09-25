SELECT 'cities' AS table_name, COUNT(*) AS row_count FROM cities
UNION ALL
SELECT 'customers', COUNT(*) FROM customers
UNION ALL
SELECT 'restaurants', COUNT(*) FROM restaurants
UNION ALL
SELECT 'delivery_partners', COUNT(*) FROM delivery_partners
UNION ALL
SELECT 'menu', COUNT(*) FROM menu
UNION ALL
SELECT 'promotions', COUNT(*) FROM promotions
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'payments', COUNT(*) FROM payments
UNION ALL
SELECT 'customer_feedback', COUNT(*) FROM customer_feedback
UNION ALL
SELECT 'weather', COUNT(*) FROM weather
UNION ALL
SELECT 'traffic', COUNT(*) FROM traffic;

-- Orders → Customers
SELECT COUNT(*) AS orphan_orders_customers
FROM orders o
LEFT JOIN customers c
    ON o.CustomerID = c.CustomerID
WHERE o.CustomerID IS NOT NULL
  AND c.CustomerID IS NULL;

-- Orders → Restaurants
SELECT COUNT(*) AS orphan_orders_restaurants
FROM orders o
LEFT JOIN restaurants r
    ON o.RestaurantID = r.RestaurantID
WHERE o.RestaurantID IS NOT NULL
  AND r.RestaurantID IS NULL;

-- Orders → Delivery Partners
SELECT COUNT(*) AS orphan_orders_delivery_partners
FROM orders o
LEFT JOIN delivery_partners dp
    ON o.DeliveryPartnerID = dp.DeliveryPartnerID
WHERE dp.DeliveryPartnerID IS NULL;

-- Orders → Promotions
SELECT COUNT(*) AS orphan_orders_promotions
FROM orders o
LEFT JOIN promotions p
    ON o.CouponCode = p.CouponCode
WHERE o.CouponCode IS NOT NULL
  AND p.CouponCode IS NULL;

-- Order Items → Orders
SELECT COUNT(*) AS orphan_order_items_orders
FROM order_items oi
LEFT JOIN orders o
    ON oi.OrderID = o.OrderID
WHERE o.OrderID IS NULL;

-- Order Items → Menu
SELECT COUNT(*) AS orphan_order_items_menu
FROM order_items oi
LEFT JOIN menu m
    ON oi.FoodItemID = m.FoodItemID
WHERE m.FoodItemID IS NULL;

-- Payments → Orders
SELECT COUNT(*) AS orphan_payments_orders
FROM payments p
LEFT JOIN orders o
    ON p.OrderID = o.OrderID
WHERE o.OrderID IS NULL;

-- Feedback → Orders
SELECT COUNT(*) AS orphan_feedback_orders
FROM customer_feedback cf
LEFT JOIN orders o
    ON cf.OrderID = o.OrderID
WHERE o.OrderID IS NULL;

-- Customers → Cities
SELECT COUNT(*) AS orphan_customers_cities
FROM customers c
LEFT JOIN cities ci
    ON c.City = ci.City
WHERE ci.City IS NULL;

-- Restaurants → Cities
SELECT COUNT(*) AS orphan_restaurants_cities
FROM restaurants r
LEFT JOIN cities ci
    ON r.City = ci.City
WHERE ci.City IS NULL;

-- Delivery Partners → Cities
SELECT COUNT(*) AS orphan_delivery_partners_cities
FROM delivery_partners dp
LEFT JOIN cities ci
    ON dp.City = ci.City
WHERE ci.City IS NULL;

-- Weather → Cities
SELECT COUNT(*) AS orphan_weather_cities
FROM weather w
LEFT JOIN cities ci
    ON w.City = ci.City
WHERE ci.City IS NULL;

-- Traffic → Cities
SELECT COUNT(*) AS orphan_traffic_cities
FROM traffic t
LEFT JOIN cities ci
    ON t.City = ci.City
WHERE ci.City IS NULL;

-- 1. Invalid customer ages
SELECT COUNT(*) AS invalid_customer_ages
FROM customers
WHERE Age IS NOT NULL
  AND (Age < 0 OR Age > 100);


-- 2. Invalid restaurant ratings
SELECT COUNT(*) AS invalid_restaurant_ratings
FROM restaurants
WHERE Rating IS NOT NULL
  AND (Rating < 1 OR Rating > 5);


-- 3. Invalid restaurant costs
SELECT COUNT(*) AS invalid_restaurant_costs
FROM restaurants
WHERE AverageCost IS NOT NULL
  AND AverageCost < 0;


-- 4. Invalid delivery partner ratings
SELECT COUNT(*) AS invalid_delivery_ratings
FROM delivery_partners
WHERE Rating IS NOT NULL
  AND (Rating < 1 OR Rating > 5);


-- 5. Invalid delivery times
SELECT COUNT(*) AS invalid_delivery_times
FROM delivery_partners
WHERE AverageDeliveryTime IS NOT NULL
  AND AverageDeliveryTime < 0;


-- 6. Invalid menu prices
SELECT COUNT(*) AS invalid_menu_prices
FROM menu
WHERE Price IS NOT NULL
  AND Price < 0;


-- 7. Invalid order delivery times
SELECT COUNT(*) AS invalid_order_delivery_times
FROM orders
WHERE DeliveryTimeMinutes IS NOT NULL
  AND DeliveryTimeMinutes < 0;


-- 8. Invalid food costs
SELECT COUNT(*) AS invalid_food_costs
FROM orders
WHERE FoodCost IS NOT NULL
  AND FoodCost < 0;


-- 9. Invalid final amounts
SELECT COUNT(*) AS invalid_final_amounts
FROM orders
WHERE FinalAmount IS NOT NULL
  AND FinalAmount < 0;


-- 10. Invalid order-item quantities
SELECT COUNT(*) AS invalid_quantities
FROM order_items
WHERE Quantity <= 0;


-- 11. Invalid order-item prices
SELECT COUNT(*) AS invalid_unit_prices
FROM order_items
WHERE UnitPrice < 0;


-- 12. Invalid order-item totals
SELECT COUNT(*) AS invalid_total_prices
FROM order_items
WHERE TotalPrice < 0;


-- 13. Invalid feedback ratings
SELECT COUNT(*) AS invalid_feedback_ratings
FROM customer_feedback
WHERE (CustomerRating IS NOT NULL AND (CustomerRating < 1 OR CustomerRating > 5))
   OR (DeliveryRating IS NOT NULL AND (DeliveryRating < 1 OR DeliveryRating > 5))
   OR (FoodRating IS NOT NULL AND (FoodRating < 1 OR FoodRating > 5));


-- 14. Invalid promotion discounts
SELECT COUNT(*) AS invalid_discounts
FROM promotions
WHERE DiscountPercentage IS NOT NULL
  AND (DiscountPercentage < 0 OR DiscountPercentage > 100);


-- 15. Invalid rainfall
SELECT COUNT(*) AS invalid_rainfall
FROM weather
WHERE Rainfall IS NOT NULL
  AND Rainfall < 0;


-- 16. Invalid humidity
SELECT COUNT(*) AS invalid_humidity
FROM weather
WHERE Humidity IS NOT NULL
  AND (Humidity < 0 OR Humidity > 100);


-- 17. Invalid traffic speed
SELECT COUNT(*) AS invalid_traffic_speed
FROM traffic
WHERE AverageSpeed IS NOT NULL
  AND AverageSpeed < 0;
  
SELECT
    COUNT(*) AS mismatched_final_amounts
FROM orders
WHERE FoodCost IS NOT NULL
  AND FinalAmount IS NOT NULL
  AND ABS(
        FinalAmount -
        (FoodCost + DeliveryFee + GST - Discount)
      ) > 0.01;
      
SELECT
    COUNT(*) AS total_orders,
    SUM(FoodCost IS NULL) AS missing_food_cost,
    SUM(FinalAmount IS NULL) AS missing_final_amount
FROM orders;


USE zomato_bi;

-- Duplicate primary keys
SELECT 'customers' AS table_name, COUNT(*) - COUNT(DISTINCT CustomerID) AS duplicates
FROM customers
UNION ALL
SELECT 'restaurants', COUNT(*) - COUNT(DISTINCT RestaurantID)
FROM restaurants
UNION ALL
SELECT 'delivery_partners', COUNT(*) - COUNT(DISTINCT DeliveryPartnerID)
FROM delivery_partners
UNION ALL
SELECT 'menu', COUNT(*) - COUNT(DISTINCT FoodItemID)
FROM menu
UNION ALL
SELECT 'promotions', COUNT(*) - COUNT(DISTINCT PromotionID)
FROM promotions
UNION ALL
SELECT 'orders', COUNT(*) - COUNT(DISTINCT OrderID)
FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) - COUNT(DISTINCT OrderItemID)
FROM order_items
UNION ALL
SELECT 'payments', COUNT(*) - COUNT(DISTINCT PaymentID)
FROM payments
UNION ALL
SELECT 'customer_feedback', COUNT(*) - COUNT(DISTINCT FeedbackID)
FROM customer_feedback
UNION ALL
SELECT 'weather', COUNT(*) - COUNT(DISTINCT WeatherID)
FROM weather
UNION ALL
SELECT 'traffic', COUNT(*) - COUNT(DISTINCT TrafficID)
FROM traffic;


-- 1. Duplicate customer emails
SELECT
    COUNT(*) AS duplicate_email_rows,
    COUNT(DISTINCT Email) AS duplicate_email_values
FROM customers
WHERE Email IS NOT NULL
  AND Email IN (
      SELECT Email
      FROM customers
      WHERE Email IS NOT NULL
      GROUP BY Email
      HAVING COUNT(*) > 1
  );


-- 2. Orders with multiple payment records
SELECT
    COUNT(*) AS orders_with_multiple_payments
FROM (
    SELECT OrderID
    FROM payments
    GROUP BY OrderID
    HAVING COUNT(*) > 1
) x;


-- 3. Duplicate FoodName values in menu
SELECT
    COUNT(*) AS duplicate_food_name_groups
FROM (
    SELECT FoodName
    FROM menu
    GROUP BY FoodName
    HAVING COUNT(*) > 1
) x;


-- 4. Multiple items belonging to the same order
SELECT
    COUNT(*) AS orders_with_multiple_items
FROM (
    SELECT OrderID
    FROM order_items
    GROUP BY OrderID
    HAVING COUNT(*) > 1
) x;