#!/bin/bash

# Chicago Crimes Serverless Deployment - DynamoDB Setup
# This script creates DynamoDB table for storing processing results

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "Step 5: Creating DynamoDB table..."
echo "Creating DynamoDB table for results storage..."

# Check if table exists
if aws dynamodb describe-table --table-name $RESULTS_TABLE --region $REGION > /dev/null 2>&1; then
    echo "✓ DynamoDB table '$RESULTS_TABLE' already exists"
else
    # Create DynamoDB table
    if aws dynamodb create-table \
        --table-name $RESULTS_TABLE \
        --attribute-definitions \
            AttributeName=file_key,AttributeType=S \
        --key-schema \
            AttributeName=file_key,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region $REGION > /dev/null 2>&1; then
        echo "✓ DynamoDB table '$RESULTS_TABLE' created successfully!"
    else
        echo "Error: Failed to create DynamoDB table"
        exit 1
    fi
fi
echo "Table will store processing results with file_key as primary key"
echo ""
echo "--------------------------------NEXT STEP-----------------------------------"
echo ""
