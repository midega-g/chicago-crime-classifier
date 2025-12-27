#!/usr/bin/env bash
# 00-config.sh
# Centralized configuration, colors, logging and helpers for Chicago Crimes Serverless Deployment

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────────
# 1. Find project root reliably
# ────────────────────────────────────────────────────────────────────────────────
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

# ────────────────────────────────────────────────────────────────────────────────
# 2. Load .env file (safely)
# ────────────────────────────────────────────────────────────────────────────────
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
else
    echo "Error: .env file not found at $ENV_FILE" >&2
    exit 1
fi

# ────────────────────────────────────────────────────────────────────────────────
# 3. Colors & Symbols (used by all scripts)
# ────────────────────────────────────────────────────────────────────────────────
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m'          # No Color

export INFO=" ${CYAN}info${NC}"
export SUCCESS=" ${GREEN}✓${NC}"
export WARN=" ${YELLOW}warn${NC}"
export ERROR=" ${RED}error${NC}"

# ────────────────────────────────────────────────────────────────────────────────
# 4. Project-wide constants (override via .env when needed)
# ────────────────────────────────────────────────────────────────────────────────

export STAGE_NAME="dev"

# AWS Core
export REGION="${AWS_REGION}"
export AWS_PROFILE="${AWS_PROFILE}"
export ACCOUNT_ID="${AWS_ACCOUNT_ID}"

# S3
export STATIC_BUCKET="chicago-crimes-web-bucket"
export UPLOAD_BUCKET="chicago-crimes-uploads-bucket"

# Lambda
export FUNCTION_NAME="chicago-crimes-lambda-predictor"
export ECR_REPO="chicago-crimes-lambda-ecr"
export ROLE_NAME="chicago-crimes-lambda-execution-role"

# DynamoDB
export RESULTS_TABLE="chicago-crimes-dynamodb-results"

# API Gateway
export API_NAME="chicago-crimes-api-gateway"

# CloudFront
export CF_OAC_NAME="chicago-crimes-oac"
export DISTRIBUTION_COMMENT="Chicago Crimes Prediction App"

# Email / Notifications
export ADMIN_EMAIL="${ADMIN_EMAIL}"

# ────────────────────────────────────────────────────────────────────────────────
# 5. Helper function: Run AWS command with better error reporting
# ────────────────────────────────────────────────────────────────────────────────
run_aws() {
    local cmd=("$@")
    # Insert --profile after 'aws' command
    if [[ "${cmd[0]}" == "aws" ]]; then
        cmd=("${cmd[0]}" "--profile" "$AWS_PROFILE" "${cmd[@]:1}")
    fi
    echo -e "${INFO} ${cmd[*]}"

    # Capture both stdout and stderr
    local output
    local exit_code
    output=$("${cmd[@]}" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        # Success - return the output for further processing
        echo "$output"
        return 0
    else
        # Failure - show the error
        echo -e "${ERROR} Command failed: ${cmd[*]}" >&2
        echo -e "${ERROR} Error output:" >&2
        echo "$output" >&2
        return $exit_code
    fi
}

# ────────────────────────────────────────────────────────────────────────────────
# 6. Logging helper functions
# ────────────────────────────────────────────────────────────────────────────────

log_info() {
    echo -e "${INFO} $*" >&2
}

log_success() {
    echo -e "${SUCCESS} $*" >&2
}

log_warn() {
    echo -e "${WARN} $*" >&2
}

log_error() {
    echo -e "${ERROR} $*" >&2
    return 1
}

log_section() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$*${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_summary() {
    echo -e "\n${GREEN}---------------------------------------------------------------${NC}"
    echo -e "${SUCCESS} $*"
    echo -e "${GREEN}---------------------------------------------------------------${NC}"
}

# ────────────────────────────────────────────────────────────────────────────────
# 7. Show loaded configuration (useful for debugging)
# ────────────────────────────────────────────────────────────────────────────────

print_config_summary() {
    log_section "Configuration Loaded"
    echo -e "  ${CYAN}Profile:${NC}     ${YELLOW}${AWS_PROFILE}${NC}"
    echo -e "  ${CYAN}Region:${NC}      ${YELLOW}${REGION}${NC}"
    echo -e "  ${CYAN}Account ID:${NC}  ${YELLOW}${ACCOUNT_ID}${NC}"
    echo -e "  ${CYAN}Static Bucket:${NC}   ${YELLOW}${STATIC_BUCKET}${NC}"
    echo -e "  ${CYAN}Upload Bucket:${NC}   ${YELLOW}${UPLOAD_BUCKET}${NC}"
    echo ""
}

# Uncomment next line if you want auto-print when sourcing (optional)
# print_config_summary
