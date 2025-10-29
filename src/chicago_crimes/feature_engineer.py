import numpy as np
from sklearn.utils.class_weight import compute_class_weight

from chicago_crimes.config import FEATURE_COLS


def create_features_target(df, target_col="arrest"):
    """Split dataframe into features and target."""
    X = df[FEATURE_COLS]
    y = df[target_col].astype("int")
    return X, y


def compute_class_weights(y):
    """Compute class weights for imbalanced dataset."""
    classes = np.unique(y)
    class_weights = compute_class_weight("balanced", classes=classes, y=y)
    sample_weights = {cls: w for cls, w in zip(classes, class_weights)}
    return sample_weights


def convert_to_dict_features(X):
    """Convert DataFrame to dictionary records for DictVectorizer."""
    return X.to_dict(orient="records")


def get_feature_statistics(df):
    """Print statistics about each feature column."""
    for col in df.columns.tolist():
        print(f"{col}: {df[col].nunique()}")

    print("\nValue counts for each column:")
    for col in df.columns.tolist():
        print(f"\n{col}:")
        print(df[col].value_counts())
