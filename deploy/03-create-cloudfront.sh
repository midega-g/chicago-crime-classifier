#!/bin/bash

# Chicago Crimes Serverless Deployment - CloudFront Setup
# This script creates CloudFront distribution for private S3 bucket access

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "Creating CloudFront distribution with Origin Access Control..."

# Step 1: Create or get existing Origin Access Control (OAC)
echo "Checking for existing Origin Access Control..."
EXISTING_OAC=$(aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='chicago-crimes-oac'].Id" --output text)

if [ ! -z "$EXISTING_OAC" ] && [ "$EXISTING_OAC" != "None" ]; then
    echo "Reusing existing OAC: $EXISTING_OAC"
    OAC_ID=$EXISTING_OAC
else
    echo "Creating new Origin Access Control..."
    TIMESTAMP=$(date +%s)
    OAC_RESPONSE=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config \
            Name="chicago-crimes-oac-$TIMESTAMP",Description="OAC for Chicago Crimes static website",OriginAccessControlOriginType="s3",SigningBehavior="always",SigningProtocol="sigv4")
    
    OAC_ID=$(echo $OAC_RESPONSE | jq -r '.OriginAccessControl.Id')
    echo "Created OAC with ID: $OAC_ID"
fi

echo "Using OAC ID: $OAC_ID"

# Step 2: Create CloudFront distribution configuration
cat > cloudfront-config.json << EOF
{
    "CallerReference": "chicago-crimes-$(date +%s)",
    "Comment": "$DISTRIBUTION_COMMENT",
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3-$STATIC_BUCKET",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "ForwardedValues": {
            "QueryString": false,
            "Cookies": {
                "Forward": "none"
            }
        },
        "MinTTL": 0,
        "DefaultTTL": 86400,
        "MaxTTL": 31536000,
        "Compress": true,
        "AllowedMethods": {
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        }
    },
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3-$STATIC_BUCKET",
                "DomainName": "$STATIC_BUCKET.s3.$REGION.amazonaws.com",
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                },
                "OriginAccessControlId": "$OAC_ID"
            }
        ]
    },
    "Enabled": true,
    "DefaultRootObject": "index.html",
    "CustomErrorResponses": {
        "Quantity": 1,
        "Items": [
            {
                "ErrorCode": 404,
                "ResponsePagePath": "/index.html",
                "ResponseCode": "200",
                "ErrorCachingMinTTL": 300
            }
        ]
    },
    "PriceClass": "PriceClass_100"
}
EOF

# Step 3: Create the distribution
echo "Creating CloudFront distribution..."
DISTRIBUTION_RESPONSE=$(aws cloudfront create-distribution \
    --distribution-config file://cloudfront-config.json)

DISTRIBUTION_ID=$(echo $DISTRIBUTION_RESPONSE | jq -r '.Distribution.Id')
DOMAIN_NAME=$(echo $DISTRIBUTION_RESPONSE | jq -r '.Distribution.DomainName')

echo "Distribution created with ID: $DISTRIBUTION_ID"

# Step 4: Update S3 bucket policy to allow CloudFront access
echo "Updating S3 bucket policy for CloudFront access..."
cat > s3-cloudfront-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontServicePrincipal",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$STATIC_BUCKET/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DISTRIBUTION_ID"
                }
            }
        }
    ]
}
EOF

aws s3api put-bucket-policy \
    --bucket $STATIC_BUCKET \
    --policy file://s3-cloudfront-policy.json

echo "CloudFront distribution created successfully!"
echo "Distribution ID: $DISTRIBUTION_ID"
echo "Domain Name: $DOMAIN_NAME"
echo "Status: Deploying (this may take 10-15 minutes)"
echo ""
echo "S3 bucket is now private and accessible only via CloudFront"
echo "Once deployed, your app will be available at: https://$DOMAIN_NAME"

# Clean up
rm -f cloudfront-config.json s3-cloudfront-policy.json

echo ""
echo "IMPORTANT: Update the API_GATEWAY_URL in static-web/script.js and redeploy:"
echo "1. Update API_GATEWAY_URL in static-web/script.js"
echo "2. Run: ./deploy/05-deploy-static-website.sh"
echo "3. Invalidate CloudFront cache: aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths '/*'"