"""
features.py
-----------
All the feature-engineering logic used to build the three analytical
tables: order_analytics, customer_analytics, restaurant_analytics.

Each function does ONE small job (aggregate a table, add one group of
columns, etc.) so it's easy to test and easy to change later without
breaking everything else. The three "build_..." functions at the
bottom just call the small functions in order.

Usage:
    from ingest import load_all_raw
    from clean import clean_orders
    from features import build_order_analytics, build_customer_analytics, build_restaurant_analytics

    data = load_all_raw("/mnt/user-data/uploads/")
    orders = clean_orders(data["orders"])

    order_analytics = build_order_analytics(data, orders)
"""

import numpy as np
import pandas as pd

TRAFFIC_SCORE_MAP = {"Low": 1, "Moderate": 2, "High": 3, "Severe": 4}


# ---------------------------------------------------------------
# Small building-block functions
# ---------------------------------------------------------------

def aggregate_order_items(order_items, menu):
    """One row per order: how many items, how much they cost, avg prep time."""
    items = order_items.merge(menu[["FoodItemID", "PreparationTime"]], on="FoodItemID", how="left")

    return items.groupby("OrderID").agg(
        TotalQuantity=("Quantity", "sum"),
        UniqueItems=("FoodItemID", "nunique"),
        ItemRevenue=("TotalPrice", "sum"),
        AverageItemPrice=("UnitPrice", "mean"),
        RestaurantPreparationTime=("PreparationTime", "mean"),
    ).reset_index()


def _mode_or_nan(series):
    """Helper: most common value in a group, or NaN if the group is empty."""
    modes = series.mode()
    return modes.iloc[0] if not modes.empty else np.nan


def aggregate_weather(weather):
    """Collapse weather to one row per City+Date (some days have 2+ readings)."""
    return weather.groupby(["City", "Date"]).agg(
        Temperature=("Temperature", "mean"),
        Rainfall=("Rainfall", "mean"),
        Humidity=("Humidity", "mean"),
        WeatherCondition=("WeatherCondition", _mode_or_nan),
    ).reset_index()


def aggregate_traffic(traffic):
    """Collapse traffic to one row per City+Date."""
    return traffic.groupby(["City", "Date"]).agg(
        AverageSpeed=("AverageSpeed", "mean"),
        TrafficLevel=("TrafficLevel", _mode_or_nan),
    ).reset_index()


def rain_bucket(rainfall_mm):
    """Turn a rainfall number into a simple category."""
    if pd.isna(rainfall_mm):
        return np.nan
    if rainfall_mm <= 0:
        return "None"
    if rainfall_mm <= 2.5:
        return "Light"
    if rainfall_mm <= 7.6:
        return "Moderate"
    return "Heavy"


def add_temporal_features(df, date_col="OrderDate", time_col="OrderTime"):
    """Add OrderHour, DayOfWeek, Month, Quarter, Year, IsWeekend, PeakHour."""
    df["OrderHour"] = pd.to_datetime(df[time_col], format="%H:%M:%S", errors="coerce").dt.hour
    df["DayOfWeek"] = df[date_col].dt.day_name()
    df["Month"] = df[date_col].dt.month
    df["Quarter"] = df[date_col].dt.quarter
    df["Year"] = df[date_col].dt.year
    df["IsWeekend"] = df["DayOfWeek"].isin(["Saturday", "Sunday"]).astype("Int64")
    df["PeakHour"] = df["OrderHour"].apply(
        lambda h: 1 if (pd.notna(h) and (12 <= h <= 14 or 19 <= h <= 21)) else 0
    )
    return df


def compute_customer_order_stats(orders):
    """All-time totals per customer: how many orders, lifetime spend, avg basket."""
    return orders.groupby("CustomerID").agg(
        CustomerOrderCount=("OrderID", "count"),
        CustomerLifetimeValue=("FinalAmount", "sum"),
        AverageBasketValue=("FinalAmount", "mean"),
    ).reset_index()


def compute_restaurant_order_stats(orders):
    """All-time totals per restaurant: how many orders, total revenue."""
    stats = orders.groupby("RestaurantID").agg(
        RestaurantOrderCount=("OrderID", "count"),
        RestaurantRevenue=("FinalAmount", "sum"),
    ).reset_index()
    stats["RestaurantPopularity"] = (stats["RestaurantOrderCount"].rank(pct=True) * 100).round(1)
    return stats


def add_gap_since_previous_order(orders):
    """
    Add RecencyDays = days since THIS customer's previous order
    (their very first order gets a blank, since there's no "previous" one).
    """
    orders = orders.sort_values(["CustomerID", "OrderDate", "OrderTime"]).copy()
    orders["PrevOrderDate"] = orders.groupby("CustomerID")["OrderDate"].shift(1)
    orders["RecencyDays"] = (orders["OrderDate"] - orders["PrevOrderDate"]).dt.days
    return orders


def orders_ready_for_analytics(orders):
    """
    Drop orders with no valid CustomerID/RestaurantID before building the
    analytical tables (~25 rows). This is separate from src/clean.py's
    orphan-handling because clean.py works on RAW data and sets orphans
    to NaN (keeping the row); here, one step later, we actually need
    those rows gone since every join below assumes a real customer and
    restaurant on every order.
    """
    ready = orders.dropna(subset=["CustomerID", "RestaurantID"]).copy()
    ready["CustomerID"] = ready["CustomerID"].astype(int)
    ready["RestaurantID"] = ready["RestaurantID"].astype(int)
    return ready


# ---------------------------------------------------------------
# Orchestrator: order_analytics.csv
# ---------------------------------------------------------------

def build_order_analytics(data, orders):
    """Build the order-level analytical table (1 row = 1 order)."""
    customers, restaurants = data["customers"], data["restaurants"]
    partners, feedback = data["delivery_partners"], data["customer_feedback"]

    df = add_gap_since_previous_order(orders)

    df = df.merge(
        customers[["CustomerID", "Age", "Gender", "Membership", "City", "PreferredCuisine", "RegistrationDate"]]
        .rename(columns={"Age": "CustomerAge", "Gender": "CustomerGender", "City": "CustomerCity"}),
        on="CustomerID", how="left",
    )
    df = df.merge(
        restaurants[["RestaurantID", "RestaurantName", "Cuisine", "City", "Rating", "AverageCost",
                     "RestaurantType", "Latitude", "Longitude"]]
        .rename(columns={"City": "RestaurantCity", "Rating": "RestaurantRating"}),
        on="RestaurantID", how="left",
    )
    df = df.merge(
        partners[["DeliveryPartnerID", "VehicleType", "City", "Rating", "CompletedDeliveries", "AverageDeliveryTime"]]
        .rename(columns={"City": "PartnerCity", "Rating": "PartnerRating", "AverageDeliveryTime": "PartnerAverageDeliveryTime"}),
        on="DeliveryPartnerID", how="left",
    )
    df = df.merge(compute_customer_order_stats(orders), on="CustomerID", how="left")
    df = df.merge(compute_restaurant_order_stats(orders), on="RestaurantID", how="left")
    df = df.merge(aggregate_order_items(data["order_items"], data["menu"]), on="OrderID", how="left")
    df = df.merge(feedback[["OrderID", "CustomerRating", "DeliveryRating", "FoodRating", "Sentiment"]],
                   on="OrderID", how="left")

    weather_agg = aggregate_weather(data["weather"])
    df = df.merge(weather_agg, left_on=["RestaurantCity", "OrderDate"], right_on=["City", "Date"], how="left")
    df = df.drop(columns=["City", "Date"])

    traffic_agg = aggregate_traffic(data["traffic"])
    df = df.merge(traffic_agg, left_on=["RestaurantCity", "OrderDate"], right_on=["City", "Date"], how="left")
    df = df.drop(columns=["City", "Date"])

    city_partner_avg = partners.groupby("City")["AverageDeliveryTime"].mean().rename("CityAvgPartnerTime")
    df = df.merge(city_partner_avg, left_on="PartnerCity", right_index=True, how="left")

    # derived columns
    df["CustomerTenure"] = (df["OrderDate"] - df["RegistrationDate"]).dt.days
    df["OrderFrequency"] = df["CustomerOrderCount"] / df["CustomerTenure"].replace(0, np.nan)
    df = add_temporal_features(df)
    df["TrafficScore"] = df["TrafficLevel"].map(TRAFFIC_SCORE_MAP)
    df["RainImpact"] = df["Rainfall"].apply(rain_bucket)
    df["HasRain"] = (df["Rainfall"] > 0).astype("Int64")
    df["DeliveryEfficiency"] = df["PartnerAverageDeliveryTime"] / df["CityAvgPartnerTime"]
    df["BasketSize"] = df["TotalQuantity"]
    order_total = (df["FoodCost"] + df["DeliveryFee"] + df["GST"]).replace(0, np.nan)
    df["DiscountRate"] = (df["Discount"] / order_total).round(4)
    df["HasCoupon"] = df["CouponCode"].notna().astype("Int64")
    df["LateDelivery"] = (df["OrderStatus"] == "Delivered Late").astype("Int64")
    df["DeliveryTimeTarget"] = np.where(
        df["OrderStatus"].isin(["Delivered", "Delivered Late"]), df["DeliveryTimeMinutes"], np.nan
    )
    df["SameCity"] = (df["CustomerCity"] == df["RestaurantCity"]).astype("Int64")

    columns = [
        "OrderID", "OrderDate", "OrderTime", "OrderHour", "DayOfWeek", "Month", "Quarter", "Year", "IsWeekend", "PeakHour",
        "OrderStatus", "PaymentMethod", "FoodCost", "DeliveryFee", "Discount", "DiscountRate", "GST", "FinalAmount",
        "CouponCode", "HasCoupon",
        "CustomerID", "CustomerAge", "CustomerGender", "Membership", "CustomerCity", "PreferredCuisine", "RegistrationDate",
        "CustomerTenure", "CustomerOrderCount", "CustomerLifetimeValue", "AverageBasketValue", "OrderFrequency", "RecencyDays",
        "RestaurantID", "RestaurantName", "Cuisine", "RestaurantCity", "RestaurantRating", "AverageCost", "RestaurantType",
        "Latitude", "Longitude", "RestaurantOrderCount", "RestaurantRevenue", "RestaurantPopularity",
        "DeliveryPartnerID", "VehicleType", "PartnerRating", "CompletedDeliveries", "PartnerAverageDeliveryTime", "DeliveryEfficiency",
        "DeliveryTimeMinutes", "DeliveryTimeTarget", "LateDelivery",
        "TrafficLevel", "TrafficScore", "AverageSpeed", "Temperature", "Rainfall", "Humidity", "WeatherCondition", "RainImpact", "HasRain",
        "TotalQuantity", "UniqueItems", "ItemRevenue", "AverageItemPrice", "RestaurantPreparationTime", "BasketSize",
        "CustomerRating", "DeliveryRating", "FoodRating", "Sentiment", "SameCity",
    ]
    return df[columns]


# ---------------------------------------------------------------
# Orchestrator: customer_analytics.csv  (time-aware churn)
# ---------------------------------------------------------------

def build_customer_analytics(data, orders, observation_days_before_end=60, churn_window_days=60):
    """
    Build the customer-level table with a churn label that only ever
    looks at information available BEFORE the observation date, so the
    model can't accidentally "see the future".
    """
    customers = data["customers"]
    feedback = data["customer_feedback"]

    orders_dated = orders.dropna(subset=["OrderDate"]).copy()
    max_date = orders_dated["OrderDate"].max()
    obs_date = max_date - pd.Timedelta(days=observation_days_before_end)

    hist = orders_dated[orders_dated["OrderDate"] <= obs_date].copy()
    future = orders_dated[
        (orders_dated["OrderDate"] > obs_date)
        & (orders_dated["OrderDate"] <= obs_date + pd.Timedelta(days=churn_window_days))
    ]
    base_customers = hist["CustomerID"].unique()

    agg = hist.groupby("CustomerID").agg(
        TotalOrders=("OrderID", "count"),
        TotalRevenue=("FinalAmount", "sum"),
        AverageOrderValue=("FinalAmount", "mean"),
        AverageDeliveryTime=("DeliveryTimeMinutes", "mean"),
        FirstOrderDate=("OrderDate", "min"),
        LastOrderDate=("OrderDate", "max"),
        CancelledOrders=("OrderStatus", lambda s: (s == "Cancelled").sum()),
        CouponOrders=("CouponCode", lambda s: s.notna().sum()),
    ).reset_index()

    agg["CancellationRate"] = (agg["CancelledOrders"] / agg["TotalOrders"]).round(4)
    agg["CouponUsageRate"] = (agg["CouponOrders"] / agg["TotalOrders"]).round(4)
    agg["RecencyDays"] = (obs_date - agg["LastOrderDate"]).dt.days

    reg_dates = customers.set_index("CustomerID")["RegistrationDate"]
    agg["CustomerTenure"] = (obs_date - agg["CustomerID"].map(reg_dates)).dt.days
    agg["OrderFrequency"] = agg["TotalOrders"] / agg["CustomerTenure"].replace(0, np.nan)

    hist["IsWeekend"] = hist["OrderDate"].dt.day_name().isin(["Saturday", "Sunday"])
    weekend_rate = hist.groupby("CustomerID")["IsWeekend"].mean().rename("WeekendOrderRate")
    agg = agg.merge(weekend_rate, on="CustomerID", how="left")

    def orders_in_window(start_days_ago, end_days_ago):
        window = hist[
            (hist["OrderDate"] > obs_date - pd.Timedelta(days=start_days_ago))
            & (hist["OrderDate"] <= obs_date - pd.Timedelta(days=end_days_ago))
        ]
        return window.groupby("CustomerID").size()

    agg = agg.merge(orders_in_window(30, 0).rename("OrdersLast30Days"), on="CustomerID", how="left")
    agg = agg.merge(orders_in_window(60, 0).rename("OrdersLast60Days"), on="CustomerID", how="left")
    agg = agg.merge(orders_in_window(120, 60).rename("OrdersPrevious60Days"), on="CustomerID", how="left")
    for col in ["OrdersLast30Days", "OrdersLast60Days", "OrdersPrevious60Days"]:
        agg[col] = agg[col].fillna(0).astype(int)

    fb_hist = feedback.merge(hist[["OrderID", "CustomerID"]], on="OrderID", how="inner")
    avg_rating = fb_hist.groupby("CustomerID")["CustomerRating"].mean().rename("AverageRating")
    agg = agg.merge(avg_rating, on="CustomerID", how="left")

    profile = customers[["CustomerID", "Age", "Gender", "City", "Membership", "RegistrationDate", "PreferredCuisine"]]
    result = profile[profile["CustomerID"].isin(base_customers)].merge(agg, on="CustomerID", how="left")
    result = result.rename(columns={"TotalRevenue": "CustomerLifetimeValue"})

    churned_ids = set(base_customers) - set(future["CustomerID"].unique())
    result["Churn60"] = result["CustomerID"].isin(churned_ids).astype(int)

    columns = [
        "CustomerID", "Age", "Gender", "City", "Membership", "RegistrationDate",
        "TotalOrders", "CustomerLifetimeValue", "AverageOrderValue", "AverageDeliveryTime", "AverageRating",
        "FirstOrderDate", "LastOrderDate", "RecencyDays", "OrderFrequency",
        "OrdersLast30Days", "OrdersLast60Days", "OrdersPrevious60Days",
        "CouponUsageRate", "CancellationRate", "WeekendOrderRate", "PreferredCuisine",
        "CustomerTenure", "Churn60",
    ]
    return result[columns]


# ---------------------------------------------------------------
# Orchestrator: restaurant_analytics.csv
# ---------------------------------------------------------------

def build_restaurant_analytics(data, orders):
    """Build the restaurant-level table (1 row = 1 restaurant)."""
    restaurants = data["restaurants"]
    feedback = data["customer_feedback"]

    r_orders = orders.groupby("RestaurantID").agg(
        TotalOrders=("OrderID", "count"),
        CompletedOrders=("OrderStatus", lambda s: s.isin(["Delivered", "Delivered Late"]).sum()),
        CancelledOrders=("OrderStatus", lambda s: (s == "Cancelled").sum()),
        LateOrders=("OrderStatus", lambda s: (s == "Delivered Late").sum()),
        TotalRevenue=("FinalAmount", "sum"),
        AverageOrderValue=("FinalAmount", "mean"),
        AverageDeliveryTime=("DeliveryTimeMinutes", "mean"),
    ).reset_index()
    r_orders["CancellationRate"] = (r_orders["CancelledOrders"] / r_orders["TotalOrders"]).round(4)
    r_orders["LateDeliveryRate"] = (r_orders["LateOrders"] / r_orders["TotalOrders"]).round(4)

    r_feedback = feedback.merge(orders[["OrderID", "RestaurantID"]], on="OrderID", how="inner")
    avg_rating = r_feedback.groupby("RestaurantID")["CustomerRating"].mean().rename("AverageCustomerRating")

    result = (
        restaurants[["RestaurantID", "RestaurantName", "City", "Cuisine", "RestaurantType", "Rating", "AverageCost"]]
        .merge(r_orders, on="RestaurantID", how="left")
        .merge(avg_rating, on="RestaurantID", how="left")
    )
    for col in ["TotalOrders", "CompletedOrders", "CancelledOrders", "LateOrders", "TotalRevenue"]:
        result[col] = result[col].fillna(0)

    result["RestaurantPopularity"] = (result["TotalOrders"].rank(pct=True) * 100).round(1)
    result["RevenueRankCity"] = result.groupby("City")["TotalRevenue"].rank(ascending=False, method="min").astype("Int64")

    def normalize(series):
        """Scale a column to 0-1 so different units can be combined fairly."""
        if series.max() == series.min():
            return series * 0
        return (series - series.min()) / (series.max() - series.min())

    result["PerformanceScore"] = (
        0.40 * normalize(result["Rating"].fillna(result["Rating"].mean()))
        + 0.30 * normalize(result["TotalRevenue"])
        + 0.15 * normalize(result["TotalOrders"])
        + 0.15 * (1 - result["CancellationRate"].fillna(0))
    ).round(4)

    result["PerformanceCategory"] = pd.qcut(
        result["PerformanceScore"], 4, labels=["Poor", "Average", "Good", "Top"]
    )

    columns = [
        "RestaurantID", "RestaurantName", "City", "Cuisine", "RestaurantType", "Rating", "AverageCost",
        "TotalOrders", "CompletedOrders", "CancelledOrders", "CancellationRate",
        "TotalRevenue", "AverageOrderValue", "AverageDeliveryTime", "AverageCustomerRating",
        "LateDeliveryRate", "RestaurantPopularity", "RevenueRankCity", "PerformanceScore", "PerformanceCategory",
    ]
    return result[columns]
