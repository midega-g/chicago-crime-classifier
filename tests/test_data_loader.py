from unittest.mock import mock_open, patch

from chicago_crimes.data_loader import (
    get_feature_columns,
    load_location_mapping,
    prepare_features,
)


class TestDataLoader:
    def test_load_location_mapping(self):
        """Test loading location mapping from JSON."""
        # Mock the JSON file content
        mock_json_content = '{"STREET": "Street/Public", "RESIDENCE": "Residential"}'

        with patch("builtins.open", mock_open(read_data=mock_json_content)):
            with patch("json.load") as mock_json_load:
                mock_json_load.return_value = {
                    "STREET": "Street/Public",
                    "RESIDENCE": "Residential",
                }
                mapping = load_location_mapping("dummy_path.json")

        assert isinstance(mapping, dict)
        assert "STREET" in mapping

    def test_prepare_features(self, sample_dataframe):
        """Test feature preparation function."""
        # Mock location mapping
        location_mapping = {"STREET": "Street/Public", "RESIDENCE": "Residential"}

        result_df = prepare_features(sample_dataframe.copy(), location_mapping)

        # Check that new features are created
        assert "hour" in result_df.columns
        assert "day_of_week" in result_df.columns
        assert "is_night" in result_df.columns
        assert "is_weekend" in result_df.columns
        assert "location_group" in result_df.columns

        # Check that original columns are removed
        assert "date" not in result_df.columns
        assert "location_description" not in result_df.columns

        # Check data types
        assert result_df["is_night"].dtype in [int, bool]
        assert result_df["is_weekend"].dtype in [int, bool]

    def test_get_feature_columns(self, mock_data_file):
        """Test dynamic feature column detection."""
        columns = get_feature_columns(mock_data_file)
        assert isinstance(columns, list)
        assert len(columns) > 0
