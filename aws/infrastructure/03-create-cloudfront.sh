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
# Verify prerequisites
# -------------------------------------------------------------------
log_info "Verifying prerequisites..."

if ! aws s3api head-bucket --bucket "$STATIC_BUCKET" --profile "$AWS_PROFILE" 2>/dev/null; then
  log_error "Static bucket $STATIC_BUCKET does not exist. Run 01-create-s3-buckets.sh first."
  exit 1
fi

if ! aws s3api head-bucket --bucket "$UPLOAD_BUCKET" --profile "$AWS_PROFILE" 2>/dev/null; then
  log_error "Upload bucket $UPLOAD_BUCKET does not exist. Run 01-create-s3-buckets.sh first."
  exit 1
fi

log_success "Prerequisites verified"
echo ""

# -------------------------------------------------------------------
# Check if CloudFront distribution already exists
# -------------------------------------------------------------------
log_info "Checking for existing CloudFront distribution..."

EXISTING_DIST=$(aws cloudfront list-distributions \
  --profile "$AWS_PROFILE" \
  --query "DistributionList.Items[?Comment=='$DISTRIBUTION_COMMENT'].Id | [0]" \
  --output text 2>/dev/null || echo "")

if [[ -n "$EXISTING_DIST" && "$EXISTING_DIST" != "None" ]]; then
    DIST_STATUS=$(aws cloudfront get-distribution \
      --profile "$AWS_PROFILE" \
      --id "$EXISTING_DIST" \
      --query 'Distribution.Status' \
      --output text)
    
    DOMAIN_NAME=$(aws cloudfront get-distribution \
      --profile "$AWS_PROFILE" \
      --id "$EXISTING_DIST" \
      --query 'Distribution.DomainName' \
      --output text)

    log_success "CloudFront distribution already exists: ${YELLOW}$EXISTING_DIST${NC}"
    log_info "Domain Name: ${BLUE}https://$DOMAIN_NAME${NC}"
    log_info "Status: ${GREEN}$DIST_STATUS${NC}"
    
    # Update bucket policies even if distribution exists
    log_info "Verifying bucket policies are up to date..."
    
    # Update S3 bucket policy
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
          "AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$EXISTING_DIST"
        }
      }
    }
  ]
}
EOF

    aws s3api put-bucket-policy \
      --profile "$AWS_PROFILE" \
      --bucket "$STATIC_BUCKET" \
      --policy file://s3-cloudfront-policy.json >/dev/null

    # Update upload bucket CORS
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

    aws s3api put-bucket-cors \
      --profile "$AWS_PROFILE" \
      --bucket "$UPLOAD_BUCKET" \
      --cors-configuration file://upload-cors-policy.json >/dev/null

    log_success "Bucket policies updated"
    echo ""
    log_summary "Using existing CloudFront distribution ${CYAN}Next:${NC} Run 04-create-api-gateway.sh"
    exit 0
fi

log_info "No existing distribution found. Creating new one..."
echo ""

# -------------------------------------------------------------------
# Step 1: Create or reuse Origin Access Control (OAC)
# -------------------------------------------------------------------
OAC_NAME="$CF_OAC_NAME"

log_info "Checking for existing Origin Access Control..."

EXISTING_OAC=$(aws cloudfront list-origin-access-controls \
  --profile "$AWS_PROFILE" \
  --query "OriginAccessControlList.Items[?Name=='$OAC_NAME'].Id | [0]" \
  --output text 2>/dev/null || echo "")

if [[ -n "$EXISTING_OAC" && "$EXISTING_OAC" != "None" ]]; then
    OAC_ID="$EXISTING_OAC"
    log_success "Reusing existing OAC: ${YELLOW}$OAC_ID${NC}"
else
    log_info "Creating new Origin Access Control..."
    OAC_RESPONSE=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config \
        Name="$OAC_NAME",Description="OAC for Chicago Crimes static website",OriginAccessControlOriginType="s3",SigningBehavior="always",SigningProtocol="sigv4" \
        --profile "$AWS_PROFILE")

    OAC_ID=$(echo "$OAC_RESPONSE" | jq -r '.OriginAccessControl.Id')
    log_success "Created OAC with ID: ${YELLOW}$OAC_ID${NC}"
fi
echo ""

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

log_success "Configuration file created"

# -------------------------------------------------------------------
# Step 3: Create CloudFront distribution
# -------------------------------------------------------------------
log_info "Creating CloudFront distribution (this may take a moment)..."

DISTRIBUTION_RESPONSE=$(aws cloudfront create-distribution \
  --profile "$AWS_PROFILE" \
  --distribution-config file://cloudfront-config.json)

DISTRIBUTION_ID=$(echo "$DISTRIBUTION_RESPONSE" | jq -r '.Distribution.Id')
DOMAIN_NAME=$(echo "$DISTRIBUTION_RESPONSE" | jq -r '.Distribution.DomainName')

log_success "Distribution created with ID: ${YELLOW}$DISTRIBUTION_ID${NC}"
log_info "Domain Name: ${BLUE}https://$DOMAIN_NAME${NC}"
echo ""

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

aws s3api put-bucket-policy \
  --profile "$AWS_PROFILE" \
  --bucket "$STATIC_BUCKET" \
  --policy file://s3-cloudfront-policy.json

log_success "S3 bucket policy updated"

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

aws s3api put-bucket-cors \
  --profile "$AWS_PROFILE" \
  --bucket "$UPLOAD_BUCKET" \
  --cors-configuration file://upload-cors-policy.json

log_success "Upload bucket CORS policy updated"
echo ""

# -------------------------------------------------------------------
# Final output
# -------------------------------------------------------------------
log_success "CloudFront distribution created successfully!"
echo ""

log_info "Distribution details:"
log_info "  ID          : ${YELLOW}$DISTRIBUTION_ID${NC}"
log_info "  Domain Name : ${BLUE}https://$DOMAIN_NAME${NC}"
log_info "  Status      : ${YELLOW}Deploying${NC} (may take 10-15 minutes)"
echo ""

log_warn "${CYAN}Post-deployment steps:${NC}"
log_info "1. Wait for distribution status to change to 'Deployed'"
log_info "   Check status: ${GREEN}aws cloudfront get-distribution --id $DISTRIBUTION_ID --query 'Distribution.Status'${NC}"
log_info ""
log_info "2. Update ${GREEN}API_GATEWAY_URL${NC} in ${BLUE}aws/static-web/script.js${NC}"
log_info ""
log_info "3. Redeploy static site: ${GREEN}./02-deploy-static-website.sh${NC}"
log_info ""
log_info "4. Test your site: ${BLUE}https://$DOMAIN_NAME${NC}"
echo ""

log_info "${CYAN}Cache invalidation (if needed):${NC}"
log_info "  ${GREEN}aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths '/*'${NC}"

log_summary "CloudFront distribution setup completed! ${CYAN}Next:${NC} Run 04-create-api-gateway.sh"