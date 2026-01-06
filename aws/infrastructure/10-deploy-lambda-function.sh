#!/usr/bin/env bash

set -euo pipefail

# -------------------------------------------------------------------
# Load shared configuration and helpers
# -------------------------------------------------------------------
source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

log_section "Lambda Function Deployment"

# -------------------------------------------------------------------
# Get Docker image URI
# -------------------------------------------------------------------
log_info "Getting ECR repository URI..."

IMAGE_URI="$(verify_ecr_image_exists)":"$IMAGE_TAG"

if [[ -z "$IMAGE_URI" ]]; then
    log_error "Could not retrieve valid image URI for ${ECR_REPO}:${IMAGE_TAG}"
    exit 1
fi

log_info "Using image: $IMAGE_URI"

# -------------------------------------------------------------------
# Verify IAM role exists
# -------------------------------------------------------------------
log_info "Verifying IAM role exists..."

ROLE_ARN=$(aws --profile "$AWS_PROFILE" iam get-role \
  --role-name "$ROLE_NAME" \
  --query 'Role.Arn' \
  --output text 2>/dev/null)

if [[ -z "$ROLE_ARN" ]]; then
    log_error "Failed to retrieve ARN for role $ROLE_NAME"
    log_error "Make sure the role exists and the profile has iam:GetRole permission"
    exit 1
fi

log_info "Using role ARN: $ROLE_ARN"


# -------------------------------------------------------------------
# Check if Lambda function exists
# -------------------------------------------------------------------
log_info "Checking for existing Lambda function..."

if aws --profile "$AWS_PROFILE" lambda get-function \
    --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then

    log_warn "Function exists, updating code..."

    aws --profile "$AWS_PROFILE" lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --image-uri "$IMAGE_URI" \
        --output text >/dev/null 2>&1

    log_info "Waiting for code update to complete..."
    aws --profile "$AWS_PROFILE" lambda wait function-updated \
        --function-name "$FUNCTION_NAME"

    log_success "Code update completed"

    log_info "Updating function configuration..."
    aws --profile "$AWS_PROFILE" lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --environment "Variables={UPLOAD_BUCKET=$UPLOAD_BUCKET,RESULTS_TABLE=$RESULTS_TABLE}" \
        --timeout 300 \
        --memory-size 2048 \
        --description "$LAMBDA_DESCRIPTION" >/dev/null

    log_info "Waiting for configuration update to complete..."
    aws --profile "$AWS_PROFILE" lambda wait function-updated \
        --function-name "$FUNCTION_NAME"

    log_success "Function configuration updated"

else
    log_info "Creating new Lambda function..."

    # Temporarily disable auto-exit so we can inspect failures
    set +e
    CREATE_OUTPUT=$(timeout 120 aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --role "$ROLE_ARN" \
        --code ImageUri="$IMAGE_URI" \
        --package-type Image \
        --environment Variables="{UPLOAD_BUCKET=$UPLOAD_BUCKET,RESULTS_TABLE=$RESULTS_TABLE}" \
        --timeout 300 \
        --memory-size 2048 \
        --description "$LAMBDA_DESCRIPTION" \
        --profile "$AWS_PROFILE" \
        --region "$REGION" 2>&1)

    CREATE_EXIT_CODE=$?
    set -e

    if [[ $CREATE_EXIT_CODE -eq 0 ]]; then
        FUNCTION_ARN=$(echo "$CREATE_OUTPUT" | jq -r '.FunctionArn' 2>/dev/null || echo "unknown")
        log_success "Function created successfully: $FUNCTION_ARN"
    elif [[ $CREATE_EXIT_CODE -eq 124 ]]; then
        log_error "Function creation timed out after 120 seconds"
        log_error "AWS CLI may be hanging - try running the command manually"
        exit 1
    else
        log_error "Failed to create Lambda function (exit code $CREATE_EXIT_CODE)"
        exit 1
    fi
fi

# -------------------------------------------------------------------
# Wait for function to be ready
# -------------------------------------------------------------------
log_info "Waiting for function to be ready..."

for i in {1..12}; do
  STATE=$(aws --profile "$AWS_PROFILE" lambda get-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --query 'State' \
    --output text 2>/dev/null || echo "Unknown")

  if [[ "$STATE" == "Active" ]]; then
    log_success "Lambda is active"
    break
  fi

  log_info "Current state: $STATE (retry $i/12)"
  sleep 10
done

# -------------------------------------------------------------------
# Final output
# -------------------------------------------------------------------
log_success "Lambda function deployment completed!"
log_info "Function Name: ${YELLOW}$FUNCTION_NAME${NC}"
log_info "Image URI: ${YELLOW}$IMAGE_URI${NC}"
log_info "Package Type: ${YELLOW}Container${NC}"
log_info "Memory: ${YELLOW}2048 MB${NC}"
log_info "Timeout: ${YELLOW}300 seconds${NC}"

log_summary "Lambda function ready for integration!"
echo -e "${CYAN}Next:${NC} Run 11-configure-s3-trigger.sh"
