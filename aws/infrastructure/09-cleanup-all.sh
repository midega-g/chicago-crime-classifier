#!/bin/bash

# Chicago Crimes Serverless Deployment - Complete Cleanup
# This script removes all AWS resources created by the deployment

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "==========================================="
echo "Chicago Crimes - Complete Cleanup"
echo "==========================================="
echo "This will delete ALL resources. Are you sure?"
read -p "Type 'DELETE' to confirm: " confirm

if [ "$confirm" != "DELETE" ]; then
    echo "Cleanup cancelled"
    exit 0
fi
echo ""

# Step 1: Delete Lambda functions (SES resources are account-level, not project-specific)
echo "Step 1: Deleting Lambda functions..."
aws lambda delete-function --function-name $FUNCTION_NAME --region $REGION > /dev/null 2>&1 || echo "Function not found"

# Note: SES verified emails and configuration remain at account level
# No project-specific SES resources to clean up
echo ""

# Step 2: Delete API Gateway
echo "Step 2: Deleting API Gateway..."
API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text --region $REGION)
if [ ! -z "$API_ID" ]; then
    aws apigateway delete-rest-api --rest-api-id $API_ID --region $REGION > /dev/null 2>&1
    echo "API Gateway deleted"
else
    echo "API Gateway not found"
fi
echo ""

# Step 3: Delete DynamoDB table
echo "Step 3: Deleting DynamoDB table..."
aws dynamodb delete-table --table-name $RESULTS_TABLE --region $REGION > /dev/null 2>&1 || echo "Table not found"
echo ""

# Step 4: Delete CloudFront distribution with proper waiting
echo "Step 4: Deleting CloudFront distribution..."
DISTRIBUTIONS=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='$DISTRIBUTION_COMMENT'].Id" --output text 2>/dev/null || echo "")

if [ ! -z "$DISTRIBUTIONS" ] && [ "$DISTRIBUTIONS" != "None" ] && [ "$DISTRIBUTIONS" != "null" ]; then
    for DIST_ID in $DISTRIBUTIONS; do
        # Skip if DIST_ID is None, null, or empty
        if [ "$DIST_ID" = "None" ] || [ "$DIST_ID" = "null" ] || [ -z "$DIST_ID" ]; then
            continue
        fi

        echo "Disabling CloudFront distribution: $DIST_ID"
        if aws cloudfront get-distribution-config --id $DIST_ID > dist-config.json 2>/dev/null; then
            ETAG=$(jq -r '.ETag' dist-config.json 2>/dev/null || echo "")
            if [ ! -z "$ETAG" ] && [ "$ETAG" != "null" ]; then
                jq '.DistributionConfig.Enabled = false | .DistributionConfig' dist-config.json > dist-config-disabled.json 2>/dev/null
                aws cloudfront update-distribution --id $DIST_ID --distribution-config file://dist-config-disabled.json --if-match $ETAG > /dev/null 2>&1
                echo "Waiting for distribution to be disabled..."
                timeout 900 aws cloudfront wait distribution-deployed --id $DIST_ID > /dev/null 2>&1 || echo "Timeout waiting for distribution deployment"

                # Get fresh ETag after deployment
                echo "Getting fresh ETag for deletion..."
                FRESH_CONFIG=$(aws cloudfront get-distribution --id $DIST_ID 2>/dev/null)
                FRESH_ETAG=$(echo $FRESH_CONFIG | jq -r '.ETag' 2>/dev/null || echo "")

                if [ ! -z "$FRESH_ETAG" ] && [ "$FRESH_ETAG" != "null" ]; then
                    echo "Deleting CloudFront distribution: $DIST_ID"
                    aws cloudfront delete-distribution --id $DIST_ID --if-match $FRESH_ETAG > /dev/null 2>&1
                    echo "Distribution deletion initiated. Waiting for cleanup to complete..."
                    sleep 30
                fi
            fi
        fi
        rm -f dist-config.json dist-config-disabled.json
    done

    echo "Waiting for CloudFront cleanup to complete..."
    sleep 60
else
    echo "CloudFront distribution not found"
fi
echo ""

# Step 5: Delete Origin Access Controls
echo "Step 5: Deleting Origin Access Controls..."
OAC_IDS=$(aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?contains(Name, 'chicago-crimes-oac')].Id" --output text 2>/dev/null || echo "")

if [ ! -z "$OAC_IDS" ] && [ "$OAC_IDS" != "None" ] && [ "$OAC_IDS" != "null" ]; then
    for OAC_ID in $OAC_IDS; do
        # Skip if OAC_ID is None, null, or empty
        if [ "$OAC_ID" = "None" ] || [ "$OAC_ID" = "null" ] || [ -z "$OAC_ID" ]; then
            continue
        fi

        echo "Deleting Origin Access Control: $OAC_ID"
        OAC_CONFIG=$(aws cloudfront get-origin-access-control --id $OAC_ID 2>/dev/null)
        if [ $? -eq 0 ]; then
            OAC_ETAG=$(echo $OAC_CONFIG | jq -r '.ETag' 2>/dev/null || echo "")
            if [ ! -z "$OAC_ETAG" ] && [ "$OAC_ETAG" != "null" ]; then
                aws cloudfront delete-origin-access-control --id $OAC_ID --if-match $OAC_ETAG > /dev/null 2>&1 || echo "Failed to delete OAC $OAC_ID"
            fi
        fi
    done
else
    echo "No Origin Access Controls found"
fi
echo ""

# Step 6: Empty and delete S3 buckets
echo "Step 6: Emptying and deleting S3 buckets..."

# Function to completely empty a bucket (including versions)
empty_bucket() {
    local bucket=$1
    echo "Removing all objects and versions from: $bucket"

    # Delete all object versions and delete markers
    aws s3api list-object-versions --bucket $bucket --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | while read key version; do
        if [ ! -z "$key" ] && [ "$key" != "None" ]; then
            aws s3api delete-object --bucket $bucket --key "$key" --version-id "$version" > /dev/null 2>&1
        fi
    done

    # Delete all delete markers
    aws s3api list-object-versions --bucket $bucket --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | while read key version; do
        if [ ! -z "$key" ] && [ "$key" != "None" ]; then
            aws s3api delete-object --bucket $bucket --key "$key" --version-id "$version" > /dev/null 2>&1
        fi
    done

    # Remove remaining objects (fallback)
    aws s3 rm s3://$bucket --recursive > /dev/null 2>&1 || true
}

# Check and delete static bucket
if aws s3 ls s3://$STATIC_BUCKET > /dev/null 2>&1; then
    empty_bucket $STATIC_BUCKET
    echo "Deleting static bucket: $STATIC_BUCKET"
    aws s3 rb s3://$STATIC_BUCKET
    echo "✓ Static bucket deleted"
else
    echo "Static bucket not found: $STATIC_BUCKET"
fi

# Check and delete upload bucket
if aws s3 ls s3://$UPLOAD_BUCKET > /dev/null 2>&1; then
    empty_bucket $UPLOAD_BUCKET
    echo "Deleting upload bucket: $UPLOAD_BUCKET"
    aws s3 rb s3://$UPLOAD_BUCKET
    echo "✓ Upload bucket deleted"
else
    echo "Upload bucket not found: $UPLOAD_BUCKET"
fi
echo ""

# Step 7: Delete ECR repository
echo "Step 7: Deleting ECR repository..."
aws ecr delete-repository --repository-name $ECR_REPO --region $REGION --force > /dev/null 2>&1 || echo "ECR repository not found"
echo ""

# Step 8: Delete ALL IAM roles and policies
echo "Step 8: Deleting IAM roles and policies..."

# Delete api-gateway-s3-role
aws iam delete-role-policy --role-name api-gateway-s3-role --policy-name S3AccessPolicy > /dev/null 2>&1 || echo "S3AccessPolicy not found"
aws iam delete-role --role-name api-gateway-s3-role > /dev/null 2>&1 || echo "api-gateway-s3-role not found"

# Delete chicago-crimes-lambda-role
aws iam delete-role-policy --role-name chicago-crimes-lambda-role --policy-name ChicagoCrimesLambdaPolicy > /dev/null 2>&1 || echo "ChicagoCrimesLambdaPolicy not found"
aws iam detach-role-policy --role-name chicago-crimes-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole > /dev/null 2>&1 || echo "AWSLambdaBasicExecutionRole not attached"
aws iam delete-role --role-name chicago-crimes-lambda-role > /dev/null 2>&1 || echo "chicago-crimes-lambda-role not found"

echo ""
echo "==========================================="
echo "Cleanup Complete!"
echo "==========================================="
echo "All resources have been deleted:"
echo "✓ ML Lambda function"
echo "✓ SES email configuration (account-level, preserved)"
echo "✓ API Gateway"
echo "✓ DynamoDB table"
echo "✓ CloudFront distribution and OAC"
echo "✓ S3 buckets"
echo "✓ ECR repository and Docker images"
echo "✓ IAM roles and policies"
echo ""
echo "All AWS resources have been completely removed."
