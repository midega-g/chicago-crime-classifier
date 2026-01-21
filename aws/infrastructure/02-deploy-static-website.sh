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
if ! aws s3api head-bucket --bucket "$STATIC_BUCKET" 2>/dev/null; then
  log_error "Bucket $STATIC_BUCKET does not exist. Run 01-create-s3-buckets.sh first."
  exit 1
fi

FILE_COUNT=$(find "$STATIC_WEB_DIR" -type f | wc -l | tr -d ' ')
if [[ "$FILE_COUNT" -eq 0 ]]; then
  log_error "No files found in $STATIC_WEB_DIR"
  exit 1
fi

echo ""

############################################
# Deployment context
############################################

log_info "Deployment context:"
log_info "  Source directory : ${BLUE}$STATIC_WEB_DIR${NC}"
log_info "  Target bucket    : ${BLUE}s3://$STATIC_BUCKET/${NC}"
log_info "  AWS region       : ${YELLOW}$REGION${NC}"
log_info "  AWS profile      : ${YELLOW}$AWS_PROFILE${NC}"
log_info "  DRY_RUN mode     : ${GREEN}$DRY_RUN${NC}"
log_info "  Files to deploy  : ${GREEN}$FILE_COUNT${NC}"
echo ""

############################################
# S3 sync strategy
############################################

log_info "Syncing static assets to S3..."

SYNC_FLAGS=(
  --delete
  --profile "$AWS_PROFILE"
  --region "$REGION"
)

if [[ "$DRY_RUN" == "true" ]]; then
  SYNC_FLAGS+=(--dryrun)
  log_warn "DRY_RUN enabled — no files will be uploaded or deleted"
fi

# Sync all files with default cache settings first
aws s3 sync "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
  "${SYNC_FLAGS[@]}" \
  --cache-control "max-age=31536000, immutable" \
  --exclude "*.html" \
  --exclude "*.json"

# Sync HTML files with short cache (always check for updates)
if compgen -G "$STATIC_WEB_DIR/*.html" > /dev/null; then
  log_info "Syncing HTML files with no-cache policy..."
  aws s3 sync "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
    "${SYNC_FLAGS[@]}" \
    --cache-control "no-cache, no-store, must-revalidate" \
    --content-type "text/html" \
    --exclude "*" \
    --include "*.html"
fi

# Sync JSON files with short cache
if compgen -G "$STATIC_WEB_DIR/*.json" > /dev/null; then
  log_info "Syncing JSON files with no-cache policy..."
  aws s3 sync "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
    "${SYNC_FLAGS[@]}" \
    --cache-control "no-cache, no-store, must-revalidate" \
    --content-type "application/json" \
    --exclude "*" \
    --include "*.json"
fi

echo ""

############################################
# Explicit content-type corrections
############################################

log_info "Ensuring correct content types for specific file types..."

# JavaScript files
if compgen -G "$STATIC_WEB_DIR/*.js" > /dev/null; then
  aws s3 cp "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
    --recursive \
    --exclude "*" \
    --include "*.js" \
    --content-type "application/javascript" \
    --cache-control "max-age=31536000, immutable" \
    --profile "$AWS_PROFILE" \
    --region "$REGION" \
    ${DRY_RUN:+--dryrun} \
    >/dev/null
fi

# CSS files
if compgen -G "$STATIC_WEB_DIR/*.css" > /dev/null; then
  aws s3 cp "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
    --recursive \
    --exclude "*" \
    --include "*.css" \
    --content-type "text/css" \
    --cache-control "max-age=31536000, immutable" \
    --profile "$AWS_PROFILE" \
    --region "$REGION" \
    ${DRY_RUN:+--dryrun} \
    >/dev/null
fi

echo ""

############################################
# Deployment verification
############################################

if [[ "$DRY_RUN" == "false" ]]; then
  log_info "Verifying deployment..."
  
  UPLOADED_COUNT=$(aws s3 ls "s3://$STATIC_BUCKET/" --recursive --profile "$AWS_PROFILE" | wc -l | tr -d ' ')
  
  if [[ "$UPLOADED_COUNT" -gt 0 ]]; then
    log_success "Deployment verified: $UPLOADED_COUNT files in bucket"
  else
    log_warn "Warning: Bucket appears empty after deployment"
  fi
fi

echo ""

############################################
# Completion
############################################

log_success "Static website deployment completed successfully!"
log_info "Files deployed to: ${BLUE}s3://$STATIC_BUCKET/${NC}"

if [[ "$DRY_RUN" == "true" ]]; then
  log_warn "DRY_RUN was enabled — no actual changes were made"
  log_info "Run without DRY_RUN=true to perform actual deployment"
fi

echo ""
log_info "${CYAN}Cache Strategy:${NC}"
log_info "  • Static assets (JS/CSS/images): 1 year cache (immutable)"
log_info "  • HTML/JSON files: no-cache (always fresh)"
echo ""

log_warn "Website is accessible only via CloudFront distribution (private bucket)"
log_info "${CYAN}Optional:${NC} Update ${GREEN}API_GATEWAY_URL${NC} in ${GREEN}script.js${NC} with your actual API Gateway endpoint"

log_summary "Static website deployment completed! ${CYAN}Next:${NC} Run 03-create-cloudfront.sh"