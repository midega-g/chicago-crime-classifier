# pylint: disable=redefined-outer-name
from unittest.mock import MagicMock

import numpy as np
import pandas as pd
import pytest


@pytest.fixture
def sample_dataframe():
    """Create a sample DataFrame for testing."""
    data = {
        "date": pd.date_range("2023-01-01", periods=5, freq="D"),
        "primary_type": ["THEFT", "BATTERY", "THEFT", "ASSAULT", "ROBBERY"],
        "location_description": [
            "STREET",
            "RESIDENCE",
            "STREET",
            "RESIDENCE",
            "STREET",
        ],
        "arrest": [False, True, False, True, False],
        "domestic": [False, True, False, False, True],
        "district": [1, 2, 1, 3, 2],
        "ward": [1.0, 2.0, 1.0, 3.0, 2.0],
        "community_area": [1.0, 2.0, 1.0, 3.0, 2.0],
        "fbi_code": ["06", "08B", "06", "08A", "03"],
    }
    return pd.DataFrame(data)


@pytest.fixture
def sample_processed_data(sample_dataframe):
    """Create sample processed data with engineered features."""
    df = sample_dataframe.copy()
    # Add engineered features that would be created by prepare_features
    df["hour"] = [12, 18, 15, 3, 20]
    df["day_of_week"] = [0, 1, 2, 3, 4]
    df["month"] = [1, 1, 1, 1, 1]
    df["quarter"] = [1, 1, 1, 1, 1]
    df["is_night"] = [0, 1, 0, 1, 1]
    df["is_weekend"] = [0, 0, 0, 0, 0]
    df["location_group"] = [
        "Street/Public",
        "Residential",
        "Street/Public",
        "Residential",
        "Street/Public",
    ]

    # Remove original columns that would be dropped
    df.drop(["date", "location_description"], axis=1, inplace=True, errors="ignore")
    return df


@pytest.fixture
def sample_features(sample_processed_data):
    """Extract features from processed data."""
    feature_cols = [col for col in sample_processed_data.columns if col != "arrest"]
    return sample_processed_data[feature_cols]


@pytest.fixture
def sample_training_data(sample_processed_data):
    """Create sample training data in dictionary format."""
    X = sample_processed_data.drop("arrest", axis=1)
    y = sample_processed_data["arrest"].astype(int)
    X_dict = X.to_dict("records")
    return X_dict, y


@pytest.fixture
def mock_pipeline():
    """Create a mock pipeline for testing."""
    pipeline = MagicMock()
    pipeline.fit.return_value = pipeline
    return pipeline


@pytest.fixture
def mock_trained_pipeline():
    """Create a mock trained pipeline for evaluation tests."""
    pipeline = MagicMock()
    # Return numpy arrays for predict_proba
    pipeline.predict_proba.return_value = np.array([[0.8, 0.2], [0.3, 0.7], [0.9, 0.1]])
    pipeline.predict.return_value = np.array([0, 1, 0])
    return pipeline


@pytest.fixture
def mock_data_file(tmp_path):
    """Create a mock data file for testing."""
    file_path = tmp_path / "mock_data.csv.gz"
    # Create a minimal CSV file
    df = pd.DataFrame(
        {
            "id": [1, 2, 3],
            "date": ["2023-01-01", "2023-01-02", "2023-01-03"],
            "primary_type": ["THEFT", "BATTERY", "ASSAULT"],
        }
    )
    df.to_csv(file_path, index=False, compression="gzip")
    return file_path


@pytest.fixture
def mock_location_mapping():
    """Create a mock location mapping."""
    return {
        "STREET": "Street/Public Open",
        "RESIDENCE": "Residential",
        "APARTMENT": "Residential",
        "SIDEWALK": "Street/Public Open",
        "RESTAURANT": "Food/Entertainment/Recreation",
    }
