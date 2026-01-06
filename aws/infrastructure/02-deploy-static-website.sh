#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

# Optional dry-run mode (no changes made)
DRY_RUN="${DRY_RUN:-false}"

log_section "Static Website Deployment"

############################################
# Preflight checks
############################################

# Validate PROJECT_ROOT
if [[ -z "${PROJECT_ROOT:-}" ]]; then
  log_error "PROJECT_ROOT is not set. Check 00-config.sh"
  exit 1
fi

STATIC_WEB_DIR="$PROJECT_ROOT/aws/static-web"

log_info "Verifying static web directory exists..."
if [[ ! -d "$STATIC_WEB_DIR" ]]; then
  log_error "Static web directory not found: $STATIC_WEB_DIR"
  exit 1
fi

log_info "Verifying S3 bucket exists..."
if ! aws s3api head-bucket --bucket "$STATIC_BUCKET" > /dev/null 2>/dev/null; then
  log_error "Bucket $STATIC_BUCKET does not exist. Run 01-create-s3-buckets.sh first."
  exit 1
fi
echo ""

############################################
# Deployment context (UX clarity)
############################################

log_info "Deployment context:"
log_info "  Source directory : ${BLUE}$STATIC_WEB_DIR${NC}"
log_info "  Target bucket    : ${BLUE}s3://$STATIC_BUCKET/${NC}"
log_info "  AWS region       : ${YELLOW}$REGION"${NC}
log_info "  DRY_RUN mode     : ${GREEN}$DRY_RUN${NC}"
echo ""

############################################
# Optional integrity logging
############################################

FILE_COUNT=$(find "$STATIC_WEB_DIR" -type f | wc -l | tr -d ' ')
log_info "Preparing to deploy ${GREEN}$FILE_COUNT static files${NC}"

############################################
# S3 sync (bulk assets)
############################################

SYNC_FLAGS=(
  --delete
  --cache-control "max-age=86400"
  --region "$REGION"
  --profile "$AWS_PROFILE"
)

if [[ "$DRY_RUN" == "true" ]]; then
  SYNC_FLAGS+=(--dryrun)
  log_warn "DRY_RUN enabled — no files will be uploaded or deleted"
fi

log_info "Syncing static assets to S3..."
aws s3 sync "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" "${SYNC_FLAGS[@]}"
echo ""

############################################
# Explicit content-type handling
############################################

log_info "Applying explicit content types..."

# HTML (short cache)
if [[ -f "$STATIC_WEB_DIR/index.html" ]]; then
  aws s3 cp "$STATIC_WEB_DIR/index.html" "s3://$STATIC_BUCKET/index.html" \
    --cache-control "max-age=300" \
    --content-type "text/html" \
    --region "$REGION" \
    ${DRY_RUN:+--dryrun}
fi

# JavaScript
aws s3 cp "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
  --recursive \
  --exclude "*" \
  --include "*.js" \
  --content-type "application/javascript" \
  --cache-control "max-age=86400" \
  --region "$REGION" \
  ${DRY_RUN:+--dryrun}

# CSS
aws s3 cp "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
  --recursive \
  --exclude "*" \
  --include "*.css" \
  --content-type "text/css" \
  --cache-control "max-age=86400" \
  --region "$REGION" \
  ${DRY_RUN:+--dryrun}
echo ""

############################################
# Completion
############################################

log_success "Static website deployment completed successfully!"
log_info "Files deployed to: ${BLUE}s3://$STATIC_BUCKET/${NC}"

if [[ "$DRY_RUN" == "true" ]]; then
  log_warn "DRY_RUN was enabled — no actual changes were made"
fi
echo ""

log_warn "Website is accessible only via CloudFront distribution (private bucket)"
log_warn ${CYAN}OPTIONAL:${NC} "Update ${GREEN}API_GATEWAY_URL${NC} in ${GREEN}script.js${NC} with your actual API Gateway endpoint"

log_summary "Static website deployment completed! ${CYAN}Next:${NC} Run 03-create-cloudfront.sh"
