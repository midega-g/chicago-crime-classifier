#!/usr/bin/env bash

set -euo pipefail

# -------------------------------------------------------------------
# Load shared configuration and helpers
# -------------------------------------------------------------------
source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

log_section "DynamoDB Table Setup"

# -------------------------------------------------------------------
# Check if DynamoDB table already exists
# -------------------------------------------------------------------
log_info "Checking for existing DynamoDB table..."

if aws --profile "$AWS_PROFILE" dynamodb describe-table \
    --table-name "$RESULTS_TABLE" >/dev/null 2>&1; then

    TABLE_STATUS=$(aws --profile "$AWS_PROFILE" dynamodb describe-table \
      --table-name "$RESULTS_TABLE" \
      --query 'Table.TableStatus' \
      --output text)

    log_warn "DynamoDB table already exists: ${YELLOW}$RESULTS_TABLE${NC}"
    log_info "Table Status: ${GREEN}$TABLE_STATUS${NC}"
    log_summary "Using existing DynamoDB table ${CYAN}Next:${NC} Run 06-create-ecr-repository.sh"
    exit 0
fi
echo ""

log_info "Creating new DynamoDB table..."

# -------------------------------------------------------------------
# Create DynamoDB table
# -------------------------------------------------------------------
log_info "Creating DynamoDB table"

aws --profile "$AWS_PROFILE" dynamodb create-table \
    --table-name "$RESULTS_TABLE" \
    --attribute-definitions \
        AttributeName=file_key,AttributeType=S \
    --key-schema \
        AttributeName=file_key,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST > /dev/null 2>&1;

log_success "DynamoDB table created: ${YELLOW}$RESULTS_TABLE${NC}"
echo ""

# -------------------------------------------------------------------
# Wait for table to be active
# -------------------------------------------------------------------
log_info "Waiting for table to become active..."

aws --profile "$AWS_PROFILE" dynamodb wait table-exists \
    --table-name "$RESULTS_TABLE"

TABLE_STATUS=$(aws --profile "$AWS_PROFILE" dynamodb describe-table \
  --table-name "$RESULTS_TABLE" \
  --query 'Table.TableStatus' \
  --output text)

log_success "Table is now active: ${GREEN}$TABLE_STATUS${NC}"

# -------------------------------------------------------------------
# Final output
# -------------------------------------------------------------------
log_success "DynamoDB table setup completed!"
echo ""

log_info "Table Name: ${YELLOW}$RESULTS_TABLE${NC}"
log_info "Primary Key: ${YELLOW}file_key (String)${NC}"
log_info "Billing Mode: ${YELLOW}PAY_PER_REQUEST${NC}"
log_info "Table Status: ${GREEN}$TABLE_STATUS${NC}"

log_summary "DynamoDB table ready! ${CYAN}Next:${NC} Run 06-create-ecr-repository.sh"
