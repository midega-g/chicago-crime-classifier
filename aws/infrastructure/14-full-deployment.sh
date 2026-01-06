#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# Load configuration
# ==============================================================================

source "$(dirname "$0")/00-config.sh" || {
  log_error "Failed to load config"
  exit 1
}

log_section "Full Infrastructure Deployment"
log_info "Starting complete serverless deployment..."

# ==============================================================================
# STEP 1: Create S3 buckets
# ==============================================================================

FORCE_DELETE=true "$(dirname "$0")/01-create-s3-buckets.sh"

# ==============================================================================
# STEP 2: Deploy static website to S3
# ==============================================================================

"$(dirname "$0")/02-deploy-static-website.sh"

# ==============================================================================
# STEP 3: Create CloudFront distribution
# ==============================================================================

"$(dirname "$0")/03-create-cloudfront.sh"

# ==============================================================================
# STEP 4: Create API Gateway
# ==============================================================================

"$(dirname "$0")/04-create-api-gateway.sh"

# ==============================================================================
# STEP 5: Create DynamoDB table
# ==============================================================================

"$(dirname "$0")/05-create-dynamodb.sh"

# ==============================================================================
# STEP 6: Create ECR repository
# ==============================================================================

"$(dirname "$0")/06-create-ecr-repository.sh"

# ==============================================================================
# STEP 7: Build and push Docker image
# ==============================================================================

"$(dirname "$0")/07-build-push-docker.sh"

# ==============================================================================
# STEP 8: Create Lambda execution role
# ==============================================================================

"$(dirname "$0")/08-create-lambda-role.sh"

# ==============================================================================
# STEP 9: Set up SES email
# ==============================================================================

"$(dirname "$0")/09-setup-ses-email.sh"

# ==============================================================================
# STEP 10: Deploy Lambda function
# ==============================================================================

"$(dirname "$0")/10-deploy-lambda-function.sh"

# ==============================================================================
# STEP 11: Configure integrations (S3 trigger + API Gateway)
# ==============================================================================

"$(dirname "$0")/11-configure-s3-trigger.sh"
"$(dirname "$0")/12-configure-api-integration.sh"

# ==============================================================================
# CloudFront deployment wait (long-running step)
# ==============================================================================

log_section "CloudFront deployment wait (long-running step)"
log_info "Waiting for CloudFront distribution to be deployed..."

DISTRIBUTION_ID=$(get_cloudfront_distribution_id)

if [ -z "$DISTRIBUTION_ID" ] || [ "$DISTRIBUTION_ID" = "None" ]; then
    log_error "CloudFront distribution not found"
    exit 1
fi

log_info "CloudFront Distribution ID: ${YELLOW}$DISTRIBUTION_ID${NC}"

log_info "CloudFront deployment usually takes 5-15 minutes..."

wait_cmd=(
  aws --profile "$AWS_PROFILE"
  cloudfront wait distribution-deployed
  --id "$DISTRIBUTION_ID"
)

if command -v timeout >/dev/null 2>&1; then
  log_info "Waiting for CloudFront distribution (max 20 minutes)..."
  if timeout 1200 "${wait_cmd[@]}" > /dev/null 2>&1; then
    log_success "CloudFront distribution is ${GREEN}deployed and ready${NC}"
  else
    exit_code=$?

    if [ "$exit_code" -eq 124 ]; then
      log_error "Timed out waiting for CloudFront distribution to deploy (20 minutes)"
    else
      log_error "CloudFront deployment ${RED}failed${NC} (AWS CLI error)"
    fi

    log_error "Check AWS Console → CloudFront → Distributions"
    exit 1
  fi
else
  log_warn "'timeout' not available — waiting without time limit"
  if "${wait_cmd[@]}" > /dev/null 2>&1; then
    log_success "CloudFront distribution is deployed and ready"
  else
    log_error "CloudFront deployment failed"
    log_error "Check AWS Console → CloudFront → Distributions"
    exit 1
  fi
fi

# ==============================================================================
# Final cache invalidation and URL output
# ==============================================================================

log_info "Updating static files and invalidating cache..."
"$(dirname "$0")/13-update-and-invalidate.sh"

API_ID=$(get_api_gateway_id)
CLOUDFRONT_URL=$(get_cloudfront_distribution_url)

# ==============================================================================
# Summary
# ==============================================================================

log_section "DEPLOYMENT COMPLETE!"
log_info "API Gateway: ${BLUE}https://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE_NAME${NC}"

log_success "Access your application: ${BLUE}https://$CLOUDFRONT_URL${NC}"
log_warn "CloudFront may take 10-15 minutes to fully propagate"
echo ""
