import pickle

import numpy as np
import xgboost as xgb
from sklearn.pipeline import make_pipeline
from sklearn.feature_extraction import DictVectorizer

from chicago_crimes.config import MODEL_DIR, MODEL_PARAMS


def create_xgb_pipeline(sample_weights, model_params=None):
    """Create XGBoost pipeline with DictVectorizer."""
    if model_params is None:
        model_params = MODEL_PARAMS.copy()

    # Add scale_pos_weight for class imbalance
    model_params["scale_pos_weight"] = sample_weights.get(1, 1)

    model = xgb.XGBClassifier(**model_params)

    pipeline = make_pipeline(DictVectorizer(sparse=True, dtype=np.float32), model)

    return pipeline


def train_model(pipeline, X_train_dict, y_train):
    """Train the model pipeline."""
    pipeline.fit(X_train_dict, y_train)
    return pipeline


def save_model(pipeline, model_path=None):
    """Save trained model to disk."""
    if model_path is None:
        model_path = MODEL_DIR / "xgb_model.pkl"

    with open(model_path, "wb") as f_out:
        pickle.dump(pipeline, f_out)

    print(f"Model saved to {model_path}")


def load_model(model_path=None):
    """Load trained model from disk."""
    if model_path is None:
        model_path = MODEL_DIR / "xgb_model.pkl"

    with open(model_path, "rb") as f_in:
        pipeline = pickle.load(f_in)

    return pipeline
