#!/usr/bin/env bash

set -euo pipefail

# -------------------------------------------------------------------
# Load shared configuration and helpers
# -------------------------------------------------------------------
source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

# -------------------------------------------------------------------
# Preflight checks
# -------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || {
  log_error "jq is required but not installed. Please install jq and retry."
  exit 1
}

trap 'rm -f cloudfront-config.json s3-cloudfront-policy.json upload-cors-policy.json' EXIT

log_section "CloudFront Distribution Setup"

# -------------------------------------------------------------------
# Check if CloudFront distribution already exists
# -------------------------------------------------------------------
log_info "Checking for existing CloudFront distribution..."

EXISTING_DIST=$(aws cloudfront list-distributions \
  --profile "$AWS_PROFILE" \
  --query "DistributionList.Items[?Comment=='$DISTRIBUTION_COMMENT'].Id | [0]" \
  --output text 2>/dev/null || echo "")

if [[ -n "$EXISTING_DIST" && "$EXISTING_DIST" != "None" ]]; then
    DOMAIN_NAME=$(aws cloudfront get-distribution \
      --profile "$AWS_PROFILE" \
      --id "$EXISTING_DIST" \
      --query 'Distribution.DomainName' \
      --output text)

    log_warn "CloudFront distribution already exists: $EXISTING_DIST"
    log_info "Domain Name: ${YELLOW}https://$DOMAIN_NAME${NC}"
    log_summary "Using existing CloudFront distribution"
    echo -e "${CYAN}Next:${NC} Run 04-create-api-gateway.sh"
    exit 0
fi

log_info "Creating new CloudFront distribution..."

# -------------------------------------------------------------------
# Step 1: Create or reuse Origin Access Control (OAC)
# -------------------------------------------------------------------
OAC_NAME="$CF_OAC_NAME"

log_info "Checking for existing Origin Access Control..."

EXISTING_OAC=$(aws cloudfront list-origin-access-controls \
  --query "OriginAccessControlList.Items[?Name=='$OAC_NAME'].Id | [0]" \
  --output text \
  --profile "$AWS_PROFILE" 2>/dev/null || echo "")

if [[ -n "$EXISTING_OAC" && "$EXISTING_OAC" != "None" ]]; then
    OAC_ID="$EXISTING_OAC"
    log_info "Reusing existing OAC: $OAC_ID"
else
    log_info "Creating new Origin Access Control..."
    # shellcheck disable=SC2140
    OAC_RESPONSE=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config \
        --profile "$AWS_PROFILE" \
        Name="$OAC_NAME",Description="OAC for Chicago Crimes static website",OriginAccessControlOriginType="s3",SigningBehavior="always",SigningProtocol="sigv4")

    OAC_ID=$(echo "$OAC_RESPONSE" | jq -r '.OriginAccessControl.Id')
    log_success "Created OAC with ID: $OAC_ID"
fi

# -------------------------------------------------------------------
# Step 2: Create CloudFront distribution configuration
# -------------------------------------------------------------------
log_info "Creating CloudFront distribution configuration..."

cat > cloudfront-config.json << EOF
{
  "CallerReference": "chicago-crimes-$(date +%s)",
  "Comment": "$DISTRIBUTION_COMMENT",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "PriceClass": "PriceClass_100",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "S3-$STATIC_BUCKET",
        "DomainName": "$STATIC_BUCKET.s3.$REGION.amazonaws.com",
        "OriginAccessControlId": "$OAC_ID",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-$STATIC_BUCKET",
    "ViewerProtocolPolicy": "redirect-to-https",
    "Compress": true,
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "ForwardedValues": {
      "QueryString": false,
      "Cookies": { "Forward": "none" }
    },
    "MinTTL": 0,
    "DefaultTTL": 86400,
    "MaxTTL": 31536000
  },
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
  }
}
EOF

# -------------------------------------------------------------------
# Step 3: Create CloudFront distribution
# -------------------------------------------------------------------
log_info "Creating CloudFront distribution..."

DISTRIBUTION_RESPONSE=$(aws cloudfront create-distribution \
  --profile "$AWS_PROFILE" \
  --distribution-config file://cloudfront-config.json)

DISTRIBUTION_ID=$(echo "$DISTRIBUTION_RESPONSE" | jq -r '.Distribution.Id')
DOMAIN_NAME=$(echo "$DISTRIBUTION_RESPONSE" | jq -r '.Distribution.DomainName')

log_success "Distribution created with ID: $DISTRIBUTION_ID"

# -------------------------------------------------------------------
# Step 4: Update S3 bucket policy to allow CloudFront access
# -------------------------------------------------------------------
log_info "Updating S3 bucket policy for CloudFront access..."

cat > s3-cloudfront-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
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

run_aws aws --profile "$AWS_PROFILE" s3api put-bucket-policy \
  --bucket "$STATIC_BUCKET" \
  --policy file://s3-cloudfront-policy.json

# -------------------------------------------------------------------
# Step 5: Update upload bucket CORS policy
# -------------------------------------------------------------------
log_info "Updating S3 upload bucket CORS policy..."

cat > upload-cors-policy.json << EOF
{
  "CORSRules": [
    {
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
      "AllowedOrigins": ["https://$DOMAIN_NAME"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 86400
    }
  ]
}
EOF

run_aws aws --profile "$AWS_PROFILE" s3api put-bucket-cors \
  --bucket "$UPLOAD_BUCKET" \
  --cors-configuration file://upload-cors-policy.json

# -------------------------------------------------------------------
# Final output
# -------------------------------------------------------------------
log_success "CloudFront distribution created successfully!"
log_info "Distribution ID: ${YELLOW}$DISTRIBUTION_ID${NC}"
log_info "Domain Name: ${YELLOW}https://$DOMAIN_NAME${NC}"
log_warn "Status: Deploying (may take 10-15 minutes)"

log_warn "IMPORTANT:"
log_info "1. Update API_GATEWAY_URL in static-web/script.js"
log_info "2. Redeploy static site: 02-deploy-static-website.sh"
log_info "3. Invalidate cache if needed"

log_summary "CloudFront distribution setup completed!"
echo -e "${CYAN}Next:${NC} Run 04-create-api-gateway.sh"
