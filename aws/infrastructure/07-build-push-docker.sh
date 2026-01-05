#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/00-config.sh" || { echo "Failed to load config" >&2; exit 1; }

# ────────────────────────────────────────────────────────────────────────────────
# Preflight checks
# ────────────────────────────────────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || { log_error "Docker is required"; exit 1; }

log_section "Docker Build and Push"

# ────────────────────────────────────────────────────────────────────────────────
# Get ECR repository URI (registry hostname + repo name)
# ────────────────────────────────────────────────────────────────────────────────
log_info "Getting ECR repository information..."

REPO_URI=$(get_ecr_repo_uri)

if [[ -z "$REPO_URI" || "$REPO_URI" == "None" ]]; then
    log_error "ECR repository not found. Create it first."
    exit 1
fi

# Registry hostname only - very important for credential stability
REGISTRY_HOST="${REPO_URI%%/*}"   # removes everything after first /

log_info "Target registry: ${REGISTRY_HOST}"
log_info "Full repository:  ${REPO_URI}"

# ────────────────────────────────────────────────────────────────────────────────
# Optional: skip build if image already exists (and SKIP_BUILD is set)
# this option allows you to run the script as:
#       SKIP_BUILD=1 ./07-build-push-docker.sh
# ────────────────────────────────────────────────────────────────────────────────
CURRENT_DIGEST=$(aws ecr describe-images \
    --repository-name "$ECR_REPO" \
    --image-ids imageTag="$IMAGE_TAG" \
    --query 'imageDetails[0].imageDigest' \
    --output text 2>/dev/null || echo "None")

if [[ "$CURRENT_DIGEST" != "None" && -n "${SKIP_BUILD:-}" ]]; then
    log_success "Image $IMAGE_TAG already exists - skipping build"
    log_info "URI: $REPO_URI:$IMAGE_TAG"
    exit 0
fi

# ────────────────────────────────────────────────────────────────────────────────
# Build phase
# ────────────────────────────────────────────────────────────────────────────────
log_info "Building Docker image..."

cd "$(dirname "$0")/../.."

for attempt in {1..2}; do
    log_info "Build attempt $attempt/2..."
    if DOCKER_BUILDKIT=1 docker buildx build \
        --platform linux/amd64 \
        -f aws/lambda/Dockerfile \
        -t "$ECR_REPO" .; then
        log_success "Build successful"
        break
    fi
    [[ $attempt -eq 2 ]] && { log_error "Build failed after 2 attempts"; exit 1; }
    sleep 10
done

# ────────────────────────────────────────────────────────────────────────────────
# Tag image
# ────────────────────────────────────────────────────────────────────────────────
log_info "Tagging image..."
docker tag "$ECR_REPO:latest" "$REPO_URI:$IMAGE_TAG"
log_success "Tagged: $REPO_URI:$IMAGE_TAG"

# ────────────────────────────────────────────────────────────────────────────────
# Critical: Authenticate RIGHT BEFORE PUSH
# ────────────────────────────────────────────────────────────────────────────────
log_info "Authenticating with ECR (right before push)..."

# Get fresh token
token=$(aws ecr get-login-password --region "$REGION" --profile "$AWS_PROFILE") \
    || { log_error "Failed to get ECR token"; exit 1; }

echo "$token" | docker login --username AWS --password-stdin "$REGISTRY_HOST" \
    || { log_error "ECR login failed"; exit 1; }

log_success "ECR authentication completed"

# Small delay - helps some credential helpers to settle
sleep 2

# ────────────────────────────────────────────────────────────────────────────────
# Push with retry
# ────────────────────────────────────────────────────────────────────────────────

# Pre-push diagnostics
log_info "=== Pre-push Diagnostics ==="
log_info "Image size: $(docker images "$REPO_URI:$IMAGE_TAG" --format "{{.Size}}")"
log_info "Layer count: $(docker history "$REPO_URI:$IMAGE_TAG" | tail -n +2 | wc -l)"

for attempt in {1..2}; do
    log_info "Push attempt $attempt/2..."

    # Re-auth before each serious push attempt (paranoid but effective)
    if [[ $attempt -gt 1 ]]; then
        log_info "Refreshing ECR token..."
        token=$(aws ecr get-login-password --region "$REGION" --profile "$AWS_PROFILE")
        echo "$token" | docker login --username AWS --password-stdin "$REGISTRY_HOST"
        sleep 2
    fi

    # Increase timeout based on your condition
    # or run restart docker
    if timeout 1500 docker push "$REPO_URI:$IMAGE_TAG"; then
        log_success "Push successful"
        break
    fi

    log_warn "Push attempt $attempt failed"
    [[ $attempt -eq 3 ]] && { log_error "Failed to push after 2 attempts"; exit 1; }
done

# ────────────────────────────────────────────────────────────────────────────────
# Optional: Clean up untagged images
# ────────────────────────────────────────────────────────────────────────────────

log_info "Cleaning up old ECR images..."

OLD_IMAGES=$(aws ecr list-images \
  --repository-name "$ECR_REPO" \
  --filter tagStatus=UNTAGGED \
  --query 'imageIds[?imageDigest!=null]' \
  --profile "$AWS_PROFILE" \
  --output json 2>/dev/null || echo '[]')

if [[ "$OLD_IMAGES" != "[]" && -n "$OLD_IMAGES" ]]; then
    if aws ecr batch-delete-image \
        --repository-name "$ECR_REPO" \
        --image-ids "$OLD_IMAGES" \
        --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_success "Old untagged images cleaned up"
    else
        log_warn "Failed to clean up old images"
    fi
else
    log_info "No old images to clean up"
fi

# ────────────────────────────────────────────────────────────────────────────────
# Final verification
# ────────────────────────────────────────────────────────────────────────────────

log_info "Verifying image in ECR..."
if [[ -n "$(verify_ecr_image_exists)" ]]; then
    log_success "Image ${ECR_REPO}:${IMAGE_TAG} exists in ECR"
else
    log_error "Image not found in ECR after push"
    exit 1
fi

log_success "Docker build and push completed!"
log_info "Image ready: ${YELLOW}$REPO_URI:$IMAGE_TAG${NC}"
echo -e "${CYAN}Next:${NC} Run 08-create-lambda-role.sh"
