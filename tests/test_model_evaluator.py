# tests/test_model_evaluator.py
import pytest
import numpy as np
from unittest.mock import Mock
from chicago_crimes.model_evaluator import evaluate_model

class TestModelEvaluator:
    
    def test_evaluate_model(self, mock_trained_pipeline, capsys):
        """Test model evaluation function."""
        # Mock predictions - use numpy arrays instead of lists
        mock_proba = np.array([[0.8, 0.2], [0.3, 0.7], [0.9, 0.1]])
        mock_predictions = np.array([0, 1, 0])
        
        # Configure mock pipeline
        mock_trained_pipeline.predict_proba.return_value = mock_proba
        mock_trained_pipeline.predict.return_value = mock_predictions
        
        # Test data
        X_dict = [{'feature1': 'value1'}, {'feature2': 'value2'}, {'feature3': 'value3'}]
        y_true = [0, 1, 0]
        
        # Run evaluation
        metrics = evaluate_model(mock_trained_pipeline, X_dict, y_true, "Test")
        
        # Check returned metrics
        assert 'auc_score' in metrics
        assert 'y_pred_proba' in metrics
        assert 'y_pred' in metrics
        assert 'classification_report' in metrics
        
        # Check that AUC score is calculated
        assert 0 <= metrics['auc_score'] <= 1
        
        # Check output was printed
        captured = capsys.readouterr()
        assert "Test AUC-ROC:" in captured.out
        assert "Classification Report" in captured.out
    
    def test_evaluate_model_with_different_dataset_name(self, mock_trained_pipeline):
        """Test evaluation with different dataset names."""
        mock_proba = np.array([[0.7, 0.3], [0.4, 0.6]])
        mock_predictions = np.array([0, 1])
        
        mock_trained_pipeline.predict_proba.return_value = mock_proba
        mock_trained_pipeline.predict.return_value = mock_predictions
        
        X_dict = [{'feature1': 'value1'}, {'feature2': 'value2'}]
        y_true = [0, 1]
        
        metrics = evaluate_model(mock_trained_pipeline, X_dict, y_true, "Custom Dataset")
        
        assert metrics['auc_score'] is not None