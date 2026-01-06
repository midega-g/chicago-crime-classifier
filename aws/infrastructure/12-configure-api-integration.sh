#!/usr/bin/env bash

set -euo pipefail

# -------------------------------------------------------------------
# Load shared configuration and helpers
# -------------------------------------------------------------------
source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

log_section "API Gateway Lambda Integration"

# -------------------------------------------------------------------
# Get API Gateway ID
# -------------------------------------------------------------------
log_info "Finding API Gateway..."

API_ID=$(get_api_gateway_id)

if [[ -z "$API_ID" || "$API_ID" == "None" ]]; then
    log_error "API Gateway not found. Run 04-create-api-gateway.sh first."
    exit 1
fi

log_success "Found API Gateway: ${YELLOW}$API_ID${NC}"
echo ""

# -------------------------------------------------------------------
# Get root resource ID for root method integration
# -------------------------------------------------------------------
log_info "Finding root resource..."

ROOT_RESOURCE_ID=$(aws --profile "$AWS_PROFILE" apigateway get-resources \
  --rest-api-id "$API_ID" \
  --query "items[?path=='/'].id | [0]" \
  --output text 2>/dev/null || echo "")

if [[ -z "$ROOT_RESOURCE_ID" || "$ROOT_RESOURCE_ID" == "None" ]]; then
    log_error "Root resource not found."
    exit 1
fi

log_success "Found root resource: ${YELLOW}$ROOT_RESOURCE_ID${NC}"
echo ""

# -------------------------------------------------------------------
# Get proxy resource ID
# -------------------------------------------------------------------
log_info "Finding proxy resource..."

PROXY_RESOURCE_ID=$(aws --profile "$AWS_PROFILE" apigateway get-resources \
  --rest-api-id "$API_ID" \
  --query "items[?pathPart=='{proxy+}'].id | [0]" \
  --output text 2>/dev/null || echo "")

if [[ -z "$PROXY_RESOURCE_ID" || "$PROXY_RESOURCE_ID" == "None" ]]; then
    log_error "Proxy resource not found. Run 04-create-api-gateway.sh first."
    exit 1
fi

log_success "Found proxy resource: ${YELLOW}$PROXY_RESOURCE_ID${NC}"
echo ""

# -------------------------------------------------------------------
# Configure Lambda integration for root resource
# -------------------------------------------------------------------
log_info "Configuring Lambda integration for root resource..."

LAMBDA_ARN="$(get_lambda_function_arn)"
if [ -z "$LAMBDA_ARN" ]; then
    log_error "Failed to get Lambda ARN"
    exit 1
fi

INTEGRATION_URI="arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations"

ROOT_INTEGRATION_RESULT=""
if ROOT_INTEGRATION_RESULT=$(
    aws --profile "$AWS_PROFILE" apigateway put-integration \
    --rest-api-id "$API_ID" \
    --resource-id "$ROOT_RESOURCE_ID" \
    --http-method ANY \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "$INTEGRATION_URI" 2>&1); then
    log_success "Root Lambda integration configured"
elif echo "$ROOT_INTEGRATION_RESULT" | grep -Eqi "Conflict|Already|exists|409"; then
    log_info "Root integration already exists"
else
    log_error "Root integration failed"
    echo "${RED}$ROOT_INTEGRATION_RESULT${NC}" >&2
    exit 1
fi
echo ""

# -------------------------------------------------------------------
# Configure Lambda integration for proxy resource
# -------------------------------------------------------------------
log_info "Configuring Lambda integration for proxy resource..."

PROXY_INTEGRATION_RESULT=""
if PROXY_INTEGRATION_RESULT=$(
    aws --profile "$AWS_PROFILE" apigateway put-integration \
    --rest-api-id "$API_ID" \
    --resource-id "$PROXY_RESOURCE_ID" \
    --http-method ANY \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "$INTEGRATION_URI" 2>&1); then
    log_success "Proxy Lambda integration configured"
elif echo "$PROXY_INTEGRATION_RESULT" | grep -Eqi "Conflict|Already|exists|409"; then
    log_info "Proxy integration already exists"
else
    log_error "Proxy integration failed"
    echo "${RED}$PROXY_INTEGRATION_RESULT${NC}" >&2
    exit 1
fi
echo ""

# -------------------------------------------------------------------
# Add Lambda permission for API Gateway
# -------------------------------------------------------------------
log_info "Adding API Gateway permissions to Lambda..."

POLICY=$(aws --profile "$AWS_PROFILE" lambda get-policy \
  --function-name "$FUNCTION_NAME" 2>/dev/null || true)

if echo "$POLICY" | grep -q "$API_ID"; then
    log_info "Lambda permission for API Gateway already exists"
else
    if aws --profile "$AWS_PROFILE" lambda add-permission \
        --function-name "$FUNCTION_NAME" \
        --statement-id "apigw-${API_ID}-${STAGE_NAME}" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/$STAGE_NAME/*/*" \
        >/dev/null 2>&1; then
        log_success "API Gateway permission added"
    else
        log_warn "Failed to add API Gateway permission (may already exist)"
    fi
fi
echo ""

# -------------------------------------------------------------------
# Deploy API
# -------------------------------------------------------------------
log_info "Deploying API Gateway..."

if aws --profile "$AWS_PROFILE" apigateway create-deployment \
    --rest-api-id "$API_ID" \
    --stage-name "$STAGE_NAME" \
    --stage-description "Deployment $(date +%Y-%m-%d_%H:%M:%S)" >/dev/null 2>&1; then
    log_success "${GREEN}API Gateway deployed${NC}"
else
    log_warn "${RED}API deployment failed${NC}"
fi
echo ""

# -------------------------------------------------------------------
# Verifying Deployment Status
# -------------------------------------------------------------------

log_info "Verifying deployment status..."

# Get the stage's deployment ID
STAGE_DEPLOYMENT_ID=$(aws --profile "$AWS_PROFILE" apigateway get-stage \
    --rest-api-id "$API_ID" \
    --stage-name "$STAGE_NAME" \
    --query 'deploymentId' \
    --output text 2>/dev/null)

if [[ -n "$STAGE_DEPLOYMENT_ID" ]]; then
    log_success "Stage $STAGE_NAME is deployed with ID: ${YELLOW}$STAGE_DEPLOYMENT_ID${NC}"
else
    log_error "Stage ${YELLOW}$STAGE_NAME${NC} has no deployment associated"
    exit 1
fi
echo ""

# -------------------------------------------------------------------
# Test API endpoint
# -------------------------------------------------------------------
API_ENDPOINT="https://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE_NAME"

log_info "Testing API Gateway endpoint..."

if command -v curl >/dev/null 2>&1; then
    log_info "Testing: ${BLUE}$API_ENDPOINT/health${NC}"

    # Wait a moment for deployment to propagate
    sleep 3

    for attempt in {1..3}; do
        HEALTH_RESPONSE=$(curl -s -w "\\n%{http_code}" "$API_ENDPOINT/health" 2>/dev/null || printf "ERROR\\n000")
        HTTP_CODE=$(echo "$HEALTH_RESPONSE" | tail -n1)
        if [[ "$HTTP_CODE" == "200" ]]; then
            log_success "API health check passed on attempt $attempt"
            break
        elif [[ "$attempt" -eq 3 ]]; then
            log_warn "API health check failed after 3 attempts (code ${RED}$HTTP_CODE${NC})"
            log_warn "This may indicate Lambda function issues - check CloudWatch logs"
        else
            log_info "Health check attempt $attempt failed (code ${RED}$HTTP_CODE${NC}), retrying..."
            sleep 5
        fi
    done
else
    log_info "curl not available - skipping API test"
fi
echo ""

# -------------------------------------------------------------------
# Final output
# -------------------------------------------------------------------
log_success "API Gateway Lambda integration completed!"
log_info "API ID: ${YELLOW}$API_ID${NC}"
log_info "API Endpoint: ${BLUE}$API_ENDPOINT${NC}"
log_info "Lambda Function: ${YELLOW}$FUNCTION_NAME${NC}"
log_info "Integration Type: ${YELLOW}AWS_PROXY${NC}"

log_summary "API Gateway integration configured successfully! ${CYAN}Next:${NC} Test the complete system or run 14-full-deployment.sh"
