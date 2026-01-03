import numpy as np

from chicago_crimes.feature_engineer import (
    compute_class_weights,
    convert_to_dict_features,
    create_features_target,
    get_feature_statistics,
)


class TestFeatureEngineer:
    def test_create_features_target(self, sample_processed_data):
        """Test feature-target separation."""
        X, y = create_features_target(sample_processed_data)

        # Check that X contains feature columns
        expected_features = ["primary_type", "domestic", "district", "fbi_code"]
        for feature in expected_features:
            if feature in sample_processed_data.columns:
                assert feature in X.columns

        # Check that y is the target
        assert y.name == "arrest"
        assert y.dtype == int

    def test_compute_class_weights(self):
        """Test class weight computation for imbalanced data."""
        # Create imbalanced labels
        y_imbalanced = np.array([0, 0, 0, 0, 1])  # 4:1 ratio

        sample_weights = compute_class_weights(y_imbalanced)

        assert isinstance(sample_weights, dict)
        assert 0 in sample_weights
        assert 1 in sample_weights
        # Minority class should have higher weight
        assert sample_weights[1] > sample_weights[0]

    def test_convert_to_dict_features(self, sample_features):
        """Test conversion of DataFrame to dictionary records."""
        features_dict = convert_to_dict_features(sample_features)

        assert isinstance(features_dict, list)
        assert isinstance(features_dict[0], dict)
        # Check that dictionary contains expected keys
        expected_keys = ["primary_type", "domestic", "district"]
        for key in expected_keys:
            if key in sample_features.columns:
                assert key in features_dict[0]

    def test_get_feature_statistics(self, sample_processed_data, capsys):
        """Test feature statistics printing."""
        get_feature_statistics(sample_processed_data)

        captured = capsys.readouterr()
        # Check that output contains feature names
        assert "primary_type" in captured.out or any(
            col in captured.out for col in sample_processed_data.columns
        )
