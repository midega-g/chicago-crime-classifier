#!/usr/bin/env bash

set -euo pipefail

# Load configuration
source "$(dirname "$0")/00-config.sh" || {
  log_error "Failed to load config"
  exit 1
}

log_section "Update Static Files and Invalidate Cache"

log_info "Starting static files update..."
log_info "Static Bucket: ${YELLOW}$STATIC_BUCKET${NC}"
log_info "Region: ${YELLOW}$REGION${NC}"

# Get API Gateway URL
log_info "Getting API Gateway URL..."
API_ID=$(get_api_gateway_id)

if [ -z "$API_ID" ] || [ "$API_ID" = "None" ]; then
    log_error "API Gateway '$API_NAME' not found"
    log_error "Run 04-create-api-gateway.sh first"
    exit 1
fi

API_URL="https://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE_NAME"
log_success "Found API Gateway: $API_URL"

# Update script.js with API Gateway URL
log_info "Updating script.js with API Gateway URL..."
if [ -f "aws/static-web/script.js" ]; then
    # Create backup and use portable sed
    cp aws/static-web/script.js aws/static-web/script.js.bak

    # Use portable sed syntax that works on both GNU and BSD sed
    if sed "s|const API_GATEWAY_URL = '[^']*';|const API_GATEWAY_URL = '$API_URL';|g" \
        aws/static-web/script.js.bak > aws/static-web/script.js; then
        log_success "Updated script.js"
        rm aws/static-web/script.js.bak
    else
        log_error "Failed to update script.js"
        mv aws/static-web/script.js.bak aws/static-web/script.js  # Restore backup
        exit 1
    fi
else
    log_error "aws/static-web/script.js not found"
    exit 1
fi

# Upload static files to S3 with differentiated cache control
log_info "Uploading static files to S3..."

# Upload HTML files with short cache (should be revalidated)
if find aws/static-web -name "*.html" -type f | head -1 | grep -q .; then
    aws --profile "$AWS_PROFILE" s3 sync aws/static-web/ s3://$STATIC_BUCKET/ \
        --exclude "*" \
        --include "*.html" \
        --cache-control "max-age=0, must-revalidate" \
        --region "$REGION" > /dev/null 2>&1
fi

# Upload script.js with short cache (contains API Gateway URL)
if [ -f "aws/static-web/script.js" ]; then
    aws --profile "$AWS_PROFILE" s3 cp aws/static-web/script.js s3://$STATIC_BUCKET/script.js \
        --cache-control "max-age=300" \
        --region "$REGION" > /dev/null 2>&1
fi

# Upload other assets (CSS, images) with longer cache
aws --profile "$AWS_PROFILE" s3 sync aws/static-web/ s3://$STATIC_BUCKET/ \
    --exclude "*.html" \
    --exclude "script.js" \
    --cache-control "max-age=86400" \
    --region "$REGION" > /dev/null 2>&1

log_success "Static files uploaded successfully"

# Get CloudFront distribution and invalidate cache
log_info "Invalidating CloudFront cache..."
DISTRIBUTION_ID=$(get_cloudfront_distribution_id)

if [ -z "$DISTRIBUTION_ID" ] || [ "$DISTRIBUTION_ID" = "None" ]; then
    log_error "CloudFront distribution not found"
    exit 1
fi

log_success "Found CloudFront distribution: $DISTRIBUTION_ID"

# Create selective cache invalidation (only for files that change)
INVALIDATION_ID=$(aws --profile "$AWS_PROFILE" cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" \
    --paths "/" "/index.html" "/script.js" \
    --query 'Invalidation.Id' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$INVALIDATION_ID" ] && [ "$INVALIDATION_ID" != "None" ]; then
    log_success "Cache invalidation created: $INVALIDATION_ID"
    log_info "Waiting for invalidation to complete (this may take 2-5 minutes)..."

    # Poll invalidation status with AWS CLI instead of timeout
    MAX_ATTEMPTS=60  # 5 minutes with 5-second intervals
    ATTEMPT=0

    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        STATUS=$(aws --profile "$AWS_PROFILE" cloudfront get-invalidation \
            --distribution-id "$DISTRIBUTION_ID" \
            --id "$INVALIDATION_ID" \
            --query 'Invalidation.Status' \
            --output text 2>/dev/null || echo "InProgress")

        if [ "$STATUS" = "Completed" ]; then
            log_success "Cache invalidation completed"
            break
        elif [ $ATTEMPT -eq $((MAX_ATTEMPTS - 1)) ]; then
            log_warn "Invalidation still in progress after 5 minutes"
            log_info "Your changes are deploying - check CloudFront console for status"
            break
        else
            sleep 5
            ATTEMPT=$((ATTEMPT + 1))
        fi
    done
else
    log_error "Failed to create cache invalidation"
    exit 1
fi

# Get final CloudFront URL
CLOUDFRONT_URL=$(get_cloudfront_distribution_url)

log_summary "UPDATE COMPLETE!"
log_info "Updated script.js with API Gateway URL"
log_info "Re-uploaded static files to S3"
log_info "Selectively invalidated CloudFront cache (HTML + JS only)"

log_success "Access your application: https://$CLOUDFRONT_URL"
log_warn "Cache propagation may take 2-5 minutes"
