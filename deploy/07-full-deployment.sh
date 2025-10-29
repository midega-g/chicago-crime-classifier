#!/bin/bash

# Chicago Crimes Serverless Deployment - Complete Infrastructure
# This script combines step 2 and complete setup into one deployment

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "==========================================="
echo "Chicago Crimes - Full Infrastructure Setup"
echo "==========================================="

# Step 1: Create S3 buckets
echo "Step 1: Creating S3 buckets..."
./deploy/01-create-s3-buckets.sh

# Step 2: Upload static files
echo "Step 2: Uploading static website files..."
./deploy/02-deploy-static-website.sh

# Step 3: Create CloudFront distribution
echo "Step 3: Creating CloudFront distribution..."
./deploy/03-create-cloudfront.sh

# Step 4: Create API Gateway with proxy integration
echo "Step 4: Creating API Gateway with proxy integration..."
./deploy/04-create-api-gateway.sh

# Step 5: Create DynamoDB table
echo "Step 5: Creating DynamoDB table..."
./deploy/05-create-dynamodb.sh

# Step 6: Deploy ML Lambda function
echo "Step 6: Deploying ML Lambda function..."
./deploy/06-deploy-ml-lambda-docker.sh
echo ""

# Step 7: Update script.js and invalidate cache
echo "Step 7: Updating script.js with API Gateway URL..."

# Small buffer to ensure CloudFront is ready for operations
echo "Waiting for CloudFront to be ready for operations..."
sleep 10

# Get API Gateway and CloudFront URLs
API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text --region $REGION)
CLOUDFRONT_URL=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='$DISTRIBUTION_COMMENT'].DomainName" --output text)

if [ ! -z "$API_ID" ] && [ "$API_ID" != "None" ]; then
    API_URL="https://$API_ID.execute-api.$REGION.amazonaws.com/prod"
    sed -i "s|const API_GATEWAY_URL = '.*';|const API_GATEWAY_URL = '$API_URL';|" static-web/script.js

    # Re-upload updated script.js
    aws s3 cp static-web/script.js s3://$STATIC_BUCKET/script.js \
        --cache-control "max-age=86400" \
        --region $REGION > /dev/null 2>&1

    # Invalidate CloudFront cache
    DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='$DISTRIBUTION_COMMENT'].Id" --output text)
    if [ ! -z "$DISTRIBUTION_ID" ]; then
        aws cloudfront create-invalidation \
            --distribution-id $DISTRIBUTION_ID \
            --paths "/script.js" \
            --query 'Invalidation.Id' \
            --output text > /dev/null 2>&1
    fi
fi

echo ""
echo "==========================================="
echo "🎉 DEPLOYMENT SUCCESSFUL!"
echo "==========================================="
echo ""
echo "Resources created:"
echo "✓ S3 buckets: $STATIC_BUCKET, $UPLOAD_BUCKET"
echo "✓ CloudFront distribution: https://$CLOUDFRONT_URL"
echo "✓ API Gateway: https://$API_ID.execute-api.$REGION.amazonaws.com/prod"
echo "✓ ML Lambda function with SNS notifications"
echo "✓ DynamoDB table: $RESULTS_TABLE"
echo "✓ Script.js updated with API Gateway URL"
echo "✓ CloudFront cache invalidated"
echo ""
echo "🌐 ACCESS YOUR APPLICATION:"
echo "https://$CLOUDFRONT_URL"
echo ""
echo "Your Chicago Crimes ML application is ready!"
echo "Note: CloudFront deployment may take 10-15 minutes to fully propagate."
