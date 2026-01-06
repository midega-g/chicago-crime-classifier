#!/usr/bin/env bash

set -euo pipefail

# -------------------------------------------------------------------
# Load shared configuration and helpers
# -------------------------------------------------------------------
source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

trap 'rm -f s3-notification.json' EXIT

log_section "S3 Trigger Configuration"

# -------------------------------------------------------------------
# Verify Lambda function exists
# -------------------------------------------------------------------
log_info "Verifying Lambda function exists..."

if ! aws --profile "$AWS_PROFILE" lambda get-function \
    --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
    log_error "Lambda function not found. Run 06e-deploy-lambda-function.sh first."
    exit 1
fi

log_info "Lambda function verified: ${YELLOW}$FUNCTION_NAME${NC}"
echo ""

# -------------------------------------------------------------------
# Add S3 permission to Lambda
# -------------------------------------------------------------------
log_info "Adding S3 permission to Lambda function..."

if aws --profile "$AWS_PROFILE" lambda add-permission \
    --function-name "$FUNCTION_NAME" \
    --principal s3.amazonaws.com \
    --action lambda:InvokeFunction \
    --source-arn "arn:aws:s3:::$UPLOAD_BUCKET" \
    --statement-id s3-trigger >/dev/null 2>&1; then
    log_success "S3 permission added successfully"
else
    log_warn "S3 permission add failed (may already exist)"
fi
echo ""

# -------------------------------------------------------------------
# Create S3 notification configuration
# -------------------------------------------------------------------
log_info "Creating S3 notification configuration..."

LAMBDA_ARN="$(get_lambda_function_arn)"
if [ -z "$LAMBDA_ARN" ]; then
    log_error "Failed to get Lambda ARN"
    exit 1
fi

log_info "Using Lambda ARN for trigger: ${YELLOW}${LAMBDA_ARN}${NC}"

cat > s3-notification.json << EOF
{
    "LambdaFunctionConfigurations": [
        {
            "Id": "ProcessUploadedFiles",
            "LambdaFunctionArn": "${LAMBDA_ARN}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "uploads/"
                        }
                    ]
                }
            }
        }
    ]
}
EOF

# -------------------------------------------------------------------
# Apply S3 notification configuration
#   NOTE: This replaces all existing S3 notification configurations on the bucket.
#   Safe because this bucket is dedicated to Lambda ingestion.
# -------------------------------------------------------------------
log_info "Applying S3 notification configuration..."

if aws --profile "$AWS_PROFILE" s3api put-bucket-notification-configuration \
    --bucket "$UPLOAD_BUCKET" \
    --notification-configuration file://s3-notification.json; then
    log_success "S3 notification configuration applied successfully"
else
    log_error "S3 notification configuration failed - bucket may not exist"
    log_info "Run 01-create-s3-buckets.sh first"
    exit 1
fi
echo ""

# -------------------------------------------------------------------
# Final output
# -------------------------------------------------------------------
log_success "S3 trigger configuration completed!"
log_info "Trigger Bucket: ${YELLOW}$UPLOAD_BUCKET${NC}"
log_info "Trigger Prefix: ${YELLOW}uploads/${NC}"
log_info "Lambda Function: ${YELLOW}$FUNCTION_NAME${NC}"
log_info "Events: ${YELLOW}s3:ObjectCreated:*${NC}"

log_summary "S3 trigger configured successfully! ${CYAN}Next:${NC} Run 12-configure-api-integration.sh"
