#!/usr/bin/env bash

set -euo pipefail

# -------------------------------------------------------------------
# Load shared configuration and helpers
# -------------------------------------------------------------------
source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

trap 'rm -f lambda-trust-policy.json lambda-permissions-policy.json' EXIT

log_section "Lambda IAM Role Setup"

# -------------------------------------------------------------------
# Check if IAM role already exists
# -------------------------------------------------------------------
log_info "Checking for existing IAM role..."

if aws --profile "$AWS_PROFILE" iam get-role \
    --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    log_warn "IAM role already exists: $ROLE_NAME"
    log_summary "Using existing IAM role"
    echo -e "${CYAN}Next:${NC} Run 09-setup-ses-email.sh"
    exit 0
fi

log_info "Creating new IAM role..."

# -------------------------------------------------------------------
# Create trust policy
# -------------------------------------------------------------------
log_info "Creating Lambda trust policy..."

cat > lambda-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# -------------------------------------------------------------------
# Create IAM role
# -------------------------------------------------------------------
log_info "Creating IAM role: $ROLE_NAME"

aws --profile "$AWS_PROFILE" iam create-role \
    --role-name "$ROLE_NAME" \
    --tags Key=Project,Value=ChicagoCrimes Key=Env,Value=dev \
    --assume-role-policy-document file://lambda-trust-policy.json >/dev/null

log_success "IAM role created: $ROLE_NAME"

# -------------------------------------------------------------------
# Attach basic execution policy
# -------------------------------------------------------------------
log_info "Attaching basic execution policy..."

aws --profile "$AWS_PROFILE" iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole >/dev/null

log_success "Basic execution policy attached"

# -------------------------------------------------------------------
# Create custom permissions policy
# -------------------------------------------------------------------
log_info "Creating custom permissions policy..."

cat > lambda-permissions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::$UPLOAD_BUCKET/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::$UPLOAD_BUCKET"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem"
            ],
            "Resource": "arn:aws:dynamodb:$REGION:$ACCOUNT_ID:table/$RESULTS_TABLE"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ses:SendEmail",
                "ses:SendRawEmail"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# -------------------------------------------------------------------
# Attach custom policy
# -------------------------------------------------------------------
log_info "Attaching custom permissions policy..."

aws --profile "$AWS_PROFILE" iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "$INLINE_POLICY_NAME" \
    --policy-document file://lambda-permissions-policy.json >/dev/null

log_success "Custom permissions policy attached"

# -------------------------------------------------------------------
# Wait for IAM propagation
# -------------------------------------------------------------------
log_info "Waiting for IAM policies to propagate..."
log_info "Waiting for IAM role to become available..."

for i in {1..10}; do
  if aws --profile "$AWS_PROFILE" iam get-role \
       --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    log_success "IAM role is now available"
    break
  fi
  log_info "IAM not ready yet... retrying ($i/10)"
  sleep 6
done

# -------------------------------------------------------------------
# Final output
# -------------------------------------------------------------------
log_success "Lambda IAM role setup completed!"
log_info "Role Name: ${YELLOW}$ROLE_NAME${NC}"
log_info "Role ARN: ${YELLOW}arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME${NC}"

log_summary "IAM role ready for Lambda function!"
echo -e "${CYAN}Next:${NC} Run 09-setup-ses-email.sh"
