# Modular Architecture and Production Deployment for Machine Learning Pipelines

## Transitioning from Notebook-Based Development to Production-Ready Code Structure

The evolution from exploratory Jupyter notebooks to a structured, modular codebase represents a critical transition in machine learning project development. While the `explore_data.ipynb` notebook serves excellently for initial data exploration, feature engineering experimentation, and rapid prototyping, production deployment requires a more robust architecture that emphasizes maintainability, testability, and scalability. The modular approach implemented in the `src/` directory structure addresses these production requirements while preserving the insights gained during the exploratory phase.

The decision to create a structured source directory stems from several operational necessities that notebooks cannot adequately address. Code reusability becomes paramount when multiple team members need to access the same data processing functions, feature engineering logic, or model training procedures. Maintainability requires clear separation of concerns where changes to data loading logic do not inadvertently affect model training code. Testability demands that individual functions can be isolated and validated independently, ensuring that modifications to one component do not introduce bugs in others.

## Project Structure Creation and Directory Organization

The initial setup of the modular architecture requires careful directory creation and file organization that follows Python packaging conventions. The command sequence establishes the foundational structure that supports both development and deployment workflows.

```sh
mkdir -p src/chicago_crimes/training tests
```

```sh
touch \
    src/chicago_crimes/__init__.py \
    src/chicago_crimes/config.py \
    src/chicago_crimes/data_loader.py \
    src/chicago_crimes/feature_engineer.py \
    src/chicago_crimes/model_trainer.py \
    src/chicago_crimes/model_evaluator.py \
    src/chicago_crimes/predict.py \
    src/chicago_crimes/training/train_model.py \
    src/chicago_crimes/training/train_validation.py \
    tests/__init__.py \
    tests/test_data_loader.py \
    tests/test_feature_engineer.py
```

The directory structure follows established Python packaging patterns where the `src/` layout isolates the package code from other project files, reducing the likelihood of import conflicts and ensuring clean package distribution. The `chicago_crimes` package name provides a clear namespace that prevents naming collisions with other packages, while the `training/` subdirectory organizes execution scripts separately from core library functions.

## Configuration Management and Centralized Parameters

The `config.py` module serves as the central nervous system for the entire machine learning pipeline, consolidating all configuration parameters, file paths, and model hyperparameters in a single, maintainable location. This centralization eliminates the scattered hardcoded values that typically plague notebook-based development and provides a single source of truth for all pipeline parameters.

```python
import os
from pathlib import Path

# Get the project root directory (where pyproject.toml is located)
PROJECT_ROOT = Path(__file__).parent.parent.parent

# Data paths - now absolute from project root
DATA_DIR = PROJECT_ROOT / 'data'
MODEL_DIR = PROJECT_ROOT / 'models'
TRAIN_DATA_PATH = DATA_DIR / 'train_2022_2023.csv.gz'
VAL_DATA_PATH = DATA_DIR / 'val_2024.csv.gz'
TEST_DATA_PATH = DATA_DIR / 'test_2025.csv.gz'

# Model configuration
MODEL_PARAMS = {
    'objective': 'binary:logistic',
    'eval_metric': 'auc',
    'random_state': 42,
    'n_estimators': 100,
    'learning_rate': 0.1,
    'max_depth': 6,
    'subsample': 0.8,
    'colsample_bytree': 0.8
}
```

The configuration approach uses `pathlib.Path` objects for cross-platform compatibility and relative path resolution that remains valid regardless of the execution context. The `PROJECT_ROOT` calculation ensures that all paths resolve correctly whether the code is executed from the project root, within the package directory, or from test files. The centralized `MODEL_PARAMS` dictionary enables easy hyperparameter tuning and experimentation without modifying multiple files throughout the codebase.

## Data Loading and Processing Abstraction

The `data_loader.py` module encapsulates all data ingestion and preprocessing logic, providing a clean interface that abstracts the complexities of file format handling, column selection, and feature preparation. This abstraction enables consistent data processing across training, validation, and prediction workflows while maintaining flexibility for different data sources and formats.

```python
def create_dataset(data_path, location_mapping):
    """Create complete dataset from raw data path."""
    include_cols = get_feature_columns(data_path)
    df = load_data(data_path, usecols=include_cols)
    df = prepare_features(df, location_mapping)
    df = df.dropna()  # Remove any remaining null values
    return df

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
```

The modular design enables the same feature engineering logic to be applied consistently across training and prediction scenarios, eliminating the code duplication that often occurs when notebook logic is manually replicated for production use. The `load_location_mapping()` function demonstrates proper resource management by automatically locating the JSON mapping file relative to the module location, ensuring that the mapping remains accessible regardless of the execution context.

## Feature Engineering and Model Preparation

The `feature_engineer.py` module isolates the machine learning-specific transformations and preparations, providing clean interfaces for converting between different data representations required by various stages of the pipeline. This separation enables independent testing and modification of feature engineering logic without affecting data loading or model training components.

```python
def create_features_target(df, target_col='arrest'):
    """Split dataframe into features and target."""
    X = df[FEATURE_COLS]
    y = df[target_col].astype('int')
    return X, y

def compute_class_weights(y):
    """Compute class weights for imbalanced dataset."""
    classes = np.unique(y)
    class_weights = compute_class_weight('balanced', classes=classes, y=y)
    sample_weights = {cls: w for cls, w in zip(classes, class_weights)}
    return sample_weights

def convert_to_dict_features(X):
    """Convert DataFrame to dictionary records for DictVectorizer."""
    return X.to_dict(orient='records')
```

The feature engineering module demonstrates the principle of single responsibility by focusing exclusively on data transformation tasks. The `compute_class_weights()` function encapsulates the class imbalance handling logic, making it reusable across different model training scenarios and easily testable in isolation. The dictionary conversion function provides the necessary interface between pandas DataFrames and scikit-learn's `DictVectorizer`, handling the format transformation required for categorical feature encoding.

## Model Training and Pipeline Management

The `model_trainer.py` module manages the machine learning pipeline construction, training execution, and model persistence, providing a clean interface that abstracts the complexities of scikit-learn pipeline management and XGBoost configuration. This abstraction enables consistent model training across different execution contexts while maintaining flexibility for hyperparameter experimentation.

```python
def create_xgb_pipeline(sample_weights, model_params=None):
    """Create XGBoost pipeline with DictVectorizer."""
    if model_params is None:
        model_params = MODEL_PARAMS.copy()
    
    # Add scale_pos_weight for class imbalance
    model_params['scale_pos_weight'] = sample_weights.get(1, 1)
    
    model = xgb.XGBClassifier(**model_params)
    
    pipeline = make_pipeline(
        DictVectorizer(sparse=True, dtype=np.float32),
        model
    )
    
    return pipeline

def save_model(pipeline, model_path=None):
    """Save trained model to disk."""
    if model_path is None:
        model_path = MODEL_DIR / 'xgb_model.pkl'
    
    with open(model_path, 'wb') as f_out:
        pickle.dump(pipeline, f_out)
    
    print(f"Model saved to {model_path}")
```

The pipeline approach ensures that all preprocessing steps (dictionary vectorization) and model training occur in a coordinated manner, preventing the train-test skew that can occur when preprocessing steps are applied inconsistently. The automatic integration of class weights into the XGBoost configuration demonstrates how the modular design enables sophisticated machine learning techniques to be applied consistently without requiring detailed knowledge of the underlying algorithms from calling code.

## Package Configuration and Dependency Management

The `pyproject.toml` file establishes the project as a proper Python package with clearly defined dependencies, build configuration, and executable entry points. This configuration enables the project to be installed in development mode and executed through standardized Python packaging mechanisms.

```toml
[project]
name = "chicago-crimes"
version = "0.1.0"
description = "chicago-crimes-classifier"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.119.0",
    "scikit-learn>=1.7.2",
    "uvicorn>=0.37.0",
    "xgboost>=3.0.5",
]

[tool.hatch.build]
packages = ["src/chicago_crimes"]

[project.scripts]
train-model = "chicago_crimes.training.train_model:main"
```

The package configuration separates production dependencies from development dependencies, ensuring that deployment environments only install the minimal required packages. The `[project.scripts]` section creates a command-line interface that enables model training through a simple `train-model` command, providing a user-friendly interface for pipeline execution.

## Installation and Execution Workflow

The modular architecture requires specific installation and execution procedures that differ from notebook-based development. The editable installation enables development workflow while maintaining proper package structure and import resolution.

```sh
uv pip install -e .
```

```sh
cp scripts/location_description.json src/chicago_crimes/
```

```sh
python -m chicago_crimes.training.train_model
```

The editable installation (`-e` flag) creates a development installation that allows modifications to the source code without requiring reinstallation, facilitating iterative development while maintaining proper package structure. The location mapping file copy ensures that the JSON resource remains accessible to the package code regardless of the execution context.

## Training Script Integration and Execution Flow

The `train_model.py` script demonstrates the integration of all modular components into a cohesive training workflow that can be executed independently or integrated into larger automation systems. The script orchestrates the entire pipeline from data loading through model evaluation and persistence.

```python
def main():
    print("Loading and preparing training data...")
    
    # Load location mapping
    location_mapping = load_location_mapping()
    
    # Create training dataset
    train_df = create_dataset(TRAIN_DATA_PATH, location_mapping)
    
    # Prepare features and target
    X_train, y_train = create_features_target(train_df)
    
    # Compute class weights
    sample_weights = compute_class_weights(y_train)
    
    # Convert to dictionary format
    X_train_dict = convert_to_dict_features(X_train)
    
    # Create and train model
    pipeline = create_xgb_pipeline(sample_weights)
    pipeline = train_model(pipeline, X_train_dict, y_train)
    
    # Save model
    save_model(pipeline)
```

The training script demonstrates how the modular architecture enables clean, readable code that clearly expresses the machine learning workflow. Each function call represents a well-defined step with clear inputs and outputs, making the overall process easy to understand, debug, and modify. The error handling and optional validation evaluation show how the modular design facilitates robust production workflows that can gracefully handle missing data or configuration issues.

## Advantages of Modular Architecture Over Notebook Development

The transition from notebook-based development to modular architecture provides several critical advantages that become increasingly important as projects move toward production deployment. Reusability enables the same data processing and feature engineering logic to be used across training, validation, and prediction workflows without code duplication. Maintainability allows changes to specific components without affecting other parts of the system, reducing the risk of introducing bugs during development iterations.

Testability becomes possible through the isolation of individual functions that can be validated independently, ensuring that modifications to one component do not inadvertently break others. Configuration management centralizes all parameters and paths, eliminating the scattered hardcoded values that make notebook-based systems difficult to maintain and deploy. Reproducibility improves through standardized execution workflows that eliminate the manual cell execution dependencies inherent in notebook environments.

Scalability emerges through the clean interfaces between components that enable easy addition of new features, models, or evaluation metrics without requiring extensive refactoring. The modular approach also facilitates team collaboration by providing clear boundaries between different aspects of the system, enabling multiple developers to work on different components simultaneously without conflicts.