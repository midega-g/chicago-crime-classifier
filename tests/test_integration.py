# tests/test_integration.py
import pytest
from chicago_crimes.data_loader import load_location_mapping, prepare_features
from chicago_crimes.feature_engineer import create_features_target, compute_class_weights

class TestIntegration:
    
    def test_end_to_end_feature_processing(self, sample_dataframe, mock_location_mapping):
        """Test the complete feature processing pipeline."""
        # Test data loading and preparation
        processed_df = prepare_features(sample_dataframe.copy(), mock_location_mapping)
        
        # Test feature engineering
        X, y = create_features_target(processed_df)
        
        # Test class weight computation
        sample_weights = compute_class_weights(y)
        
        # Assertions
        assert not X.empty
        assert len(y) == len(processed_df)
        assert isinstance(sample_weights, dict)
        assert 0 in sample_weights
        assert 1 in sample_weights
        
        # Check that all expected feature columns are present
        expected_features = ['primary_type', 'domestic', 'district', 'hour']
        for feature in expected_features:
            assert feature in X.columns