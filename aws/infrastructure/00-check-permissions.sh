#!/usr/bin/env bash

set -euo pipefail

# Load shared configuration
source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

log_section "AWS Permissions Verification"

# Test actual AWS commands instead of policy simulation
test_aws_access() {
    local service="$1"
    shift
    local cmd_args=("$@")

    log_info "Testing ${service} access..."

    if aws --profile "$AWS_PROFILE" "${cmd_args[@]}" >/dev/null 2>&1; then
        log_success "${service} access confirmed"
        return 0
    else
        log_error "${service} access denied"
        log_error "Command failed: aws --profile $AWS_PROFILE ${cmd_args[*]}"
        return 1
    fi
}

# Test all required AWS services
check_all_permissions() {
    local failed=0

    # S3 permissions
    if ! test_aws_access "S3" s3api list-buckets --max-items 1; then
        failed=1
    fi

    # CloudFront permissions
    if ! test_aws_access "CloudFront" cloudfront list-distributions --max-items 1; then
        failed=1
    fi

    # API Gateway permissions
    if ! test_aws_access "API Gateway" apigateway get-rest-apis --limit 1; then
        failed=1
    fi

    # Lambda permissions
    if ! test_aws_access "Lambda" lambda list-functions --max-items 1; then
        failed=1
    fi

    # DynamoDB permissions
    if ! test_aws_access "DynamoDB" dynamodb list-tables --limit 1; then
        failed=1
    fi

    # IAM permissions (for role creation)
    if ! test_aws_access "IAM" iam list-roles --max-items 1; then
        failed=1
    fi

    # ECR permissions (for Lambda containers)
    if ! test_aws_access "ECR" ecr describe-repositories --max-items 1; then
        failed=1
    fi

    if [[ $failed -eq 1 ]]; then
        log_error "Some AWS permissions are missing!"
        log_error "Contact your AWS administrator to grant the required permissions."
        return 1
    fi

    log_success "All AWS permissions verified successfully!"
    return 0
}

# Run the comprehensive check
if check_all_permissions; then
    log_summary "Ready for deployment!"
    log_info "Profile: ${YELLOW}$AWS_PROFILE${NC}"
    log_info "Region: ${YELLOW}$REGION${NC}"
    log_info "Account: ${YELLOW}$ACCOUNT_ID${NC}"
    echo -e "${CYAN}Next:${NC} Run 07-full-deployment.sh or individual scripts"
else
    log_summary "Permission issues detected - deployment will fail"
    exit 1
fi
