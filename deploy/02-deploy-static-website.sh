#!/bin/bash

# Chicago Crimes Serverless Deployment - Static Website Deployment
# This script deploys the static website to S3

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "Deploying static website to S3..."

# Sync static files to S3
aws s3 sync static-web/ s3://$STATIC_BUCKET/ \
    --delete \
    --cache-control "max-age=86400" \
    --region $REGION

# Set specific cache control for HTML files (shorter cache)
aws s3 cp static-web/index.html s3://$STATIC_BUCKET/index.html \
    --cache-control "max-age=300" \
    --content-type "text/html" \
    --region $REGION

echo "Static website deployed successfully to private S3 bucket!"
echo "Files uploaded to: s3://$STATIC_BUCKET/"
echo ""
echo "Note: Website is accessible only via CloudFront distribution"
echo "Update the API_GATEWAY_URL in script.js with your actual API Gateway endpoint"
echo ""
echo "--------------------------------NEXT STEP-----------------------------------"
echo ""
