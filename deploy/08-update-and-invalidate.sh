#!/bin/bash

# Chicago Crimes Serverless Deployment - Update Static Files and Invalidate Cache
# This script re-uploads static files and invalidates CloudFront cache

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "==========================================="
echo "Updating Static Files and Cache"
echo "==========================================="

# Step 1: Get API Gateway URL and update script.js
echo "Step 1: Getting API Gateway URL..."
API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text --region $REGION)

if [ -z "$API_ID" ]; then
    echo "ERROR: API Gateway not found"
    exit 1
fi

API_URL="https://$API_ID.execute-api.$REGION.amazonaws.com/prod"
echo "API Gateway URL: $API_URL"

# Step 2: Update script.js with correct API Gateway URL
echo "Step 2: Updating script.js with API Gateway URL..."
sed -i "s|const API_GATEWAY_URL = '.*';|const API_GATEWAY_URL = '$API_URL';|" static-web/script.js
echo "Updated script.js with API Gateway URL"

# Step 3: Re-upload static files to S3
echo "Step 3: Re-uploading static files to S3..."
aws s3 sync static-web/ s3://$STATIC_BUCKET/ \
    --delete \
    --cache-control "max-age=86400" > /dev/null 2>&1

echo "Static files uploaded successfully"

# Step 4: Get CloudFront distribution ID and invalidate cache
echo "Step 4: Invalidating CloudFront cache..."
DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='$DISTRIBUTION_COMMENT'].Id" --output text)

if [ ! -z "$DISTRIBUTION_ID" ]; then
    echo "Found CloudFront distribution: $DISTRIBUTION_ID"

    # Create invalidation
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id $DISTRIBUTION_ID \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text)

    echo "Cache invalidation created: $INVALIDATION_ID"
    echo "Waiting for invalidation to complete..."

    # Wait for invalidation to complete (optional)
    aws cloudfront wait invalidation-completed \
        --distribution-id $DISTRIBUTION_ID \
        --id $INVALIDATION_ID > /dev/null 2>&1 || echo "Invalidation in progress..."

    echo "Cache invalidation completed"
else
    echo "CloudFront distribution not found"
    exit 1
fi

echo ""
echo "==========================================="
echo "Update Complete!"
echo "==========================================="
echo "✓ Updated script.js with API Gateway URL"
echo "✓ Re-uploaded static files to S3"
echo "✓ Invalidated CloudFront cache"
echo ""
echo "Your application is now ready to use!"
echo "Access it at: https://$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='$DISTRIBUTION_COMMENT'].DomainName" --output text)"
