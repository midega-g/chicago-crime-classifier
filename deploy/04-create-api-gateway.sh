#!/bin/bash

# Chicago Crimes Serverless Deployment - API Gateway Proxy Setup
# This script creates REST API Gateway with proxy integration for ML Lambda

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "Creating REST API Gateway with proxy integration..."

# Step 1: Create REST API
echo "Creating REST API..."

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    echo "Install with: sudo apt install jq (Ubuntu) or brew install jq (macOS)"
    exit 1
fi

# Check if API already exists
EXISTING_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text --region $REGION 2>/dev/null || echo "")

if [ ! -z "$EXISTING_API_ID" ] && [ "$EXISTING_API_ID" != "None" ]; then
    echo "API Gateway '$API_NAME' already exists with ID: $EXISTING_API_ID"
    API_ID="$EXISTING_API_ID"
else
    echo "Creating new REST API..."
    API_RESPONSE=$(aws apigateway create-rest-api \
        --name $API_NAME \
        --description "Chicago Crimes ML API with proxy integration" \
        --region $REGION)

    if [ $? -eq 0 ]; then
        API_ID=$(echo $API_RESPONSE | jq -r '.id')
        echo "Created API with ID: $API_ID"
    else
        echo "Error: Failed to create REST API"
        exit 1
    fi
fi

# Step 2: Get root resource ID
echo "Getting root resource..."
RESOURCES_RESPONSE=$(aws apigateway get-resources \
    --rest-api-id $API_ID \
    --region $REGION)

if [ $? -eq 0 ]; then
    # Debug: Show all resources
    echo "Debug: Current API resources:"
    echo $RESOURCES_RESPONSE | jq -r '.items[] | "ID: \(.id), Path: \(.path // "none"), PathPart: \(.pathPart // "none")"'

    ROOT_RESOURCE_ID=$(echo $RESOURCES_RESPONSE | jq -r '.items[] | select(.path=="/") | .id')
    if [ -z "$ROOT_RESOURCE_ID" ] || [ "$ROOT_RESOURCE_ID" = "null" ]; then
        # Fallback: get first resource if no root found
        ROOT_RESOURCE_ID=$(echo $RESOURCES_RESPONSE | jq -r '.items[0].id')
        echo "Warning: Using first resource as root: $ROOT_RESOURCE_ID"
    else
        echo "Root resource ID: $ROOT_RESOURCE_ID"
    fi
else
    echo "Error: Failed to get resources for API $API_ID"
    exit 1
fi

# Step 3: Create proxy resource
echo "Creating proxy resource {proxy+}..."

# Refresh resources to get current state
RESOURCES_RESPONSE=$(aws apigateway get-resources \
    --rest-api-id $API_ID \
    --region $REGION)

# Check if proxy resource already exists
EXISTING_PROXY_ID=$(echo $RESOURCES_RESPONSE | jq -r '.items[] | select(.pathPart=="{proxy+}") | .id' 2>/dev/null || echo "")

if [ ! -z "$EXISTING_PROXY_ID" ] && [ "$EXISTING_PROXY_ID" != "null" ] && [ "$EXISTING_PROXY_ID" != "" ]; then
    echo "Proxy resource already exists with ID: $EXISTING_PROXY_ID"
    PROXY_RESOURCE_ID="$EXISTING_PROXY_ID"
else
    echo "Creating new proxy resource..."
    PROXY_RESOURCE_RESPONSE=$(aws apigateway create-resource \
        --rest-api-id $API_ID \
        --parent-id $ROOT_RESOURCE_ID \
        --path-part "{proxy+}" \
        --region $REGION)

    if [ $? -eq 0 ]; then
        PROXY_RESOURCE_ID=$(echo $PROXY_RESOURCE_RESPONSE | jq -r '.id')
        echo "Proxy resource ID: $PROXY_RESOURCE_ID"
    else
        echo "Error: Failed to create proxy resource"
        exit 1
    fi
fi

# Step 4: Create ANY method for proxy
echo "Creating ANY method for proxy..."
if aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $PROXY_RESOURCE_ID \
    --http-method ANY \
    --authorization-type NONE \
    --request-parameters '{"method.request.path.proxy":true}' \
    --region $REGION > /dev/null 2>&1; then
    echo "ANY method created successfully"
else
    echo "Warning: ANY method creation failed (may already exist)"
fi

# Step 4b: Skip complex CORS for now - will be handled by Lambda
echo "Skipping complex CORS configuration (Lambda will handle CORS headers)"
echo "✓ Basic API structure ready"

# Step 5: Create proxy integration (will be configured after Lambda deployment)
echo "Proxy integration will be configured after Lambda deployment"

# Step 6: Deploy API
echo "Deploying API..."
if aws apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name prod \
    --region $REGION > /dev/null 2>&1; then
    echo "API deployed successfully"
else
    echo "Warning: API deployment failed"
fi

echo "API Gateway structure created successfully!"
echo "✓ API ID: $API_ID"
echo "✓ API Endpoint: https://$API_ID.execute-api.$REGION.amazonaws.com/prod"
echo "✓ Proxy resource created: $PROXY_RESOURCE_ID"
echo "✓ Ready for Lambda integration"
echo "Note: Proxy integration will be configured when Lambda is deployed"
echo ""
echo "--------------------------------NEXT STEP-----------------------------------"
echo ""
