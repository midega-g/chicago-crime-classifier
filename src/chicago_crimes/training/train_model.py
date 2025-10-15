from chicago_crimes.data_loader import create_dataset, load_location_mapping
from chicago_crimes.feature_engineer import create_features_target, compute_class_weights, convert_to_dict_features, get_feature_statistics
from chicago_crimes.model_trainer import create_xgb_pipeline, train_model, save_model
from chicago_crimes.model_evaluator import evaluate_model
from chicago_crimes.config import TRAIN_DATA_PATH, VAL_DATA_PATH

def main():
    print("Loading and preparing training data...")
    
    # Load location mapping
    location_mapping = load_location_mapping()
    
    # Create training dataset
    train_df = create_dataset(TRAIN_DATA_PATH, location_mapping)
    
    print("Training data shape:", train_df.shape)
    
    # # uncomment for debugging purposes
    # print("\nFeature statistics:")
    # get_feature_statistics(train_df)
    
    # Prepare features and target
    X_train, y_train = create_features_target(train_df)
    
    # Compute class weights
    sample_weights = compute_class_weights(y_train)
    print(f"\nClass weights: {sample_weights}")
    
    # Convert to dictionary format
    X_train_dict = convert_to_dict_features(X_train)
    
    # Create and train model
    print("\nTraining model...")
    pipeline = create_xgb_pipeline(sample_weights)
    pipeline = train_model(pipeline, X_train_dict, y_train)
    
    # Evaluate on training data
    print("\nEvaluating on training data...")
    train_metrics = evaluate_model(pipeline, X_train_dict, y_train, "Training")
    
    # Save model
    save_model(pipeline)
    print("\nModel training completed!")
    
    # Optional: Evaluate on validation data
    try:
        print("\nLoading and evaluating on validation data...")
        val_df = create_dataset(VAL_DATA_PATH, location_mapping)
        X_val, y_val = create_features_target(val_df)
        X_val_dict = convert_to_dict_features(X_val)
        
        val_metrics = evaluate_model(pipeline, X_val_dict, y_val, "Validation")
    except FileNotFoundError:
        print("Validation data not found, skipping validation evaluation.")

if __name__ == "__main__":
    main()