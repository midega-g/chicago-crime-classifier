"""Tests for configuration module."""

from chicago_crimes.config import (
    DATA_DIR,
    MODEL_DIR,
    REMOVE_COLS,
    FEATURE_COLS,
    MODEL_PARAMS,
    PROJECT_ROOT,
    TRAIN_DATA_PATH,
)


class TestConfig:
    """Test configuration settings and paths."""

    def test_project_root_exists(self):
        """Test that PROJECT_ROOT points to a valid directory."""
        assert PROJECT_ROOT.exists()
        assert (PROJECT_ROOT / "pyproject.toml").exists()

    def test_data_directories(self):
        """Test that data directories are correctly configured."""
        assert DATA_DIR == PROJECT_ROOT / "data"
        assert MODEL_DIR == PROJECT_ROOT / "models"

    def test_data_paths(self):
        """Test that data file paths are correctly constructed."""
        assert TRAIN_DATA_PATH == DATA_DIR / "train_2022_2023.csv.gz"

    def test_feature_configuration(self):
        """Test feature configuration."""
        assert isinstance(REMOVE_COLS, list)
        assert isinstance(FEATURE_COLS, list)
        assert len(FEATURE_COLS) > 0
        # Ensure no overlap between removed and included columns
        assert not set(FEATURE_COLS).intersection(set(REMOVE_COLS))

    def test_model_params(self):
        """Test model parameters configuration."""
        assert "objective" in MODEL_PARAMS
        assert "random_state" in MODEL_PARAMS
        assert MODEL_PARAMS["objective"] == "binary:logistic"
