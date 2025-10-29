#!/bin/bash

# Chicago Crimes Serverless Deployment - S3 Buckets Setup
# This script creates the required S3 buckets for the application

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "Creating S3 buckets for Chicago Crimes application..."

# Check if static bucket exists and handle accordingly
if aws s3 ls s3://$STATIC_BUCKET 2>/dev/null; then
    echo "Bucket $STATIC_BUCKET already exists"

    # Check if bucket has content
    OBJECT_COUNT=$(aws s3 ls s3://$STATIC_BUCKET --recursive | wc -l)
    if [ $OBJECT_COUNT -gt 0 ]; then
        echo "WARNING: Bucket $STATIC_BUCKET contains $OBJECT_COUNT objects"
        read -p "Delete all objects and recreate bucket? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            echo "Emptying bucket..."
            aws s3 rm s3://$STATIC_BUCKET --recursive
        else
            echo "Keeping existing bucket and contents"
        fi
    fi
else
    echo "Creating private static website bucket: $STATIC_BUCKET"
    aws s3 mb s3://$STATIC_BUCKET --region $REGION
    echo "Bucket $STATIC_BUCKET created with private access (CloudFront will handle access)"
fi

# Check if upload bucket exists and handle accordingly
if aws s3 ls s3://$UPLOAD_BUCKET 2>/dev/null; then
    echo "Bucket $UPLOAD_BUCKET already exists"

    # Check if bucket has content
    OBJECT_COUNT=$(aws s3 ls s3://$UPLOAD_BUCKET --recursive | wc -l)
    if [ $OBJECT_COUNT -gt 0 ]; then
        echo "WARNING: Bucket $UPLOAD_BUCKET contains $OBJECT_COUNT objects"
        read -p "Delete all objects and recreate bucket? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            echo "Emptying bucket..."
            aws s3 rm s3://$UPLOAD_BUCKET --recursive
        else
            echo "Keeping existing bucket and contents"
        fi
    fi
else
    echo "Creating upload bucket: $UPLOAD_BUCKET"
    aws s3 mb s3://$UPLOAD_BUCKET --region $REGION
fi

# Configure lifecycle policy to delete files after 1 day
cat > upload-lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "DeleteUploadsAfter1Day",
            "Status": "Enabled",
            "Filter": {
                "Prefix": ""
            },
            "Expiration": {
                "Days": 1
            },
            "AbortIncompleteMultipartUpload": {
                "DaysAfterInitiation": 1
            }
        }
    ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
    --bucket $UPLOAD_BUCKET \
    --lifecycle-configuration file://upload-lifecycle-policy.json > /dev/null 2>&1

# Enable versioning on upload bucket
aws s3api put-bucket-versioning \
    --bucket $UPLOAD_BUCKET \
    --versioning-configuration Status=Enabled > /dev/null 2>&1

# Configure basic CORS for upload bucket (will be updated after CloudFront)
cat > upload-cors-policy.json << EOF
{
    "CORSRules": [
        {
            "AllowedHeaders": ["*"],
            "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
            "AllowedOrigins": ["*"],
            "ExposeHeaders": ["ETag"],
            "MaxAgeSeconds": 86400
        }
    ]
}
EOF

aws s3api put-bucket-cors \
    --bucket $UPLOAD_BUCKET \
    --cors-configuration file://upload-cors-policy.json > /dev/null 2>&1

echo "S3 buckets created successfully!"
echo "Static website bucket: $STATIC_BUCKET (private)"
echo "Upload bucket: $UPLOAD_BUCKET"
echo "Note: Static website will be accessed via CloudFront distribution"

# Clean up temporary files
rm -f upload-lifecycle-policy.json upload-cors-policy.json

echo ""
echo "--------------------------------NEXT STEP-----------------------------------"
echo ""
