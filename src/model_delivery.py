"""
model_delivery.py
------------------
Predicts DeliveryTimeMinutes (via order_analytics.csv's `DeliveryTimeTarget`
column, which is already blanked out for orders that were never actually
delivered - see feature_dictionary.md).

Plain functions, one job each - load data, prep features, train, compare,
tune, save. No classes, nothing clever.

Usage:
    from model_delivery import (
        load_order_analytics, prepare_features, split_data,
        train_baseline_models, compare_models, tune_best_models, save_model,
    )

    df = load_order_analytics("../data/analytical/order_analytics.csv")
    X, y = prepare_features(df)
    X_train, X_test, y_train, y_test = split_data(X, y)
    results, fitted = train_baseline_models(X_train, y_train, X_test, y_test)
    comparison_table = compare_models(results)
"""

import numpy as np
import pandas as pd
import joblib

from sklearn.model_selection import train_test_split, RandomizedSearchCV
from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import OneHotEncoder
from sklearn.linear_model import LinearRegression
from sklearn.tree import DecisionTreeRegressor
from sklearn.ensemble import RandomForestRegressor, GradientBoostingRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

# Features the delivery-time model is allowed to use. Deliberately EXCLUDES
# anything only known after the delivery already happened - see the
# "why these features and not others" note in the notebook.
NUMERIC_FEATURES = [
    "BasketSize", "DiscountRate", "RestaurantRating", "PartnerRating",
    "DeliveryEfficiency", "AverageSpeed", "Temperature", "Humidity",
    "OrderHour", "RestaurantPreparationTime", "TrafficScore",
]
CATEGORICAL_FEATURES = ["RainImpact", "DayOfWeek", "PeakHour", "IsWeekend"]

TARGET = "DeliveryTimeTarget"

ALL_FEATURES = NUMERIC_FEATURES + CATEGORICAL_FEATURES


def load_order_analytics(path):
    """Read order_analytics.csv."""
    return pd.read_csv(path)


def prepare_features(df):
    """
    Keep only orders with a real delivery time, and split into X
    (features) / y (target). Rows with no DeliveryTimeTarget (cancelled,
    food not delivered) are dropped - there's nothing to predict there.
    """
    usable = df.dropna(subset=[TARGET]).copy()
    X = usable[ALL_FEATURES].copy()
    y = usable[TARGET].copy()
    return X, y


def split_data(X, y, test_size=0.2, random_state=42):
    """80/20 train/test split."""
    return train_test_split(X, y, test_size=test_size, random_state=random_state)


def build_preprocessor():
    """
    Numeric columns: fill missing values with the median, since ~46% of
    weather/traffic readings are genuinely missing from the source data
    (see feature_dictionary.md) - median is a safe, simple default rather
    than dropping nearly half the rows.
    Categorical columns: fill missing with a literal "Unknown" category,
    then one-hot encode.
    """
    numeric_pipeline = Pipeline([
        ("impute", SimpleImputer(strategy="median")),
    ])
    categorical_pipeline = Pipeline([
        ("impute", SimpleImputer(strategy="constant", fill_value="Unknown")),
        ("encode", OneHotEncoder(handle_unknown="ignore")),
    ])
    return ColumnTransformer([
        ("numeric", numeric_pipeline, NUMERIC_FEATURES),
        ("categorical", categorical_pipeline, CATEGORICAL_FEATURES),
    ])


def _model_zoo():
    """The 4 baseline models the plan asks for, with sensible plain defaults."""
    return {
        "Linear Regression": LinearRegression(),
        "Decision Tree": DecisionTreeRegressor(max_depth=8, random_state=42),
        "Random Forest": RandomForestRegressor(n_estimators=200, max_depth=12, random_state=42, n_jobs=-1),
        "Gradient Boosting": GradientBoostingRegressor(random_state=42),
    }


def train_baseline_models(X_train, y_train, X_test, y_test):
    """
    Train all 4 models, each wrapped in the same preprocessing pipeline.
    Returns:
        results  - dict of {model_name: {MAE, RMSE, R2}}
        fitted   - dict of {model_name: fitted Pipeline}, so you can reuse
                   them later (e.g. for feature importance) without retraining.
    """
    results = {}
    fitted = {}

    for name, model in _model_zoo().items():
        pipeline = Pipeline([
            ("preprocess", build_preprocessor()),
            ("model", model),
        ])
        pipeline.fit(X_train, y_train)
        predictions = pipeline.predict(X_test)

        results[name] = {
            "MAE": mean_absolute_error(y_test, predictions),
            "RMSE": mean_squared_error(y_test, predictions) ** 0.5,
            "R2": r2_score(y_test, predictions),
        }
        fitted[name] = pipeline

    return results, fitted


def compare_models(results):
    """Turn the results dict into a tidy, sorted comparison table."""
    table = pd.DataFrame(results).T.round(3)
    return table.sort_values("MAE")


def tune_best_models(X_train, y_train, top_model_names, n_iter=6, cv=2, random_state=42):
    """
    Tune only the top 2 models from the comparison table (not all 4) -
    that's the plan's explicit time-saving call, and it's the right one
    with a tight deadline. The grids below are deliberately small (a
    handful of combinations, cv=2) so tuning finishes in well under a
    minute rather than exhaustively searching - with signal this weak
    (see the notebook), a bigger search wouldn't change the conclusion.
    """
    param_grids = {
        "Decision Tree": {
            "model__max_depth": [4, 8, 12, None],
            "model__min_samples_leaf": [1, 10, 20],
        },
        "Random Forest": {
            "model__n_estimators": [100, 150, 200],
            "model__max_depth": [8, 12, None],
            "model__min_samples_leaf": [1, 5, 10],
        },
        "Gradient Boosting": {
            "model__n_estimators": [100, 150],
            "model__learning_rate": [0.05, 0.1],
            "model__max_depth": [2, 3],
        },
        "Linear Regression": {},  # nothing meaningful to tune
    }
    model_zoo = _model_zoo()

    tuned = {}
    for name in top_model_names:
        pipeline = Pipeline([
            ("preprocess", build_preprocessor()),
            ("model", model_zoo[name]),
        ])
        grid = param_grids.get(name, {})
        if not grid:
            pipeline.fit(X_train, y_train)
            tuned[name] = pipeline
            continue

        search = RandomizedSearchCV(
            pipeline, grid, n_iter=n_iter, cv=cv,
            scoring="neg_mean_absolute_error", random_state=random_state, n_jobs=-1,
        )
        search.fit(X_train, y_train)
        tuned[name] = search.best_estimator_

    return tuned


def get_feature_importance(fitted_pipeline, model_name):
    """
    Return a DataFrame of feature -> importance for a fitted pipeline.
    Works for tree-based models (feature_importances_) and linear models
    (coefficients). Column names come from the one-hot encoder, so
    categorical features show up as e.g. "RainImpact_Heavy".
    """
    feature_names = fitted_pipeline.named_steps["preprocess"].get_feature_names_out()
    model = fitted_pipeline.named_steps["model"]

    if hasattr(model, "feature_importances_"):
        values = model.feature_importances_
    elif hasattr(model, "coef_"):
        values = np.abs(model.coef_)
    else:
        raise ValueError(f"Don't know how to get importance from {model_name}")

    return (
        pd.DataFrame({"Feature": feature_names, "Importance": values})
        .sort_values("Importance", ascending=False)
        .reset_index(drop=True)
    )


def save_model(pipeline, path):
    """Save a fitted pipeline (preprocessing + model bundled together) to disk."""
    joblib.dump(pipeline, path)


if __name__ == "__main__":
    # Quick manual test: run "python model_delivery.py"
    df = load_order_analytics("/mnt/user-data/outputs/data/analytical/order_analytics.csv")
    X, y = prepare_features(df)
    print("Usable rows:", len(X))

    X_train, X_test, y_train, y_test = split_data(X, y)
    results, fitted = train_baseline_models(X_train, y_train, X_test, y_test)
    print(compare_models(results))
