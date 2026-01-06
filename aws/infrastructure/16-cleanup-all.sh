#!/usr/bin/env bash

set -euo pipefail

# Load configuration
source "$(dirname "$0")/00-config.sh" || {
  log_error "Failed to load config"
  exit 1
}

# Helper function to cleanup CloudFront distribution
cleanup_cloudfront_distribution() {
    local DISTRIBUTION_ID
    DISTRIBUTION_ID=$(get_cloudfront_distribution_id)

    if [ -z "$DISTRIBUTION_ID" ] || [ "$DISTRIBUTION_ID" = "None" ]; then
        log_info "CloudFront distribution not found"
        return
    fi

    log_info "Disabling CloudFront distribution: $DISTRIBUTION_ID"

    # Create temporary files
    local CONFIG_FILE
    local DISABLED_CONFIG_FILE
    CONFIG_FILE=$(mktemp)
    DISABLED_CONFIG_FILE=$(mktemp)

    trap 'rm -f "$CONFIG_FILE" "$DISABLED_CONFIG_FILE"' EXIT

    if aws --profile "$AWS_PROFILE" cloudfront get-distribution-config \
        --id "$DISTRIBUTION_ID" > "$CONFIG_FILE" 2>/dev/null; then

        local ETAG
        ETAG=$(jq -r '.ETag' "$CONFIG_FILE" 2>/dev/null || echo "")

        if [ ! -z "$ETAG" ] && [ "$ETAG" != "null" ]; then
            # Disable distribution
            jq '.DistributionConfig.Enabled = false | .DistributionConfig' \
                "$CONFIG_FILE" > "$DISABLED_CONFIG_FILE" 2>/dev/null

            if aws --profile "$AWS_PROFILE" cloudfront update-distribution \
                --id "$DISTRIBUTION_ID" \
                --distribution-config "file://$DISABLED_CONFIG_FILE" \
                --if-match "$ETAG" > /dev/null 2>&1; then

                log_info "Waiting for distribution to be disabled (5-10 minutes)..."

                # Wait for deployment with timeout
                if timeout 900 aws --profile "$AWS_PROFILE" cloudfront wait distribution-deployed \
                    --id "$DISTRIBUTION_ID" > /dev/null 2>&1; then

                    # Get fresh ETag and delete
                    local FRESH_ETAG
                    FRESH_ETAG=$(aws --profile "$AWS_PROFILE" cloudfront get-distribution \
                        --id "$DISTRIBUTION_ID" \
                        --query 'ETag' \
                        --output text 2>/dev/null || echo "")

                    if [ ! -z "$FRESH_ETAG" ] && [ "$FRESH_ETAG" != "null" ]; then
                        if aws --profile "$AWS_PROFILE" cloudfront delete-distribution \
                            --id "$DISTRIBUTION_ID" \
                            --if-match "$FRESH_ETAG" > /dev/null 2>&1; then
                            log_success "CloudFront distribution $DISTRIBUTION_ID deleted"
                        else
                            log_warn "Failed to delete CloudFront distribution $DISTRIBUTION_ID"
                        fi
                    fi
                else
                    log_warn "Timeout waiting for distribution $DISTRIBUTION_ID deployment"
                fi
            fi
        fi
    fi
}

# Helper function to cleanup Origin Access Controls
cleanup_origin_access_controls() {
    local OAC_IDS
    OAC_IDS=$(aws --profile "$AWS_PROFILE" cloudfront list-origin-access-controls \
        --query "OriginAccessControlList.Items[?contains(Name, '$CF_OAC_NAME')].Id" \
        --output text 2>/dev/null || echo "")

    if [ -z "$OAC_IDS" ] || [ "$OAC_IDS" = "None" ]; then
        log_info "Origin Access Controls not found"
        return
    fi

    for OAC_ID in $OAC_IDS; do
        if [ "$OAC_ID" != "None" ] && [ ! -z "$OAC_ID" ]; then
            local OAC_ETAG
            OAC_ETAG=$(aws --profile "$AWS_PROFILE" cloudfront get-origin-access-control \
                --id "$OAC_ID" \
                --query 'ETag' \
                --output text 2>/dev/null || echo "")

            if [ ! -z "$OAC_ETAG" ] && [ "$OAC_ETAG" != "null" ]; then
                if aws --profile "$AWS_PROFILE" cloudfront delete-origin-access-control \
                    --id "$OAC_ID" \
                    --if-match "$OAC_ETAG" > /dev/null 2>&1; then
                    log_success "Origin Access Control $OAC_ID deleted"
                else
                    log_warn "Failed to delete Origin Access Control $OAC_ID"
                fi
            fi
        fi
    done
}

# Helper function to cleanup S3 buckets
cleanup_s3_bucket() {
    local bucket_name="$1"
    local bucket_type="$2"

    if ! aws --profile "$AWS_PROFILE" s3 ls "s3://$bucket_name" > /dev/null 2>&1; then
        log_info "$bucket_type bucket $bucket_name not found"
        return
    fi

    log_info "Emptying $bucket_type bucket: $bucket_name"

    # Delete all object versions and delete markers
    aws --profile "$AWS_PROFILE" s3api list-object-versions \
        --bucket "$bucket_name" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        --output text 2>/dev/null | while read -r key version; do
        if [ ! -z "$key" ] && [ "$key" != "None" ]; then
            aws --profile "$AWS_PROFILE" s3api delete-object \
                --bucket "$bucket_name" \
                --key "$key" \
                --version-id "$version" > /dev/null 2>&1 || true
        fi
    done

    # Delete all delete markers
    aws --profile "$AWS_PROFILE" s3api list-object-versions \
        --bucket "$bucket_name" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        --output text 2>/dev/null | while read -r key version; do
        if [ ! -z "$key" ] && [ "$key" != "None" ]; then
            aws --profile "$AWS_PROFILE" s3api delete-object \
                --bucket "$bucket_name" \
                --key "$key" \
                --version-id "$version" > /dev/null 2>&1 || true
        fi
    done

    # Remove remaining objects (fallback)
    aws --profile "$AWS_PROFILE" s3 rm "s3://$bucket_name" --recursive > /dev/null 2>&1 || true

    # Delete bucket
    if aws --profile "$AWS_PROFILE" s3 rb "s3://$bucket_name" > /dev/null 2>&1; then
        log_success "$bucket_type bucket $bucket_name deleted"
    else
        log_warn "Failed to delete $bucket_type bucket $bucket_name"
    fi
}

# Helper function to cleanup CloudWatch logs
cleanup_cloudwatch_logs() {
    local LOG_GROUP="/aws/lambda/$FUNCTION_NAME"

    if aws --profile "$AWS_PROFILE" logs describe-log-groups \
        --log-group-name-prefix "$LOG_GROUP" \
        --region "$REGION" \
        --query "logGroups[?logGroupName=='$LOG_GROUP']" \
        --output text > /dev/null 2>&1; then

        if aws --profile "$AWS_PROFILE" logs delete-log-group \
            --log-group-name "$LOG_GROUP" \
            --region "$REGION" > /dev/null 2>&1; then
            log_success "CloudWatch log group $LOG_GROUP deleted"
        else
            log_warn "Failed to delete CloudWatch log group $LOG_GROUP"
        fi
    else
        log_info "CloudWatch log group $LOG_GROUP not found"
    fi
}

# Helper function to cleanup IAM resources
cleanup_iam_resources() {
    local deleted_policies=()
    local deleted_roles=()

    # Delete inline policy
    if aws --profile "$AWS_PROFILE" iam delete-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name "$INLINE_POLICY_NAME" > /dev/null 2>&1; then
        deleted_policies+=("$INLINE_POLICY_NAME")
        log_success "Inline policy $INLINE_POLICY_NAME deleted"
    fi

    # Detach managed policy
    if aws --profile "$AWS_PROFILE" iam detach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" > /dev/null 2>&1; then
        log_success "Managed policy AWSLambdaBasicExecutionRole detached from $ROLE_NAME"
    fi

    # Delete IAM role
    if aws --profile "$AWS_PROFILE" iam delete-role \
        --role-name "$ROLE_NAME" > /dev/null 2>&1; then
        deleted_roles+=("$ROLE_NAME")
        log_success "IAM role $ROLE_NAME deleted"
    else
        log_info "IAM role $ROLE_NAME not found"
    fi

    # Report deleted resources
    if [ ${#deleted_policies[@]} -gt 0 ]; then
        log_info "Deleted policies: ${deleted_policies[*]}"
    fi
    if [ ${#deleted_roles[@]} -gt 0 ]; then
        log_info "Deleted roles: ${deleted_roles[*]}"
    fi
}

log_section "Complete Infrastructure Cleanup"

log_warn "This will delete ALL AWS resources created by this project"
log_warn "This action is IRREVERSIBLE"
echo ""
read -r -p "Type 'DELETE' to confirm: " confirm

if [ "$confirm" != "DELETE" ]; then
    log_info "Cleanup cancelled"
    exit 0
fi

log_info "Starting complete cleanup..."

# Step 1: Delete Lambda function
log_info "🗑️ Step 1/9: Deleting Lambda function..."
if aws --profile "$AWS_PROFILE" lambda delete-function \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" > /dev/null 2>&1; then
    log_success "Lambda function $FUNCTION_NAME deleted"
else
    log_info "Lambda function $FUNCTION_NAME not found"
fi

# Step 2: Delete API Gateway
log_info "🗑️ Step 2/9: Deleting API Gateway..."
API_ID=$(get_api_gateway_id)
if [ ! -z "$API_ID" ] && [ "$API_ID" != "None" ]; then
    if aws --profile "$AWS_PROFILE" apigateway delete-rest-api \
        --rest-api-id "$API_ID" \
        --region "$REGION" > /dev/null 2>&1; then
        log_success "API Gateway $API_ID deleted"
    else
        log_warn "Failed to delete API Gateway $API_ID"
    fi
else
    log_info "API Gateway $API_NAME not found"
fi

# Step 3: Delete DynamoDB table
log_info "🗑️ Step 3/9: Deleting DynamoDB table..."
if aws --profile "$AWS_PROFILE" dynamodb delete-table \
    --table-name "$RESULTS_TABLE" \
    --region "$REGION" > /dev/null 2>&1; then
    log_success "DynamoDB table $RESULTS_TABLE deleted"
else
    log_info "DynamoDB table $RESULTS_TABLE not found"
fi

# Step 4: Delete CloudWatch logs
log_info "🗑️ Step 4/9: Deleting CloudWatch logs..."
cleanup_cloudwatch_logs

# Step 5: Delete CloudFront distribution
log_info "🗑️ Step 5/9: Deleting CloudFront distribution..."
cleanup_cloudfront_distribution

# Step 6: Delete Origin Access Controls
log_info "🗑️ Step 6/9: Deleting Origin Access Controls..."
cleanup_origin_access_controls

# Step 7: Delete S3 buckets
log_info "🗑️ Step 7/9: Deleting S3 buckets..."
cleanup_s3_bucket "$STATIC_BUCKET" "static"
cleanup_s3_bucket "$UPLOAD_BUCKET" "upload"

# Step 8: Delete ECR repository
log_info "🗑️ Step 8/9: Deleting ECR repository..."
if aws --profile "$AWS_PROFILE" ecr delete-repository \
    --repository-name "$ECR_REPO" \
    --region "$REGION" \
    --force > /dev/null 2>&1; then
    log_success "ECR repository $ECR_REPO deleted"
else
    log_info "ECR repository $ECR_REPO not found"
fi

# Step 9: Delete IAM roles and policies
log_info "🗑️ Step 9/9: Deleting IAM roles and policies..."
cleanup_iam_resources

log_summary "CLEANUP COMPLETE!"
log_success "All AWS resources have been deleted:"
log_info "Lambda function: ${YELLOW}$FUNCTION_NAME${NC}"
log_info "API Gateway: ${YELLOW}$API_NAME${NC}"
log_info "DynamoDB table: ${YELLOW}$RESULTS_TABLE${NC}"
log_info "CloudWatch logs: ${YELLOW}/aws/lambda/$FUNCTION_NAME${NC}"
log_info "CloudFront distribution and OAC"
log_info "S3 buckets: ${YELLOW}$STATIC_BUCKET, $UPLOAD_BUCKET${NC}"
log_info "ECR repository: ${YELLOW}$ECR_REPO${NC}"
log_info "IAM roles and policies: ${YELLOW}$ROLE_NAME, $INLINE_POLICY_NAME${NC}"

log_warn "All project resources have been permanently removed"
