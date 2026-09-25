"""
model_churn.py
--------------
Predicts Churn60 (1 = customer placed NO order in the 60 days after the
observation date) using customer_analytics.csv.

Same style as model_delivery.py: plain functions, one job each - load data,
prep features, train, compare, tune, score, save. No classes.

Usage:
    from model_churn import (
        load_customer_analytics, prepare_features, split_data,
        train_baseline_models, compare_models, tune_best_models,
        get_feature_importance, build_predictions, save_model,
    )

    df = load_customer_analytics("../data/analytical/customer_analytics.csv")
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
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.tree import DecisionTreeClassifier
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.utils.class_weight import compute_sample_weight
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score, f1_score, roc_auc_score,
)

# Every feature below was calculated ONLY from orders on/before the
# observation date (see feature_dictionary.md), so none of them can "see"
# the 60-day window that Churn60 is measured on.
#
# Left out on purpose:
#   CustomerID, RegistrationDate, FirstOrderDate, LastOrderDate - identifiers / raw dates
#   OrderFrequency - built from CustomerTenure, which is negative for ~400
#                    customers (registered AFTER their first order in the source data)
NUMERIC_FEATURES = [
    "Age", "TotalOrders", "CustomerLifetimeValue", "AverageOrderValue",
    "AverageDeliveryTime", "AverageRating", "RecencyDays",
    "OrdersLast30Days", "OrdersLast60Days", "OrdersPrevious60Days",
    "CouponUsageRate", "CancellationRate", "WeekendOrderRate", "CustomerTenure",
]
CATEGORICAL_FEATURES = ["Gender", "City", "Membership", "PreferredCuisine"]

TARGET = "Churn60"

ALL_FEATURES = NUMERIC_FEATURES + CATEGORICAL_FEATURES


def load_customer_analytics(path):
    """Read customer_analytics.csv."""
    return pd.read_csv(path)


def prepare_features(df):
    """
    Split into X (features) / y (target).
    One small fix: a negative CustomerTenure is impossible (it means the
    registration date is AFTER the first order), so those are set to 0.
    """
    df = df.copy()
    df["CustomerTenure"] = df["CustomerTenure"].clip(lower=0)
    X = df[ALL_FEATURES].copy()
    y = df[TARGET].copy()
    return X, y


def split_data(X, y, test_size=0.2, random_state=42):
    """
    80/20 split. stratify=y keeps the same churn % (~88%) in both halves,
    which matters a lot when one class is this rare.
    """
    return train_test_split(X, y, test_size=test_size, random_state=random_state, stratify=y)


def build_preprocessor():
    """
    Numeric: fill blanks with the median, then scale (helps Logistic Regression;
    harmless for the tree models).
    Categorical: fill blanks with "Unknown", then one-hot encode.
    """
    numeric_pipeline = Pipeline([
        ("impute", SimpleImputer(strategy="median")),
        ("scale", StandardScaler()),
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
    """
    The 4 models the plan asks for.
    Class imbalance (only ~12% of customers do NOT churn) is handled with
    class_weight="balanced" - the minority class counts more during training.
    Gradient Boosting has no class_weight option, so it gets sample weights
    instead (see _fit_pipeline).
    """
    return {
        "Logistic Regression": LogisticRegression(max_iter=1000, class_weight="balanced"),
        "Decision Tree": DecisionTreeClassifier(max_depth=5, class_weight="balanced", random_state=42),
        "Random Forest": RandomForestClassifier(
            n_estimators=200, max_depth=8, class_weight="balanced", random_state=42, n_jobs=-1
        ),
        "Gradient Boosting": GradientBoostingClassifier(random_state=42),
    }


def _fit_pipeline(pipeline, X_train, y_train):
    """Fit a pipeline. Gradient Boosting needs balanced sample weights passed in by hand."""
    if isinstance(pipeline.named_steps["model"], GradientBoostingClassifier):
        weights = compute_sample_weight("balanced", y_train)
        pipeline.fit(X_train, y_train, model__sample_weight=weights)
    else:
        pipeline.fit(X_train, y_train)
    return pipeline


def score_model(pipeline, X_test, y_test):
    """Accuracy / Precision / Recall / F1 / ROC-AUC for one fitted pipeline."""
    predictions = pipeline.predict(X_test)
    probabilities = pipeline.predict_proba(X_test)[:, 1]
    return {
        "Accuracy": accuracy_score(y_test, predictions),
        "Precision": precision_score(y_test, predictions),
        "Recall": recall_score(y_test, predictions),
        "F1": f1_score(y_test, predictions),
        "ROC_AUC": roc_auc_score(y_test, probabilities),
    }


def train_baseline_models(X_train, y_train, X_test, y_test):
    """
    Train all 4 models, each wrapped in the same preprocessing pipeline.
    Returns:
        results - dict of {model_name: {Accuracy, Precision, Recall, F1, ROC_AUC}}
        fitted  - dict of {model_name: fitted Pipeline}
    """
    results = {}
    fitted = {}

    for name, model in _model_zoo().items():
        pipeline = Pipeline([
            ("preprocess", build_preprocessor()),
            ("model", model),
        ])
        pipeline = _fit_pipeline(pipeline, X_train, y_train)
        results[name] = score_model(pipeline, X_test, y_test)
        fitted[name] = pipeline

    return results, fitted


def compare_models(results):
    """Turn the results dict into a tidy comparison table, best ROC-AUC first."""
    table = pd.DataFrame(results).T.round(3)
    return table.sort_values("ROC_AUC", ascending=False)


def tune_best_models(X_train, y_train, top_model_names, n_iter=6, cv=3, random_state=42):
    """
    Tune only the top 2 models from the comparison table (the plan's
    time-saving call). Small grids + cv=3, scored on ROC-AUC.
    """
    param_grids = {
        "Logistic Regression": {"model__C": [0.01, 0.1, 1, 10]},
        "Decision Tree": {
            "model__max_depth": [3, 5, 8],
            "model__min_samples_leaf": [10, 30, 60],
        },
        "Random Forest": {
            "model__n_estimators": [100, 200],
            "model__max_depth": [4, 6, 8],
            "model__min_samples_leaf": [5, 20, 50],
        },
        "Gradient Boosting": {
            "model__n_estimators": [50, 100, 150],
            "model__learning_rate": [0.05, 0.1],
            "model__max_depth": [2, 3],
        },
    }
    model_zoo = _model_zoo()

    tuned = {}
    for name in top_model_names:
        pipeline = Pipeline([
            ("preprocess", build_preprocessor()),
            ("model", model_zoo[name]),
        ])
        # Gradient Boosting needs sample weights passed to fit, which
        # RandomizedSearchCV can do through fit_params.
        fit_params = {}
        if name == "Gradient Boosting":
            fit_params["model__sample_weight"] = compute_sample_weight("balanced", y_train)

        search = RandomizedSearchCV(
            pipeline, param_grids[name], n_iter=n_iter, cv=cv,
            scoring="roc_auc", random_state=random_state, n_jobs=-1,
        )
        search.fit(X_train, y_train, **fit_params)
        tuned[name] = search.best_estimator_

    return tuned


def get_feature_importance(fitted_pipeline, model_name):
    """
    Feature -> importance for a fitted pipeline. Tree models use
    feature_importances_; Logistic Regression uses |coefficient| (features
    are scaled, so the sizes are comparable).
    """
    feature_names = fitted_pipeline.named_steps["preprocess"].get_feature_names_out()
    model = fitted_pipeline.named_steps["model"]

    if hasattr(model, "feature_importances_"):
        values = model.feature_importances_
    elif hasattr(model, "coef_"):
        values = np.abs(model.coef_[0])
    else:
        raise ValueError(f"Don't know how to get importance from {model_name}")

    return (
        pd.DataFrame({"Feature": feature_names, "Importance": values})
        .sort_values("Importance", ascending=False)
        .reset_index(drop=True)
    )


def risk_segment(probability):
    """0-0.33 Low, 0.33-0.66 Medium, 0.66-1.00 High (as in the plan)."""
    if probability < 0.33:
        return "Low"
    if probability < 0.66:
        return "Medium"
    return "High"


def build_predictions(pipeline, df, X_train_index):
    """
    Score EVERY customer and return the table Power BI will use:
    CustomerID, ActualChurn, PredictedChurn, ChurnProbability, RiskSegment, Split.
    'Split' says whether the customer was in the training or test data, so
    nobody mistakes the (over-optimistic) training rows for real performance.
    """
    X, y = prepare_features(df)
    probabilities = pipeline.predict_proba(X)[:, 1]

    predictions = pd.DataFrame({
        "CustomerID": df["CustomerID"],
        "ActualChurn": y,
        "PredictedChurn": pipeline.predict(X),
        "ChurnProbability": probabilities.round(4),
    })
    predictions["RiskSegment"] = predictions["ChurnProbability"].apply(risk_segment)
    predictions["Split"] = np.where(df.index.isin(X_train_index), "Train", "Test")
    return predictions


def save_model(pipeline, path):
    """Save a fitted pipeline (preprocessing + model bundled together) to disk."""
    joblib.dump(pipeline, path)


if __name__ == "__main__":
    # Quick manual test: run "python model_churn.py" from the src/ folder
    df = load_customer_analytics("../data/analytical/customer_analytics.csv")
    X, y = prepare_features(df)
    print("Customers:", len(X), "| churn rate:", round(y.mean(), 3))

    X_train, X_test, y_train, y_test = split_data(X, y)
    results, fitted = train_baseline_models(X_train, y_train, X_test, y_test)
    print(compare_models(results))
