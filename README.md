# Chicago Crime Arrest Prediction System

A comprehensive machine learning system for predicting arrest likelihood in Chicago crime incidents, built with modern MLOps practices and deployed as a scalable web service.

## Project Overview

This project implements an end-to-end machine learning pipeline that predicts the probability of arrest for reported crime incidents in Chicago. The system transforms raw crime data into actionable insights for law enforcement resource allocation and operational efficiency. Built incrementally through a structured development approach, the project demonstrates best practices in data science, software engineering, and cloud deployment.

**🎯 Business Context**: [Detailed Business Problem & Requirements](notes/00_business_problem_and_requirements.md)

## Quick Start

### Prerequisites

- Python 3.12+
- UV package manager
- Docker (for containerization)
- AWS CLI (for cloud deployment)

### Installation & Setup

```sh
# Clone and navigate to project
git clone <repository-url>
cd chicago-crimes

# Install dependencies using UV
uv sync

# Activate virtual environment
source .venv/bin/activate  # Linux/Mac
# or
.venv\Scripts\activate     # Windows

# Set up environment variables
cp .env.example .env
# Edit .env with your configuration
```

### Running the Application

**Local Development:**

```sh
# Start the web interface
python run_api.py

# Or use uvicorn directly
uvicorn src.predict-api:app --host 0.0.0.0 --port 8000 --reload
```

**Docker Deployment:**

```sh
# Build and run container
docker build -t chicago-crimes .
docker run -p 8000:8000 chicago-crimes
```

**AWS Elastic Beanstalk:**

```sh
# Initialize and deploy
eb init -p docker crime-arrest-classifier -r <your-region>
eb create crime-arrest-classifier-env
```

## Project Architecture

### Core Components

The system follows a modular architecture designed for maintainability, testability, and scalability:

```txt
src/
├── chicago_crimes/           # Core ML package
│   ├── training/            # Model training modules
│   ├── config.py           # Configuration management
│   ├── data_loader.py      # Data ingestion and processing
│   ├── feature_engineer.py # Feature transformation pipeline
│   ├── model_trainer.py    # Training orchestration
│   └── model_evaluator.py  # Performance assessment
├── web/                    # Web interface components
│   ├── templates/          # HTML templates
│   └── static/            # CSS/JS assets
└── predict-api.py         # FastAPI application
```

### Data Pipeline

The data processing pipeline transforms raw Chicago crime data through several stages:

1. **Data Extraction**: Automated retrieval from Chicago Open Data Portal
2. **Feature Engineering**: Temporal, categorical, and geographic feature creation
3. **Model Training**: XGBoost classifier with hyperparameter optimization
4. **Evaluation**: Comprehensive performance metrics and validation
5. **Deployment**: Containerized web service with prediction API

## Development Journey

This project was built incrementally through a structured approach, with each phase building upon previous work:

### Phase 1: Data Foundation

- **[Data Pipeline Setup](notes/01_predictive_policing_data_pipeline_notes.md)**: Established robust data ingestion from Chicago Open Data Portal using SODA API
- **[Exploratory Analysis](notes/02_exploratory_data_analysis_notes.md)**: Comprehensive data exploration, quality assessment, and feature selection strategy

### Phase 2: Machine Learning Core

- **[Model Development](notes/03_machine_learning_model_training_notes.md)**: XGBoost classifier implementation with feature engineering and hyperparameter tuning
- **[Production Architecture](notes/04_modular_architecture_and_production_deployment_notes.md)**: Modular code structure with separation of concerns and configuration management

### Phase 3: Quality Assurance

- **[Testing Framework](notes/05_testing_framework_and_quality_assurance_notes.md)**: Comprehensive test suite covering unit, integration, and model validation tests

### Phase 4: Web Services

- **[API Development](notes/06_web_service_deployment_of_model.md)**: FastAPI-based prediction service with JSON endpoints
- **[Web Interface](notes/07_web_interface_and_api_integration_notes.md)**: User-friendly web application for file upload and batch predictions

### Phase 5: Deployment & Operations

- **[Containerization](notes/08_containerization_and_docker_deployment_notes.md)**: Docker-based deployment with multi-stage builds and optimization
- **[Cloud Deployment](notes/09_aws_elastic_beanstalk_deployment_notes.md)**: AWS Elastic Beanstalk deployment with auto-scaling and load balancing

## Key Technical Decisions

### Machine Learning Approach

**XGBoost Classifier** was selected for its superior performance on tabular data, built-in handling of missing values, and excellent interpretability through feature importance scores. The model achieves an AUC-ROC of 0.87+ on validation data, demonstrating strong predictive capability for arrest likelihood.

### Feature Engineering Strategy

The system transforms high-cardinality raw features into meaningful predictors through strategic grouping and temporal extraction. Location descriptions are mapped to 15 semantic categories, while temporal features capture daily, weekly, and seasonal patterns that influence arrest probability.

### Deployment Architecture

**AWS Elastic Beanstalk** provides the optimal balance of simplicity and scalability, offering managed infrastructure with automatic scaling, health monitoring, and easy deployment workflows. The containerized approach ensures consistency across development and production environments.

### Technology Stack

- **Backend**: FastAPI for high-performance API development
- **ML Framework**: XGBoost with scikit-learn pipeline integration
- **Frontend**: Vanilla HTML/CSS/JavaScript for lightweight, responsive interface
- **Containerization**: Docker with multi-stage builds for optimized images
- **Cloud Platform**: AWS Elastic Beanstalk for managed deployment

## Model Performance

The trained model demonstrates strong predictive performance across multiple metrics:

- **AUC-ROC**: 0.87+ (excellent discrimination capability)
- **Precision**: Optimized for high-confidence predictions
- **Recall**: Balanced to capture majority of arrest cases
- **F1-Score**: Harmonized precision-recall balance

Performance is validated through temporal cross-validation to ensure the model generalizes to future incidents without data leakage.

## Data Sources & Compliance

The system utilizes the **Chicago Crimes - 2001 to Present** dataset from the City of Chicago Open Data Portal. All data usage complies with the city's open data terms, with appropriate disclaimers regarding data accuracy, timeliness, and privacy protections. The system implements block-level geographic aggregation to protect individual privacy while maintaining analytical utility.

## Testing & Quality Assurance

Comprehensive testing ensures system reliability and model performance:

```sh
# Run full test suite
pytest tests/ -v --cov=src

# Run specific test categories
pytest tests/test_model_trainer.py    # Model training tests
pytest tests/test_integration.py      # End-to-end integration tests
pytest tests/test_data_loader.py      # Data pipeline tests
```

The testing framework covers unit tests for individual components, integration tests for end-to-end workflows, and model validation tests for performance regression detection.

## Configuration Management

The system uses environment-based configuration for flexible deployment across different environments:

```python
# Configuration through environment variables
DATABASE_URL=sqlite:///chicago_crimes.db
MODEL_PATH=models/xgb_model.pkl
API_HOST=0.0.0.0
API_PORT=8000
```

Configuration is managed through the `config.py` module, providing centralized settings management with environment-specific overrides.

## Monitoring & Observability

The deployed system includes comprehensive logging and monitoring capabilities:

- **Application Logs**: Structured logging for request tracking and error diagnosis
- **Performance Metrics**: Response time and throughput monitoring
- **Model Metrics**: Prediction distribution and confidence tracking
- **Health Checks**: Automated system health monitoring

## Contributing

The project follows standard software development practices:

1. **Code Style**: Black formatting with flake8 linting
2. **Testing**: Pytest with coverage requirements
3. **Documentation**: Comprehensive inline documentation and README updates
4. **Version Control**: Git with feature branch workflow

## Security Considerations

The system implements several security measures:

- **Input Validation**: Comprehensive data validation for all API endpoints
- **File Upload Security**: Restricted file types and size limits
- **Environment Isolation**: Containerized deployment with minimal attack surface
- **Access Control**: Configurable authentication and authorization (when deployed)

## Future Enhancements

Planned improvements include:

- **Real-time Data Integration**: Live data feeds from Chicago Open Data Portal
- **Advanced Analytics**: SHAP-based model interpretability and bias detection
- **Mobile Interface**: Responsive design optimization for mobile devices
- **API Authentication**: JWT-based authentication for production deployments
- **Model Retraining**: Automated model updates with new data

## License & Disclaimer

This project is developed for educational and research purposes. The predictive model should not be used as the sole basis for law enforcement decisions. All predictions should be validated through proper investigative procedures and human judgment.

---

**📚 Complete Documentation**: Explore the [notes/](notes/) directory for detailed technical documentation covering each phase of development.

**🚀 Quick Deploy**: Use the commands above to get started immediately, or follow the detailed deployment guides in the documentation.

**🔧 Development**: The modular architecture supports easy extension and customization for different use cases and datasets.
