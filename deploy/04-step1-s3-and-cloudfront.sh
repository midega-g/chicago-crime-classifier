#!/bin/bash

# Chicago Crimes Serverless Deployment - Step 1: S3 and CloudFront
# This script creates S3 buckets, uploads files, and sets up CloudFront

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "=========================================="
echo "Step 1: S3 Buckets and CloudFront Setup"
echo "=========================================="

# Step 1: Create S3 buckets
echo "Creating S3 buckets..."
./deploy/01-create-s3-buckets.sh

# Step 2: Upload static files
echo "Uploading static website files..."
./deploy/02-deploy-static-website.sh

# Step 3: Create CloudFront distribution
echo "Creating CloudFront distribution..."
./deploy/03-create-cloudfront.sh

echo ""
echo "=========================================="
echo "Step 1 Complete!"
echo "=========================================="
echo "Resources created:"
echo "- S3 buckets: $STATIC_BUCKET (private), $UPLOAD_BUCKET"
echo "- Static files uploaded to S3"
echo "- CloudFront distribution (deploying...)"
echo ""
echo "Next: Wait 10-15 minutes for CloudFront deployment"