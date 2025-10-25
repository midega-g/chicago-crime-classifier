#!/bin/bash

# Chicago Crimes Serverless Deployment - Cleanup Step 1
# This script removes S3 buckets and CloudFront distribution only

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "WARNING: This will delete S3 buckets and CloudFront distribution!"
echo "Resources to be deleted:"
echo "- S3 buckets: $STATIC_BUCKET, $UPLOAD_BUCKET"
echo "- CloudFront distribution"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo "Starting Step 1 cleanup..."

# Delete CloudFront distribution (if exists)
echo "Checking for CloudFront distributions..."
DISTRIBUTIONS=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='$DISTRIBUTION_COMMENT'].Id" --output text)
if [ ! -z "$DISTRIBUTIONS" ]; then
    for DIST_ID in $DISTRIBUTIONS; do
        echo "Disabling CloudFront distribution: $DIST_ID"
        aws cloudfront get-distribution-config --id $DIST_ID > dist-config.json
        ETAG=$(jq -r '.ETag' dist-config.json)
        jq '.DistributionConfig.Enabled = false | .DistributionConfig' dist-config.json > dist-config-disabled.json
        aws cloudfront update-distribution --id $DIST_ID --distribution-config file://dist-config-disabled.json --if-match $ETAG
        echo "Waiting for distribution to be disabled..."
        timeout 900 aws cloudfront wait distribution-deployed --id $DIST_ID || echo "Timeout waiting for distribution deployment"
        
        # Get fresh ETag after deployment
        echo "Getting fresh ETag for deletion..."
        FRESH_CONFIG=$(aws cloudfront get-distribution --id $DIST_ID)
        FRESH_ETAG=$(echo $FRESH_CONFIG | jq -r '.ETag')
        
        echo "Deleting CloudFront distribution: $DIST_ID"
        aws cloudfront delete-distribution --id $DIST_ID --if-match $FRESH_ETAG
        echo "Distribution deletion initiated. Waiting for cleanup to complete..."
        sleep 30  # Wait for AWS to process the deletion
        rm -f dist-config.json dist-config-disabled.json
    done
    
    # Wait a bit more for all distributions to be fully deleted
    echo "Waiting for CloudFront cleanup to complete..."
    sleep 60
fi

# Delete ALL Origin Access Controls with "chicago-crimes-oac" in the name
echo "Checking for Origin Access Controls..."
OAC_IDS=$(aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?contains(Name, 'chicago-crimes-oac')].Id" --output text)

if [ ! -z "$OAC_IDS" ]; then
    echo "Found OAC IDs to delete: $OAC_IDS"
    
    for OAC_ID in $OAC_IDS; do
        echo "Attempting to delete Origin Access Control: $OAC_ID"
        
        # Get OAC details with ETag for deletion
        echo "Getting OAC details for deletion..."
        OAC_CONFIG=$(aws cloudfront get-origin-access-control --id $OAC_ID 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            OAC_ETAG=$(echo $OAC_CONFIG | jq -r '.ETag')
            echo "Deleting OAC $OAC_ID with ETag $OAC_ETAG"
            
            if aws cloudfront delete-origin-access-control --id $OAC_ID --if-match $OAC_ETAG 2>/dev/null; then
                echo "Origin Access Control $OAC_ID deleted successfully"
            else
                echo "Failed to delete OAC $OAC_ID - it may still be in use by another distribution"
            fi
        else
            echo "Could not get details for OAC $OAC_ID - it may already be deleted"
        fi
    done
else
    echo "No Origin Access Controls found with 'chicago-crimes-oac' in the name."
fi

# Empty and delete S3 buckets
echo "Emptying and deleting S3 buckets..."
aws s3 rm s3://$STATIC_BUCKET --recursive 2>/dev/null || echo "Static bucket not found or already empty"
aws s3 rb s3://$STATIC_BUCKET 2>/dev/null || echo "Static bucket not found"

aws s3 rm s3://$UPLOAD_BUCKET --recursive 2>/dev/null || echo "Upload bucket not found or already empty"
aws s3 rb s3://$UPLOAD_BUCKET 2>/dev/null || echo "Upload bucket not found"

echo ""
echo "Step 1 cleanup completed!"
echo "S3 buckets and CloudFront distribution have been removed."