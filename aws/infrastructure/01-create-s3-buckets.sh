#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

trap 'rm -f upload-lifecycle-policy.json upload-cors-policy.json' EXIT

log_section "S3 Buckets Creation"

log_info "Configuring buckets for Chicago Crimes application..."
echo ""

############################################
# Helper: apply bucket configuration
############################################
apply_bucket_config() {
  local bucket="$1"
  local bucket_type="$2"

  log_info "Applying configuration to $bucket_type bucket..."

  # Ownership controls
  aws s3api put-bucket-ownership-controls \
    --bucket "$bucket" \
    --ownership-controls '{
      "Rules": [{"ObjectOwnership": "BucketOwnerEnforced"}]
    }' >/dev/null

  # Public access block
  aws s3api put-public-access-block \
    --bucket "$bucket" \
    --public-access-block-configuration '{
      "BlockPublicAcls": true,
      "IgnorePublicAcls": true,
      "BlockPublicPolicy": true,
      "RestrictPublicBuckets": true
    }' >/dev/null

  log_success "Configuration applied to $bucket_type bucket"
}

############################################
# STATIC WEBSITE BUCKET
############################################
log_info "Checking static website bucket..."

if aws s3api head-bucket --bucket "$STATIC_BUCKET" 2>/dev/null; then
  log_success "Bucket ${YELLOW}$STATIC_BUCKET${NC} exists"
else
  log_info "Creating static website bucket..."
  aws s3 mb "s3://$STATIC_BUCKET" --region "$REGION" --profile "$AWS_PROFILE"
  log_success "Static bucket created: ${YELLOW}$STATIC_BUCKET${NC}"
fi

apply_bucket_config "$STATIC_BUCKET" "static"
echo ""

############################################
# UPLOAD BUCKET
############################################
log_info "Checking upload bucket..."

if aws s3api head-bucket --bucket "$UPLOAD_BUCKET" 2>/dev/null; then
  log_success "Bucket ${YELLOW}$UPLOAD_BUCKET${NC} exists"
else
  log_info "Creating upload bucket..."
  aws s3 mb "s3://$UPLOAD_BUCKET" --region "$REGION" --profile "$AWS_PROFILE"
  log_success "Upload bucket created: ${YELLOW}$UPLOAD_BUCKET${NC}"
fi

apply_bucket_config "$UPLOAD_BUCKET" "upload"

############################################
# LIFECYCLE POLICY
############################################
log_info "Configuring lifecycle policy for upload bucket..."

cat > upload-lifecycle-policy.json <<EOF
{
  "Rules": [
    {
      "ID": "DeleteUploadsAfter1Day",
      "Status": "Enabled",
      "Filter": {},
      "Expiration": { "Days": 1 },
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 1
      }
    }
  ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
  --bucket "$UPLOAD_BUCKET" \
  --lifecycle-configuration file://upload-lifecycle-policy.json >/dev/null

log_success "Lifecycle policy applied"

############################################
# VERSIONING
############################################
log_info "Enabling versioning on upload bucket..."

aws s3api put-bucket-versioning \
  --bucket "$UPLOAD_BUCKET" \
  --versioning-configuration Status=Enabled >/dev/null

log_success "Versioning enabled"

############################################
# CORS
############################################
log_info "Configuring CORS policy for upload bucket..."

cat > upload-cors-policy.json <<EOF
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
  --bucket "$UPLOAD_BUCKET" \
  --cors-configuration file://upload-cors-policy.json >/dev/null

log_success "CORS policy applied"

############################################
# SUMMARY
############################################
echo ""
log_success "S3 bucket infrastructure configured successfully!"
echo ""

log_info "Buckets summary:"
log_info "  Static: ${YELLOW}$STATIC_BUCKET${NC}"
log_info "  Upload: ${YELLOW}$UPLOAD_BUCKET${NC} (versioned, lifecycle enabled)"
echo ""

log_info "${CYAN}Note:${NC} This script is idempotent - safe to run repeatedly"
log_info "      Bucket content is managed by deployment scripts"

log_summary "S3 infrastructure setup completed! ${CYAN}Next:${NC} Run 02-deploy-static-website.sh"