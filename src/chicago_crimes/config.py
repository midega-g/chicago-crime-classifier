from pathlib import Path

# Get the project root directory (where pyproject.toml is located)
PROJECT_ROOT = Path(__file__).parent.parent.parent

# absolute data paths
DATA_DIR = PROJECT_ROOT / "data"
MODEL_DIR = PROJECT_ROOT / "models"
TRAIN_DATA_PATH = DATA_DIR / "train_2022_2023.csv.gz"
VAL_DATA_PATH = DATA_DIR / "val_2024.csv.gz"
TEST_DATA_PATH = DATA_DIR / "test_2025.csv.gz"

# Feature configuration
REMOVE_COLS = [
    "id",
    "updated_on",
    "block",
    "iucr",
    "beat",
    "description",
    "latitude",
    "longitude",
    "location",
    "year",
    "y_coordinate",
    "x_coordinate",
    "case_number",
    "id",
]

FEATURE_COLS = [
    "primary_type",
    "domestic",
    "district",
    "ward",
    "community_area",
    "fbi_code",
    "hour",
    "day_of_week",
    "month",
    "quarter",
    "is_night",
    "is_weekend",
    "location_group",
]

# Model configuration
MODEL_PARAMS = {
    "objective": "binary:logistic",
    "eval_metric": "auc",
    "random_state": 42,
    "n_estimators": 100,
    "learning_rate": 0.1,
    "max_depth": 6,
    "subsample": 0.8,
    "colsample_bytree": 0.8,
}

# Ensure directories exist
MODEL_DIR.mkdir(exist_ok=True)
DATA_DIR.mkdir(exist_ok=True)
