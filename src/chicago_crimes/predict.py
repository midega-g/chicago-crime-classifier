from chicago_crimes.model_trainer import load_model
from chicago_crimes.feature_engineer import convert_to_dict_features
from chicago_crimes.data_loader import prepare_features, load_location_mapping


def predict_new_data(model_path, new_data, location_mapping):
    """Make predictions on new data."""
    # Load model
    pipeline = load_model(model_path)

    # Prepare features (assuming new_data has the same structure as training data)
    prepared_data = prepare_features(new_data.copy(), location_mapping)

    # Convert to dictionary format
    features_dict = convert_to_dict_features(prepared_data)

    # Make predictions
    predictions = pipeline.predict(features_dict)
    probabilities = pipeline.predict_proba(features_dict)

    return predictions, probabilities


# Example usage
if __name__ == "__main__":
    # This would be used for making predictions on new incoming data
    location_mapping = load_location_mapping()

    # Example: Load new data (you would replace this with your actual new data)
    # new_df = pd.read_csv('path_to_new_data.csv')
    # predictions, probabilities = predict_new_data(None, new_df, location_mapping)

    print("Prediction module ready for use.")
