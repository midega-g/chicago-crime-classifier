#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

# FORCE_DELETE=true enables non-interactive destructive actions
FORCE_DELETE="${FORCE_DELETE:-false}"

trap 'rm -f upload-lifecycle-policy.json upload-cors-policy.json' EXIT

log_section "S3 Buckets Creation"

log_info "Creating buckets for Chicago Crimes application..."
log_info "FORCE_DELETE mode: ${FORCE_DELETE}"

############################################
# Helper: check if bucket has any objects
############################################
bucket_has_objects() {
  local bucket="$1"

  aws s3api list-objects-v2 \
    --bucket "$bucket" \
    --max-items 1 \
    --query 'length(Contents[])' \
    --output text 2>/dev/null | grep -q '[1-9]'
}

############################################
# Helper: confirm or force delete
############################################
confirm_or_force_delete() {
  local bucket="$1"

  if [[ "$FORCE_DELETE" == "true" ]]; then
    log_warn "FORCE_DELETE enabled — deleting all objects in $bucket"
    run_aws aws s3 rm "s3://$bucket" --recursive
    return
  fi

  read -rp "Delete all objects in $bucket? (yes/no): " confirm
  confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')

  if [[ "$confirm" == "yes" ]]; then
    log_info "Emptying bucket..."
    run_aws aws s3 rm "s3://$bucket" --recursive
  else
    log_info "Keeping existing bucket and contents"
  fi
}

############################################
# STATIC WEBSITE BUCKET
############################################
log_info "Checking static website bucket..."

if aws s3api head-bucket --bucket "$STATIC_BUCKET" 2>/dev/null; then
  log_warn "Bucket $STATIC_BUCKET already exists"

  if bucket_has_objects "$STATIC_BUCKET"; then
    log_warn "Bucket $STATIC_BUCKET contains objects"
    confirm_or_force_delete "$STATIC_BUCKET"
  fi
else
  log_info "Creating static website bucket..."
  run_aws aws s3 mb "s3://$STATIC_BUCKET" --region "$REGION"
  log_success "Static bucket created: $STATIC_BUCKET"
fi

log_info "Applying ownership controls and public access block (static bucket)..."

run_aws aws s3api put-bucket-ownership-controls \
  --bucket "$STATIC_BUCKET" \
  --ownership-controls '{
    "Rules": [{"ObjectOwnership": "BucketOwnerEnforced"}]
  }' >/dev/null

run_aws aws s3api put-public-access-block \
  --bucket "$STATIC_BUCKET" \
  --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }' >/dev/null

############################################
# UPLOAD BUCKET
############################################
log_info "Checking upload bucket..."

if aws s3api head-bucket --bucket "$UPLOAD_BUCKET" 2>/dev/null; then
  log_warn "Bucket $UPLOAD_BUCKET already exists"

  if bucket_has_objects "$UPLOAD_BUCKET"; then
    log_warn "Bucket $UPLOAD_BUCKET contains objects"
    confirm_or_force_delete "$UPLOAD_BUCKET"
  fi
else
  log_info "Creating upload bucket..."
  run_aws aws s3 mb "s3://$UPLOAD_BUCKET" --region "$REGION"
  log_success "Upload bucket created: $UPLOAD_BUCKET"
fi

log_info "Applying ownership controls and public access block (upload bucket)..."

run_aws aws s3api put-bucket-ownership-controls \
  --bucket "$UPLOAD_BUCKET" \
  --ownership-controls '{
    "Rules": [{"ObjectOwnership": "BucketOwnerEnforced"}]
  }' >/dev/null

run_aws aws s3api put-public-access-block \
  --bucket "$UPLOAD_BUCKET" \
  --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }' >/dev/null

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

run_aws aws s3api put-bucket-lifecycle-configuration \
  --bucket "$UPLOAD_BUCKET" \
  --lifecycle-configuration file://upload-lifecycle-policy.json >/dev/null

############################################
# VERSIONING
############################################
log_info "Enabling versioning on upload bucket..."

run_aws aws s3api put-bucket-versioning \
  --bucket "$UPLOAD_BUCKET" \
  --versioning-configuration Status=Enabled >/dev/null

############################################
# CORS (TEMPORARY)
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

run_aws aws s3api put-bucket-cors \
  --bucket "$UPLOAD_BUCKET" \
  --cors-configuration file://upload-cors-policy.json >/dev/null

############################################
# SUMMARY
############################################
log_success "S3 buckets configured successfully!"
log_info "Static website bucket: ${YELLOW}$STATIC_BUCKET${NC}"
log_info "Upload bucket: ${YELLOW}$UPLOAD_BUCKET${NC} (versioned, lifecycle enabled)"

log_summary "S3 setup completed!"
echo -e "${CYAN}Next:${NC} Run 02-deploy-static-website.sh"
