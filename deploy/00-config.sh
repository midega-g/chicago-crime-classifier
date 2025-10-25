#!/bin/bash

# Chicago Crimes Serverless Deployment - Configuration
# Centralized configuration for all deployment scripts

# AWS Configuration
export REGION="af-south-1"
export ACCOUNT_ID="076181803615"

# S3 Configuration
export STATIC_BUCKET="chicago-crimes-static-web"
export UPLOAD_BUCKET="chicago-crimes-uploads"

# Lambda Configuration
export FUNCTION_NAME="chicago-crimes-predictor"
export ECR_REPO="chicago-crimes-lambda"
export ROLE_NAME="lambda-execution-role"

# DynamoDB Configuration
export RESULTS_TABLE="chicago-crimes-results"

# API Gateway Configuration
export API_NAME="chicago-crimes-api"

# CloudFront Configuration
export DISTRIBUTION_COMMENT="Chicago Crimes Prediction App"