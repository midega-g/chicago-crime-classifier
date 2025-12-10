# Chicago Crime Arrest Prediction System

A comprehensive machine learning system for predicting arrest likelihood in Chicago crime incidents, built with modern MLOps practices and deployed as a scalable web service.

## Project Overview

This project implements an end-to-end machine learning pipeline that predicts the probability of arrest for reported crime incidents in Chicago. The system transforms raw crime data into actionable insights for law enforcement resource allocation and operational efficiency. Built incrementally through a structured development approach, the project demonstrates best practices in data science, software engineering, and cloud deployment.

**🎯 Business Context**: [Detailed Business Problem & Requirements](notes/00_business_problem_and_requirements.md)

## Quick Start

### Prerequisites

- Python 3.12+
- UV package manager
- Docker (for Lambda containerization)
- AWS CLI configured with appropriate credentials
- jq (for JSON processing in deployment scripts)

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

### Serverless Deployment

```sh
# 1. Configure environment variables
cp .env.example .env
# Edit .env with your AWS_ACCOUNT_ID and ADMIN_EMAIL

# 2. Run full deployment
cd deploy
./07-full-deployment.sh

# 3. Access your application
# The deployment script will output your CloudFront URL

# 4. View logs (optional)
./10-cloud-watch-logs.sh 5  # Last 5 minutes

# 5. Cleanup resources when done
./09-cleanup-all.sh
```

## Architecture Overview

The system implements a fully serverless architecture on AWS:

1. **Static Website**: Hosted on S3, delivered globally via CloudFront
2. **File Upload**: Direct S3 upload using presigned URLs
3. **Processing**: Lambda function triggered by S3 events
4. **API**: API Gateway provides RESTful endpoints for the frontend
5. **Storage**: DynamoDB stores processing results
6. **Notifications**: SES sends email notifications on completion

This architecture provides automatic scaling, high availability, and cost efficiency through pay-per-use pricing.

## Project Architecture

### Core Components

The system follows a modular serverless architecture:

```txt
src/
├── chicago_crimes/           # Core ML package
│   ├── training/            # Model training modules
│   ├── config.py           # Configuration management
│   ├── data_loader.py      # Data ingestion and processing
│   ├── feature_engineer.py # Feature transformation pipeline
│   ├── model_trainer.py    # Training orchestration
│   └── model_evaluator.py  # Performance assessment
deploy/                      # Deployment automation scripts
├── 00-config.sh            # Centralized configuration
├── 01-create-s3-buckets.sh # S3 bucket setup
├── 02-deploy-static-website.sh
├── 03-create-cloudfront.sh
├── 04-create-api-gateway.sh
├── 05-create-dynamodb.sh
├── 06-deploy-ml-lambda-docker.sh
├── 07-full-deployment.sh   # Complete deployment
├── 08-update-and-invalidate.sh
└── 09-cleanup-all.sh       # Resource cleanup
lambda/                      # Lambda function code
├── ml-predictor.py         # Lambda handler
├── config.py               # Lambda configuration
└── Dockerfile              # Container definition
static-web/                  # Static website assets
├── index.html
├── script.js
└── style.css
```

### Data Pipeline

The data processing pipeline transforms raw Chicago crime data through several stages:

1. **Data Extraction**: Automated retrieval from Chicago Open Data Portal
2. **Feature Engineering**: Temporal, categorical, and geographic feature creation
3. **Model Training**: XGBoost classifier with hyperparameter optimization
4. **Evaluation**: Comprehensive performance metrics and validation
5. **Deployment**: Serverless architecture with S3, Lambda, API Gateway, and CloudFront

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

### Phase 5: Serverless Deployment & Operations

- **[Serverless Architecture](notes/10_serverless_s3_cloudfront_architecture_setup.md)**: Transition to serverless architecture with S3, CloudFront, and Lambda
- **[S3 and Static Deployment](notes/11_s3_bucket_creation_and_static_deployment_scripts.md)**: S3 bucket configuration and static website deployment
- **[CloudFront Distribution](notes/12_cloudfront_distribution_and_origin_access_control.md)**: Global content delivery with Origin Access Control
- **[Deployment Operations](notes/13_deployment_execution_and_cleanup_operations.md)**: Automated deployment and cleanup procedures
- **[Configuration Management](notes/14_centralized_configuration_and_secrets_management.md)**: Centralized configuration with secrets protection

## Key Technical Decisions

### Machine Learning Approach

**XGBoost Classifier** was selected for its superior performance on tabular data, built-in handling of missing values, and excellent interpretability through feature importance scores. The model achieves an AUC-ROC of 0.87+ on validation data, demonstrating strong predictive capability for arrest likelihood.

### Feature Engineering Strategy

The system transforms high-cardinality raw features into meaningful predictors through strategic grouping and temporal extraction. Location descriptions are mapped to 15 semantic categories, while temporal features capture daily, weekly, and seasonal patterns that influence arrest probability.

### Deployment Architecture

**Serverless Architecture** provides optimal scalability and cost efficiency through AWS managed services. The system uses S3 for static hosting, CloudFront for global content delivery, Lambda for serverless compute, API Gateway for RESTful endpoints, and DynamoDB for data persistence. This architecture eliminates server management overhead while providing automatic scaling, high availability, and pay-per-use pricing.

### Technology Stack

- **ML Framework**: XGBoost with scikit-learn pipeline integration
- **Frontend**: Vanilla HTML/CSS/JavaScript for lightweight, responsive interface
- **Compute**: AWS Lambda with Docker container runtime
- **Storage**: S3 for static assets and file uploads, DynamoDB for results
- **CDN**: CloudFront with Origin Access Control for secure content delivery
- **API**: API Gateway with Lambda proxy integration
- **Notifications**: SES for email notifications

## Model Performance

The trained model demonstrates strong predictive performance across multiple metrics:

- **AUC-ROC**: 0.87+ (excellent discrimination capability)
- **Precision**: Optimized for high-confidence predictions
- **Recall**: Balanced to capture majority of arrest cases
- **F1-Score**: Harmonized precision-recall balance

Performance is validated through temporal cross-validation to ensure the model generalizes to future incidents without data leakage.

## Data Sources & Compliance

The system utilizes the **Chicago Crimes - 2001 to Present** dataset from the City of Chicago Open Data Portal. All data usage complies with the city's open data terms, with appropriate disclaimers regarding data accuracy, timeliness, and privacy protections. The system implements block-level geographic aggregation to protect individual privacy while maintaining analytical utility.

## Configuration Management

The system uses centralized configuration with secure secrets management:

```sh
# Sensitive credentials in .env (not version controlled)
AWS_ACCOUNT_ID=your_account_id
ADMIN_EMAIL=your_email@example.com

# Public configuration in deploy/00-config.sh
REGION="af-south-1"
STATIC_BUCKET="chicago-crimes-static-web"
UPLOAD_BUCKET="chicago-crimes-uploads"
FUNCTION_NAME="chicago-crimes-predictor"
```

Configuration is managed through `deploy/00-config.sh` which loads sensitive values from `.env`, ensuring credentials remain private while maintaining deployment automation. See [Configuration Management](notes/14_centralized_configuration_and_secrets_management.md) for details.

## Monitoring & Observability

The serverless system includes comprehensive logging and monitoring:

- **CloudWatch Logs**: Lambda execution logs with custom log monitoring script
- **CloudWatch Metrics**: Automatic metrics for Lambda, API Gateway, and S3
- **Email Notifications**: SES-based notifications for processing completion
- **Health Endpoints**: API Gateway health check endpoints for monitoring

```sh
# View Lambda logs
./deploy/10-cloud-watch-logs.sh 5  # Last 5 minutes
```

## Contributing

The project follows standard software development practices:

1. **Code Style**: Black formatting with flake8 linting
2. **Testing**: Pytest with coverage requirements
3. **Documentation**: Comprehensive inline documentation and README updates
4. **Version Control**: Git with feature branch workflow

## Security Considerations

The system implements several security measures:

- **Origin Access Control**: CloudFront OAC for secure S3 access
- **Presigned URLs**: Time-limited S3 upload URLs
- **IAM Least Privilege**: Role-based access with minimal permissions
- **Secrets Management**: Environment-based credential protection
- **HTTPS Enforcement**: CloudFront redirect-to-https policy
- **Input Validation**: Comprehensive data validation for all API endpoints
- **File Upload Security**: Restricted file types and size limits

## Future Enhancements

Planned improvements include:

- **Real-time Streaming**: Kinesis integration for real-time crime data processing
- **Multi-region Deployment**: Cross-region replication for high availability
- **API Authentication**: Cognito or API key-based authentication
- **WAF Integration**: Web Application Firewall for enhanced security
- **Advanced Analytics**: SHAP-based model interpretability and bias detection
- **Mobile Interface**: Responsive design optimization for mobile devices
- **Cost Optimization**: Reserved capacity and savings plans analysis
- **Model Retraining**: Automated model updates with new data

## License & Disclaimer

This project is developed for educational and research purposes. The predictive model should not be used as the sole basis for law enforcement decisions. All predictions should be validated through proper investigative procedures and human judgment.

---

**📚 Complete Documentation**: Explore the [notes/](notes/) directory for detailed technical documentation covering each phase of development.

**🚀 Quick Deploy**: Run `./deploy/07-full-deployment.sh` to deploy the complete serverless infrastructure, or follow the detailed deployment guides in the documentation.

**🧹 Cleanup**: Run `./deploy/09-cleanup-all.sh` to remove all AWS resources when no longer needed.

**🔧 Development**: The modular architecture supports easy extension and customization for different use cases and datasets.
