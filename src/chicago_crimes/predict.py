import pandas as pd
from chicago_crimes.model_trainer import load_model
from chicago_crimes.feature_engineer import convert_to_dict_features
from chicago_crimes.data_loader import create_dataset, load_location_mapping
from chicago_crimes.config import MODEL_DIR, DATA_DIR


def predict_new_data(model_path, data_path, location_mapping):
    """Make predictions on new data."""
    # Load model
    pipeline = load_model(model_path)

    # Prepare features (assuming new_data has the same structure as training data)
    prepared_data = create_dataset(data_path, location_mapping)
    # prepared_data = prepare_features(new_data.copy(), location_mapping)

    # Convert to dictionary format
    features_dict = convert_to_dict_features(prepared_data)

    # Make predictions
    preds = pipeline.predict(features_dict)
    probs = pipeline.predict_proba(features_dict)

    return preds, probs


# Example usage
if __name__ == "__main__":
    
    model_path = MODEL_DIR / 'xgb_model.pkl'
    data_path = DATA_DIR / 'test_2025.csv.gz'
    location_mapping = load_location_mapping()

    predictions, probabilities = predict_new_data(model_path, data_path, location_mapping)
    result = pd.DataFrame({
        'prediction': predictions,
        'probability_no_arrest': probabilities[:, 0],
        'probability_arrest': probabilities[:, 1]
    })

    print(result[:2])
