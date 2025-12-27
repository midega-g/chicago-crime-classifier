# Lambda Configuration Settings
# This file contains hardcoded values that can be easily modified without code changes

# AWS Configuration
DEFAULT_REGION = "af-south-1"

# S3 Configuration
S3_CONFIG = {
    "addressing_style": "virtual",
    "use_accelerate_endpoint": False,
    "use_dualstack_endpoint": False,
}

# Default Environment Values (fallbacks when env vars not set)
DEFAULT_UPLOAD_BUCKET = "chicago-crimes-uploads"
DEFAULT_RESULTS_TABLE = "chicago-crimes-results"

# Admin Configuration
ADMIN_EMAIL = "midegageorge2@gmail.com"

# Model Configuration
LAMBDA_MODEL_PATH = "/var/task/models/xgb_model.pkl"

# Prediction Thresholds
RISK_THRESHOLDS = {"HIGH": 0.7, "MEDIUM": 0.3}

# API Configuration
CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
    "Access-Control-Allow-Headers": (
        "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token"
    ),
    "Access-Control-Max-Age": "86400",
}

# File Processing Configuration
SUPPORTED_COMPRESSIONS = [".csv.gz"]
SUPPORTED_FORMATS = [".csv"]

# API Paths
API_PATHS = {
    "UPLOAD_URL": "/get-upload-url",
    "RESULTS": "/get-results/",
    "PREDICT": "/predict",
    "HEALTH": "/health",
}

# Error Messages
ERROR_MESSAGES = {
    "CORRUPTED_GZIP": (
        "Corrupted gzip file: {}. Please re-compress the file and upload again."
    ),
    "DECOMPRESS_FAILED": "Failed to decompress gzip file: {}",
    "FILE_PROCESSING_FAILED": "File processing failed: {}",
    "INVALID_EVENT": "Invalid event type",
    "NOT_FOUND": "Not found",
}
