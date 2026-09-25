-- =====================================================================
-- ZOMATO BUSINESS INTELLIGENCE & DELIVERY TIME PREDICTION PLATFORM
-- MySQL 9+ - CLEANED DATA SCHEMA + BUSINESS QUERY BANK
--
-- Designed for the supplied cleaned-data profile.
--
-- Important data-profile decisions:
--   * Nullable business fields remain nullable.
--   * CustomerID / RestaurantID in orders remain nullable because the
--     cleaned profile still contains missing values.
--   * CouponCode is nullable because most orders do not use a coupon.
--   * Payments.OrderID is NOT UNIQUE because multiple payment rows can
--     exist for an order in the supplied profile.
--   * TransactionID is NOT UNIQUE because duplicates remain in the profile.
--   * Feedback.OrderID is unique in the supplied profile, but no UNIQUE
--     constraint is imposed so the schema remains flexible.
--   * City is used as the geographic key because that is what the data
--     profile provides across the operational tables.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS zomato_bi;
USE zomato_bi;

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS customer_feedback;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS menu;
DROP TABLE IF EXISTS promotions;
DROP TABLE IF EXISTS delivery_partners;
DROP TABLE IF EXISTS restaurants;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS traffic;
DROP TABLE IF EXISTS weather;
DROP TABLE IF EXISTS cities;

SET FOREIGN_KEY_CHECKS = 1;


-- =====================================================================
-- 1. CITIES
-- =====================================================================

CREATE TABLE cities (
    CityID          INT PRIMARY KEY,
    City            VARCHAR(100) NOT NULL UNIQUE,
    Population      BIGINT,
    Region          VARCHAR(50),
    AverageIncome   DECIMAL(12,2),

    CHECK (Population IS NULL OR Population > 0),
    CHECK (AverageIncome IS NULL OR AverageIncome >= 0)
);


-- =====================================================================
-- 2. CUSTOMERS
-- =====================================================================

CREATE TABLE customers (
    CustomerID          INT PRIMARY KEY,
    Name                VARCHAR(150),
    Age                 SMALLINT,
    Gender              VARCHAR(20),
    Phone               VARCHAR(30),
    Email               VARCHAR(150),
    City                VARCHAR(100) NOT NULL,
    State               VARCHAR(100),
    Pincode             VARCHAR(20),
    RegistrationDate    DATE,
    Membership          VARCHAR(30),
    TotalOrders         INT DEFAULT 0,
    PreferredCuisine    VARCHAR(50),
    Phone_raw           VARCHAR(100),
    Pincode_raw         VARCHAR(100),

    CHECK (Age IS NULL OR Age BETWEEN 0 AND 100),
    CHECK (TotalOrders IS NULL OR TotalOrders >= 0),

    CONSTRAINT fk_customers_city
        FOREIGN KEY (City) REFERENCES cities(City)
);


-- =====================================================================
-- 3. RESTAURANTS
-- =====================================================================

CREATE TABLE restaurants (
    RestaurantID    INT PRIMARY KEY,
    RestaurantName  VARCHAR(150) NOT NULL,
    Cuisine         VARCHAR(50),
    City            VARCHAR(100) NOT NULL,
    Area            VARCHAR(100),
    OpeningTime     TIME,
    ClosingTime     TIME,
    Rating          DECIMAL(2,1),
    AverageCost     DECIMAL(10,2),
    OwnerName       VARCHAR(150),
    RestaurantType  VARCHAR(50),
    Latitude        DECIMAL(9,6),
    Longitude       DECIMAL(9,6),

    CHECK (Rating IS NULL OR Rating BETWEEN 1.0 AND 5.0),
    CHECK (AverageCost IS NULL OR AverageCost >= 0),

    CONSTRAINT fk_restaurants_city
        FOREIGN KEY (City) REFERENCES cities(City)
);


-- =====================================================================
-- 4. MENU
-- =====================================================================

CREATE TABLE menu (
    FoodItemID      INT PRIMARY KEY,
    RestaurantID    INT,
    FoodName        VARCHAR(150) NOT NULL,
    Category        VARCHAR(50),
    Price           DECIMAL(10,2),
    PreparationTime SMALLINT,
    Calories        DECIMAL(8,2),
    Availability    VARCHAR(20),

    CHECK (Price IS NULL OR Price >= 0),
    CHECK (PreparationTime IS NULL OR PreparationTime >= 0),
    CHECK (Calories IS NULL OR Calories >= 0),

    CONSTRAINT fk_menu_restaurant
        FOREIGN KEY (RestaurantID) REFERENCES restaurants(RestaurantID)
);


-- =====================================================================
-- 5. DELIVERY PARTNERS
-- =====================================================================

CREATE TABLE delivery_partners (
    DeliveryPartnerID   INT PRIMARY KEY,
    Name                VARCHAR(150),
    Age                 SMALLINT,
    Gender              VARCHAR(20),
    VehicleType         VARCHAR(30),
    JoiningDate         DATE,
    City                VARCHAR(100) NOT NULL,
    Rating              DECIMAL(2,1),
    CompletedDeliveries INT DEFAULT 0,
    AverageDeliveryTime DECIMAL(6,2),

    CHECK (Age IS NULL OR Age BETWEEN 16 AND 70),
    CHECK (Rating IS NULL OR Rating BETWEEN 1.0 AND 5.0),
    CHECK (CompletedDeliveries IS NULL OR CompletedDeliveries >= 0),
    CHECK (AverageDeliveryTime IS NULL OR AverageDeliveryTime >= 0),

    CONSTRAINT fk_dp_city
        FOREIGN KEY (City) REFERENCES cities(City)
);


-- =====================================================================
-- 6. PROMOTIONS
-- =====================================================================

CREATE TABLE promotions (
    PromotionID         INT PRIMARY KEY,
    CouponCode          VARCHAR(50) NOT NULL UNIQUE,
    DiscountPercentage  SMALLINT,
    CampaignName        VARCHAR(150),
    StartDate           DATE,
    EndDate             DATE,

    CHECK (
        DiscountPercentage IS NULL
        OR DiscountPercentage BETWEEN 0 AND 100
    ),
    CHECK (
        StartDate IS NULL
        OR EndDate IS NULL
        OR EndDate >= StartDate
    )
);


-- =====================================================================
-- 7. ORDERS
-- =====================================================================

CREATE TABLE orders (
    OrderID             INT PRIMARY KEY,
    CustomerID          INT NULL,
    RestaurantID        INT NULL,
    DeliveryPartnerID   INT,
    OrderDate           DATE,
    OrderTime           TIME,
    DeliveryTimeMinutes DECIMAL(8,2),
    FoodCost            DECIMAL(10,2),
    DeliveryFee         DECIMAL(8,2),
    Discount            DECIMAL(10,2) DEFAULT 0,
    CouponCode          VARCHAR(50),
    GST                 DECIMAL(8,2) DEFAULT 0,
    FinalAmount         DECIMAL(10,2),
    OrderStatus         VARCHAR(30),
    PaymentMethod       VARCHAR(30),

    CHECK (DeliveryTimeMinutes IS NULL OR DeliveryTimeMinutes >= 0),
    CHECK (FoodCost IS NULL OR FoodCost >= 0),
    CHECK (DeliveryFee IS NULL OR DeliveryFee >= 0),
    CHECK (Discount IS NULL OR Discount >= 0),
    CHECK (GST IS NULL OR GST >= 0),
    CHECK (FinalAmount IS NULL OR FinalAmount >= 0),

    CONSTRAINT fk_orders_customer
        FOREIGN KEY (CustomerID) REFERENCES customers(CustomerID),

    CONSTRAINT fk_orders_restaurant
        FOREIGN KEY (RestaurantID) REFERENCES restaurants(RestaurantID),

    CONSTRAINT fk_orders_dp
        FOREIGN KEY (DeliveryPartnerID)
        REFERENCES delivery_partners(DeliveryPartnerID),

    CONSTRAINT fk_orders_coupon
        FOREIGN KEY (CouponCode)
        REFERENCES promotions(CouponCode)
);


-- =====================================================================
-- 8. ORDER ITEMS
-- =====================================================================

CREATE TABLE order_items (
    OrderItemID     INT PRIMARY KEY,
    OrderID         INT NOT NULL,
    FoodItemID      INT NOT NULL,
    Quantity        INT,
    UnitPrice       DECIMAL(10,2),
    TotalPrice      DECIMAL(10,2),

    CHECK (Quantity IS NULL OR Quantity > 0),
    CHECK (UnitPrice IS NULL OR UnitPrice >= 0),
    CHECK (TotalPrice IS NULL OR TotalPrice >= 0),

    CONSTRAINT fk_oi_order
        FOREIGN KEY (OrderID) REFERENCES orders(OrderID),

    CONSTRAINT fk_oi_food
        FOREIGN KEY (FoodItemID) REFERENCES menu(FoodItemID)
);


-- =====================================================================
-- 9. PAYMENTS
-- =====================================================================

CREATE TABLE payments (
    PaymentID       INT PRIMARY KEY,
    OrderID         INT NOT NULL,
    PaymentMethod   VARCHAR(30),
    PaymentStatus   VARCHAR(30),
    TransactionID   VARCHAR(100),
    PaymentDate     DATE,

    CONSTRAINT fk_payments_order
        FOREIGN KEY (OrderID) REFERENCES orders(OrderID)
);


-- =====================================================================
-- 10. CUSTOMER FEEDBACK
-- =====================================================================

CREATE TABLE customer_feedback (
    FeedbackID      INT PRIMARY KEY,
    OrderID         INT NOT NULL,
    CustomerRating  DECIMAL(3,1),
    DeliveryRating  DECIMAL(3,1),
    FoodRating      DECIMAL(3,1),
    Review          TEXT,
    Sentiment       VARCHAR(30),

    CHECK (CustomerRating IS NULL OR CustomerRating BETWEEN 1 AND 5),
    CHECK (DeliveryRating IS NULL OR DeliveryRating BETWEEN 1 AND 5),
    CHECK (FoodRating IS NULL OR FoodRating BETWEEN 1 AND 5),

    CONSTRAINT fk_feedback_order
        FOREIGN KEY (OrderID) REFERENCES orders(OrderID)
);


-- =====================================================================
-- 11. WEATHER
-- =====================================================================

CREATE TABLE weather (
    WeatherID        INT PRIMARY KEY,
    City             VARCHAR(100) NOT NULL,
    Date             DATE NOT NULL,
    Temperature      DECIMAL(6,2),
    Rainfall         DECIMAL(8,2),
    Humidity         DECIMAL(5,2),
    WeatherCondition VARCHAR(30),

    CHECK (Humidity IS NULL OR Humidity BETWEEN 0 AND 100),

    CONSTRAINT fk_weather_city
        FOREIGN KEY (City) REFERENCES cities(City)
);


-- =====================================================================
-- 12. TRAFFIC
-- =====================================================================

CREATE TABLE traffic (
    TrafficID     INT PRIMARY KEY,
    City          VARCHAR(100) NOT NULL,
    Date          DATE NOT NULL,
    Time          TIME NOT NULL,
    TrafficLevel  VARCHAR(30),
    AverageSpeed  DECIMAL(7,2),

    CHECK (AverageSpeed IS NULL OR AverageSpeed >= 0),

    CONSTRAINT fk_traffic_city
        FOREIGN KEY (City) REFERENCES cities(City)
);


-- =====================================================================
-- INDEXES
-- =====================================================================

CREATE INDEX idx_orders_customer_date
    ON orders(CustomerID, OrderDate);

CREATE INDEX idx_orders_restaurant_date
    ON orders(RestaurantID, OrderDate);

CREATE INDEX idx_orders_delivery_partner
    ON orders(DeliveryPartnerID);

CREATE INDEX idx_orders_status
    ON orders(OrderStatus);

CREATE INDEX idx_orders_coupon
    ON orders(CouponCode);

CREATE INDEX idx_order_items_order
    ON order_items(OrderID);

CREATE INDEX idx_order_items_food
    ON order_items(FoodItemID);

CREATE INDEX idx_payments_order
    ON payments(OrderID);

CREATE INDEX idx_feedback_order
    ON customer_feedback(OrderID);

CREATE INDEX idx_weather_city_date
    ON weather(City, Date);

CREATE INDEX idx_traffic_city_date
    ON traffic(City, Date);
    
SHOW TABLES;

SELECT
    TABLE_NAME,
    TABLE_ROWS
FROM information_schema.tables
WHERE table_schema = 'zomato_bi'
ORDER BY TABLE_NAME;

SHOW VARIABLES LIKE 'local_infile';

SET GLOBAL local_infile = 1;

SHOW VARIABLES LIKE 'local_infile';

USE zomato_bi;


-- =========================================================
-- CITIES
-- =========================================================

LOAD DATA LOCAL INFILE 'C:/Main/internmo/Zomato1/Zomato_Business_Intelligence_Project/data/cleaned/cities.csv'
INTO TABLE cities
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS city_count
FROM cities;

SELECT *
FROM cities
LIMIT 25;


-- =========================================================
-- CUSTOMERS
-- =========================================================

LOAD DATA LOCAL INFILE 'C:/Main/internmo/Zomato1/Zomato_Business_Intelligence_Project/data/cleaned/customers.csv'
INTO TABLE customers
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS customer_count
FROM customers;


-- =========================================================
-- RESTAURANTS
-- =========================================================

LOAD DATA LOCAL INFILE 'C:/Main/internmo/Zomato1/Zomato_Business_Intelligence_Project/data/cleaned/restaurants.csv'
INTO TABLE restaurants
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS restaurant_count
FROM restaurants;


-- =========================================================
-- DELIVERY PARTNERS
-- =========================================================

LOAD DATA LOCAL INFILE 'C:/Main/internmo/Zomato1/Zomato_Business_Intelligence_Project/data/cleaned/delivery_partners.csv'
INTO TABLE delivery_partners
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS delivery_partner_count
FROM delivery_partners;


-- =========================================================
-- MENU
-- =========================================================

LOAD DATA LOCAL INFILE 'C:/Main/internmo/Zomato1/Zomato_Business_Intelligence_Project/data/cleaned/menu.csv'
INTO TABLE menu
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS menu_item_count
FROM menu;


-- =========================================================
-- PROMOTIONS
-- =========================================================

LOAD DATA LOCAL INFILE 'C:/Main/internmo/Zomato1/Zomato_Business_Intelligence_Project/data/cleaned/promotions.csv'
INTO TABLE promotions
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS promotion_count
FROM promotions;


-- =========================================================
-- ORDERS
-- =========================================================

LOAD DATA LOCAL INFILE 'C:/Main/internmo/Zomato1/Zomato_Business_Intelligence_Project/data/cleaned/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS order_count
FROM orders;


-- =========================================================
-- ORDER ITEMS
-- =========================================================

LOAD DATA LOCAL INFILE 'C:/Main/internmo/Zomato1/Zomato_Business_Intelligence_Project/data/cleaned/order_items.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS order_item_count
FROM order_items;


-- =========================================================
-- PAYMENTS
-- =========================================================

LOAD DATA LOCAL INFILE 'C:/Main/internmo/Zomato1/Zomato_Business_Intelligence_Project/data/cleaned/payments.csv'
INTO TABLE payments
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS payment_count
FROM payments;


-- =========================================================
-- CUSTOMER FEEDBACK
-- =========================================================

LOAD DATA LOCAL INFILE 'C:/Main/internmo/Zomato1/Zomato_Business_Intelligence_Project/data/cleaned/customer_feedback.csv'
INTO TABLE customer_feedback
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS feedback_count
FROM customer_feedback;


-- =========================================================
-- WEATHER
-- =========================================================

LOAD DATA LOCAL INFILE 'C:/Main/internmo/Zomato1/Zomato_Business_Intelligence_Project/data/cleaned/weather.csv'
INTO TABLE weather
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS weather_count
FROM weather;


-- =========================================================
-- TRAFFIC
-- =========================================================

LOAD DATA LOCAL INFILE 'C:/Main/internmo/Zomato1/Zomato_Business_Intelligence_Project/data/cleaned/traffic.csv'
INTO TABLE traffic
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS traffic_count
FROM traffic;