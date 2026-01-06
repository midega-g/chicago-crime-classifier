#!/usr/bin/env bash

set -euo pipefail

# -------------------------------------------------------------------
# Load shared configuration and helpers
# -------------------------------------------------------------------
source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

log_section "ECR Repository Setup"

# -------------------------------------------------------------------
# Check if ECR repository already exists
# -------------------------------------------------------------------
log_info "Checking for existing ECR repository..."

REPO_URI=$(aws --profile "$AWS_PROFILE" ecr describe-repositories \
  --repository-names "$ECR_REPO" \
  --query 'repositories[0].repositoryUri' \
  --output text 2>/dev/null || echo "")

if [[ -n "$REPO_URI" && "$REPO_URI" != "None" ]]; then
    log_warn "ECR repository already exists: ${YELLOW}$REPO_URI${NC}"
    log_summary "Using existing ECR repository ${CYAN}Next:${NC} Run 07-build-push-docker.sh"
    exit 0
fi
echo ""

log_info "Creating new ECR repository..."

# -------------------------------------------------------------------
# Create ECR repository
# -------------------------------------------------------------------
log_info "Creating ECR repository: $ECR_REPO"

aws --profile "$AWS_PROFILE" \
    --region "$REGION" \
    ecr create-repository \
    --repository-name "$ECR_REPO" \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability MUTABLE >/dev/null 2>&1;


REPO_URI=$(get_ecr_repo_uri)

log_success "ECR repository created: ${YELLOW}$REPO_URI${NC}"
echo ""

# -------------------------------------------------------------------
# Final output
# -------------------------------------------------------------------
log_success "ECR repository setup completed!"
log_info "Repository URI: ${YELLOW}$REPO_URI${NC}"
log_info "Repository Name: ${YELLOW}$ECR_REPO${NC}"

log_summary "ECR repository ready for Docker images! ${CYAN}Next:${NC} Run 07-build-push-docker.sh"

# # Lifecycle rule: keep only images tagged 'latest' + last 5 tagged images + delete rest after 7 days
# aws ecr put-lifecycle-policy \
#   --repository-name "$ECR_REPO" \
#   --profile "$AWS_PROFILE" \
#   --lifecycle-policy-text '{
#     "rules": [
#       {
#         "rulePriority": 1,
#         "description": "Keep only latest tag + last 5 tagged images, expire rest after 7 days",
#         "selection": {
#           "tagStatus": "tagged",
#           "tagPatternList": ["latest"],
#           "countType": "imageCountMoreThan",
#           "countNumber": 1
#         },
#         "action": { "type": "expire" }
#       },
#       {
#         "rulePriority": 2,
#         "description": "Keep last 5 tagged images",
#         "selection": {
#           "tagStatus": "tagged",
#           "tagPatternList": ["*"],
#           "countType": "imageCountMoreThan",
#           "countNumber": 5
#         },
#         "action": { "type": "expire" }
#       },
#       {
#         "rulePriority": 3,
#         "description": "Expire all images older than 7 days (safety net)",
#         "selection": {
#           "tagStatus": "any",
#           "countType": "sinceImagePushed",
#           "countUnit": "days",
#           "countNumber": 7
#         },
#         "action": { "type": "expire" }
#       }
#     ]
#   }' >/dev/null 2>&1

# log_success "Lifecycle policy applied to ECR repository: $ECR_REPO"
