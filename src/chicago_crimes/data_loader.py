import pandas as pd
import json
from pathlib import Path
from chicago_crimes.config import REMOVE_COLS


def load_data(file_path, usecols=None, parse_dates=['date']):
    """Load data from CSV with gzip compression."""
    return pd.read_csv(file_path, compression='gzip', usecols=usecols, parse_dates=parse_dates)


def get_feature_columns(data_path):
    """Dynamically determine which columns to include based on removal list."""
    temp_df = pd.read_csv(data_path, compression='gzip', nrows=0)
    all_cols = temp_df.columns.tolist()
    include_cols = [col for col in all_cols if col not in REMOVE_COLS]
    return include_cols


def load_location_mapping(mapping_file=None):
    """Load location description mapping from JSON file."""
    if mapping_file is None:
        # Get the directory where this module is located
        current_dir = Path(__file__).parent
        mapping_file = current_dir / 'location_description.json'
    
    with open(mapping_file, 'r') as file:
        return json.load(file)


def prepare_features(df, location_mapping):
    """Extract temporal features and apply location mapping."""
    # Extract temporal features
    df['hour'] = df['date'].dt.hour
    df['day_of_week'] = df['date'].dt.weekday
    df['month'] = df['date'].dt.month
    df['quarter'] = df['date'].dt.quarter

    # Binary flags
    df['is_night'] = ((df['hour'] >= 18) | (df['hour'] < 6)).astype(int)
    df['is_weekend'] = (df['day_of_week'] >= 5).astype(int)

    # Apply location mapping
    df['location_group'] = df['location_description'].map(
        location_mapping).fillna("Unknown/Other")
    df.drop(columns=['date', 'location_description'], inplace=True)

    return df


def create_dataset(data_path, location_mapping):
    """Create complete dataset from raw data path."""
    include_cols = get_feature_columns(data_path)
    df = load_data(data_path, usecols=include_cols)
    df = prepare_features(df, location_mapping)
    df = df.dropna()  # Remove any remaining null values

    return df
