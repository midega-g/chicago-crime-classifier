#!/usr/bin/env bash

set -euo pipefail

# -------------------------------------------------------------------
# Load shared configuration and helpers
# -------------------------------------------------------------------
source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

# -------------------------------------------------------------------
# Preflight checks
# -------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || {
  log_error "jq is required but not installed. Please install jq and retry."
  exit 1
}

log_section "API Gateway Setup"

# -------------------------------------------------------------------
# Check if API Gateway already exists
# -------------------------------------------------------------------
log_info "Checking for existing API Gateway..."

EXISTING_API_ID=$(aws --profile "$AWS_PROFILE" apigateway get-rest-apis \
  --query "items[?name=='$API_NAME'].id | [0]" \
  --output text 2>/dev/null || echo "")

if [[ -n "$EXISTING_API_ID" && "$EXISTING_API_ID" != "None" ]]; then
    API_ID="$EXISTING_API_ID"
    log_warn "API Gateway already exists: ${YELLOW}$API_ID${NC}"
    log_info "API Endpoint: ${BLUE}https://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE_NAME${NC}"
    log_summary "Using existing API Gateway ${CYAN}Next:${NC} Run 05-create-dynamodb.sh"
    exit 0
fi

# -------------------------------------------------------------------
# Step 1: Create REST API
# -------------------------------------------------------------------
log_info "Creating REST API..."

API_RESPONSE=$(aws --profile "$AWS_PROFILE" apigateway create-rest-api \
    --name "$API_NAME" \
    --description "Chicago Crimes ML API with proxy integration")

API_ID=$(echo "$API_RESPONSE" | jq -r '.id')
log_success "Created API with ID: ${YELLOW}$API_ID${NC}"
echo ""

# -------------------------------------------------------------------
# Step 2: Get root resource ID
# -------------------------------------------------------------------
log_info "Getting root resource..."

RESOURCES_RESPONSE=$(aws --profile "$AWS_PROFILE" apigateway get-resources \
    --rest-api-id "$API_ID")

ROOT_RESOURCE_ID=$(echo "$RESOURCES_RESPONSE" | jq -r '.items[] | select(.path=="/") | .id')

if [[ -z "$ROOT_RESOURCE_ID" || "$ROOT_RESOURCE_ID" == "null" ]]; then
    ROOT_RESOURCE_ID=$(echo "$RESOURCES_RESPONSE" | jq -r '.items[0].id')
    log_warn "Using first resource as root: ${YELLOW}$ROOT_RESOURCE_ID${NC}"
else
    log_info "Root resource ID: ${YELLOW}$ROOT_RESOURCE_ID${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Step 3: Create proxy resource {proxy+}
# -------------------------------------------------------------------
log_info "Creating proxy resource {proxy+}..."

EXISTING_PROXY_ID=$(echo "$RESOURCES_RESPONSE" | jq -r '.items[] | select(.pathPart=="{proxy+}") | .id' 2>/dev/null || echo "")

if [[ -n "$EXISTING_PROXY_ID" && "$EXISTING_PROXY_ID" != "null" ]]; then
    PROXY_RESOURCE_ID="$EXISTING_PROXY_ID"
    log_info "Proxy resource already exists: ${YELLOW}$PROXY_RESOURCE_ID${YELLOW}"
else
    PROXY_RESOURCE_RESPONSE=$(aws --profile "$AWS_PROFILE" apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$ROOT_RESOURCE_ID" \
        --path-part "{proxy+}")

    PROXY_RESOURCE_ID=$(echo "$PROXY_RESOURCE_RESPONSE" | jq -r '.id')
    log_success "Created proxy resource: ${YELLOW}$PROXY_RESOURCE_ID${NC}"
fi
echo ""

# -------------------------------------------------------------------
# IMPORTANT NOTE FOR FUTURE READERS
# -------------------------------------------------------------------
# At this stage, methods are created WITHOUT backend integrations.
# Until a Lambda integration is attached, requests to this API WILL
# return HTTP 500 errors. This is expected behavior and will be
# resolved in the Lambda deployment step.
# -------------------------------------------------------------------

# -------------------------------------------------------------------
# Step 4: Create ANY method for root (/)
# -------------------------------------------------------------------
log_info "Creating ANY method for root resource '/'..."

if aws --profile "$AWS_PROFILE" apigateway put-method \
    --rest-api-id "$API_ID" \
    --resource-id "$ROOT_RESOURCE_ID" \
    --http-method ANY \
    --authorization-type NONE >/dev/null 2>&1; then
    log_success "${YELLOW}ANY${NC} method created on root resource"
else
    log_warn "${YELLOW}ANY${NC} method on root already exists"
fi
echo ""

# -------------------------------------------------------------------
# Step 5: Create ANY method for proxy resource
# -------------------------------------------------------------------
log_info "Creating ANY method for proxy resource..."

if aws --profile "$AWS_PROFILE" apigateway put-method \
    --rest-api-id "$API_ID" \
    --resource-id "$PROXY_RESOURCE_ID" \
    --http-method ANY \
    --authorization-type NONE \
    --request-parameters '{"method.request.path.proxy":true}' >/dev/null 2>&1; then
    log_success "${YELLOW}ANY${NC} method created on proxy resource"
else
    log_warn "${YELLOW}ANY${NC} method on proxy already exists"
fi
echo ""

# -------------------------------------------------------------------
# Step 6: Deploy API
# -------------------------------------------------------------------
# log_info "Deploying API to stage: $STAGE_NAME..."

# if aws --profile "$AWS_PROFILE" apigateway create-deployment \
#     --rest-api-id "$API_ID" \
#     --stage-name "$STAGE_NAME" >/dev/null 2>&1; then
#     log_success "API deployed successfully"
# else
#     log_warn "API deployment failed"
# fi

# -------------------------------------------------------------------
# Final output
# -------------------------------------------------------------------
log_success "API Gateway created successfully!"
log_info "API ID: ${YELLOW}$API_ID${NC}"
log_info "API Endpoint: ${YELLOW}https://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE_NAME${NC}"
log_info "Root resource ID: ${YELLOW}$ROOT_RESOURCE_ID${NC}"
log_info "Proxy resource ID: ${YELLOW}$PROXY_RESOURCE_ID${NC}"

log_warn "Requests will return ${RED}HTTP 500${NC} until Lambda integration is configured"

log_summary "API Gateway setup completed! ${CYAN}Next:${NC} Run 05-create-dynamodb.sh"
