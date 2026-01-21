# Static Website Deployment

The `02-deploy-static-website.sh` script handles the deployment of frontend assets to Amazon S3 with sophisticated caching strategies and content-type management. The script implements a multi-stage deployment approach that optimizes browser caching while ensuring critical files like HTML and JSON remain fresh for immediate updates.

The script is designed to work with private S3 buckets that will be accessed through CloudFront, implementing cache-control headers that optimize both performance and update propagation across the CDN infrastructure.

## Loading Shared Configuration and Enforcing Safe Execution

The script begins by enabling strict Bash execution modes and loading shared configuration.

```bash
set -euo pipefail

source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}
```

The `set -euo pipefail` directive ensures that the script exits immediately if any command fails, if an undefined variable is used, or if a pipeline command fails silently. This prevents partial deployments that could leave the website in an inconsistent state.

Sourcing `00-config.sh` provides access to centralized configuration including bucket names, AWS credentials, and logging utilities. The error handling ensures the script cannot proceed without proper configuration.

## Dry-Run Mode Support

The script supports non-destructive testing through an optional dry-run mode.

```bash
DRY_RUN="${DRY_RUN:-false}"
```

When `DRY_RUN=true` is set, all AWS operations are executed in simulation mode, showing what would be changed without actually uploading or deleting files. This is particularly valuable for CI/CD pipelines and testing deployment changes.

## Comprehensive Preflight Validation

Before any deployment operations, the script performs thorough validation of prerequisites.

### Project Root Validation

```bash
if [[ -z "${PROJECT_ROOT:-}" ]]; then
  log_error "PROJECT_ROOT is not set. Check 00-config.sh"
  exit 1
fi
```

The `[[ -z "${PROJECT_ROOT:-}" ]]` test checks if the PROJECT_ROOT variable is unset or empty. The `:-` parameter expansion provides an empty string as a fallback if the variable is unset, preventing the `-u` flag from causing script termination during the test itself.

### Static Web Directory Validation

```bash
STATIC_WEB_DIR="$PROJECT_ROOT/aws/static-web"

if [[ ! -d "$STATIC_WEB_DIR" ]]; then
  log_error "Static web directory not found: $STATIC_WEB_DIR"
  exit 1
fi
```

The `[[ ! -d "$STATIC_WEB_DIR" ]]` test verifies that the source directory exists and is actually a directory. This prevents attempting to deploy from a non-existent or invalid source location.

### S3 Bucket Existence Verification

```bash
if ! aws s3api head-bucket --bucket "$STATIC_BUCKET" 2>/dev/null; then
  log_error "Bucket $STATIC_BUCKET does not exist. Run 01-create-s3-buckets.sh first."
  exit 1
fi
```

The `aws s3api head-bucket` command checks bucket existence without listing contents:

- `--bucket "$STATIC_BUCKET"` - Specifies the target bucket from configuration
- `2>/dev/null` - Suppresses error output for cleaner script execution
- The `!` operator inverts the exit code, so the condition triggers if the bucket doesn't exist

### File Count Validation

```bash
FILE_COUNT=$(find "$STATIC_WEB_DIR" -type f | wc -l | tr -d ' ')
if [[ "$FILE_COUNT" -eq 0 ]]; then
  log_error "No files found in $STATIC_WEB_DIR"
  exit 1
fi
```

This validation ensures there are actually files to deploy:

- `find "$STATIC_WEB_DIR" -type f` - Finds all regular files in the directory
- `wc -l` - Counts the number of lines (files)
- `tr -d ' '` - Removes any whitespace from the count
- The numeric comparison `[[ "$FILE_COUNT" -eq 0 ]]` checks for empty directories

## Deployment Context Logging

The script provides comprehensive deployment context for operational transparency.

```bash
log_info "Deployment context:"
log_info "  Source directory : ${BLUE}$STATIC_WEB_DIR${NC}"
log_info "  Target bucket    : ${BLUE}s3://$STATIC_BUCKET/${NC}"
log_info "  AWS region       : ${YELLOW}$REGION${NC}"
log_info "  AWS profile      : ${YELLOW}$AWS_PROFILE${NC}"
log_info "  DRY_RUN mode     : ${GREEN}$DRY_RUN${NC}"
log_info "  Files to deploy  : ${GREEN}$FILE_COUNT${NC}"
```

This context logging helps with:

- Debugging deployment issues by showing exact source and target locations
- Verifying correct AWS profile and region usage
- Confirming dry-run mode status before execution
- Providing file count as a sanity check

## Multi-Stage S3 Sync Strategy

The deployment uses a sophisticated multi-stage approach to optimize caching behavior for different file types.

### Sync Flags Configuration

```bash
SYNC_FLAGS=(
  --delete
  --profile "$AWS_PROFILE"
  --region "$REGION"
)

if [[ "$DRY_RUN" == "true" ]]; then
  SYNC_FLAGS+=(--dryrun)
fi
```

The sync flags array provides consistent configuration across all sync operations:

- `--delete` - Removes files from S3 that no longer exist locally, maintaining exact synchronization
- `--profile "$AWS_PROFILE"` - Specifies the AWS CLI profile for authentication
- `--region "$REGION"` - Ensures operations target the correct AWS region
- `--dryrun` - Added conditionally for simulation mode

### Stage 1: Static Assets with Long-Term Caching

```bash
aws s3 sync "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
  "${SYNC_FLAGS[@]}" \
  --cache-control "max-age=31536000, immutable" \
  --exclude "*.html" \
  --exclude "*.json"
```

This first sync handles static assets (CSS, JS, images) with aggressive caching:

- `"$STATIC_WEB_DIR/"` - Source directory with trailing slash for proper sync behavior
- `"s3://$STATIC_BUCKET/"` - Target S3 bucket with trailing slash
- `"${SYNC_FLAGS[@]}"` - Expands the flags array as separate arguments
- `--cache-control "max-age=31536000, immutable"` - Sets 1-year cache with immutable flag
- `--exclude "*.html"` and `--exclude "*.json"` - Excludes files that need different caching

The `immutable` directive tells browsers and CDNs that these files will never change, enabling maximum caching efficiency.

### Stage 2: HTML Files with No-Cache Policy

```bash
if compgen -G "$STATIC_WEB_DIR/*.html" > /dev/null; then
  aws s3 sync "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
    "${SYNC_FLAGS[@]}" \
    --cache-control "no-cache, no-store, must-revalidate" \
    --content-type "text/html" \
    --exclude "*" \
    --include "*.html"
fi
```

HTML files receive special treatment for immediate updates:

- `compgen -G "$STATIC_WEB_DIR/*.html" > /dev/null` - Tests if HTML files exist before processing
- `--cache-control "no-cache, no-store, must-revalidate"` - Prevents all caching
- `--content-type "text/html"` - Explicitly sets MIME type
- `--exclude "*" --include "*.html"` - Processes only HTML files

The no-cache policy ensures that HTML changes are immediately visible to users.

### Stage 3: JSON Files with No-Cache Policy

```bash
if compgen -G "$STATIC_WEB_DIR/*.json" > /dev/null; then
  aws s3 sync "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
    "${SYNC_FLAGS[@]}" \
    --cache-control "no-cache, no-store, must-revalidate" \
    --content-type "application/json" \
    --exclude "*" \
    --include "*.json"
fi
```

JSON files (likely configuration files) also receive no-cache treatment to ensure configuration changes take effect immediately.

## Explicit Content-Type Corrections

The script performs additional passes to ensure correct MIME types for specific file categories.

### JavaScript Files

```bash
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
```

JavaScript files receive explicit content-type handling:

- `aws s3 cp` with `--recursive` - Copies files recursively
- `--exclude "*" --include "*.js"` - Processes only JavaScript files
- `--content-type "application/javascript"` - Sets correct MIME type
- `${DRY_RUN:+--dryrun}` - Conditional parameter expansion adds `--dryrun` only if DRY_RUN is set
- `>/dev/null` - Suppresses verbose output

### CSS Files

```bash
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
```

CSS files receive similar treatment with the appropriate `text/css` MIME type.

## Deployment Verification

For non-dry-run deployments, the script verifies successful upload.

```bash
if [[ "$DRY_RUN" == "false" ]]; then
  UPLOADED_COUNT=$(aws s3 ls "s3://$STATIC_BUCKET/" --recursive --profile "$AWS_PROFILE" | wc -l | tr -d ' ')
  
  if [[ "$UPLOADED_COUNT" -gt 0 ]]; then
    log_success "Deployment verified: $UPLOADED_COUNT files in bucket"
  else
    log_warn "Warning: Bucket appears empty after deployment"
  fi
fi
```

The verification process:

- `aws s3 ls "s3://$STATIC_BUCKET/" --recursive` - Lists all objects in the bucket
- `wc -l | tr -d ' '` - Counts files and removes whitespace
- Compares the count to ensure files were actually uploaded

## Completion Summary and Operational Guidance

The script concludes with comprehensive operational information.

```bash
log_success "Static website deployment completed successfully!"
log_info "Files deployed to: ${BLUE}s3://$STATIC_BUCKET/${NC}"

if [[ "$DRY_RUN" == "true" ]]; then
  log_warn "DRY_RUN was enabled — no actual changes were made"
  log_info "Run without DRY_RUN=true to perform actual deployment"
fi

log_info "${CYAN}Cache Strategy:${NC}"
log_info "  • Static assets (JS/CSS/images): 1 year cache (immutable)"
log_info "  • HTML/JSON files: no-cache (always fresh)"

log_warn "Website is accessible only via CloudFront distribution (private bucket)"
log_info "${CYAN}Optional:${NC} Update ${GREEN}API_GATEWAY_URL${NC} in ${GREEN}script.js${NC} with your actual API Gateway endpoint"
```

The completion summary provides:

- Clear confirmation of deployment success
- Reminder about dry-run mode if applicable
- Documentation of the caching strategy implemented
- Important architectural notes about CloudFront access
- Guidance for next configuration steps

## How to Run the Script

To execute a standard deployment:

```bash
./02-deploy-static-website.sh
```

To simulate deployment without making changes:

```bash
DRY_RUN=true ./02-deploy-static-website.sh
```

The script's idempotent design allows safe re-execution, and the multi-stage caching strategy ensures optimal performance while maintaining the ability to push immediate updates when needed.
