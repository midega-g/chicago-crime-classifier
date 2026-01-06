#!/usr/bin/env bash

set -euo pipefail

# -------------------------------------------------------------------
# Load shared configuration and helpers
# -------------------------------------------------------------------
source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}

log_section "SES Email Setup"

# -------------------------------------------------------------------
# Check if email is already verified
# -------------------------------------------------------------------
log_info "Checking SES email verification status..."

VERIFICATION_STATUS=$(aws ses get-identity-verification-attributes \
  --region "$REGION" \
  --profile "$AWS_PROFILE" \
  --identities "$ADMIN_EMAIL" \
  --query "VerificationAttributes.\"$ADMIN_EMAIL\".VerificationStatus" \
  --output text 2>/dev/null || echo "NotFound")

if [[ "$VERIFICATION_STATUS" == "Success" ]]; then
    log_success "Email already ${GREEN}verified${NC} in SES"
elif [[ "$VERIFICATION_STATUS" == "Pending" ]]; then
    log_warn "Email verification ${CYAN}pending${NC}"
    log_warn "Check your inbox and click the verification link."
else
    log_info "Email not verified. Sent a verification email. ${GREEN}Please verify${NC}"

    if aws ses verify-email-identity \
        --email-address "$ADMIN_EMAIL" \
        --profile "$AWS_PROFILE" \
        --region "$REGION" 2>/dev/null; then
        log_success "Verification email sent to your registred email"
        log_warn "IMPORTANT: Check your email and click the verification link!"
        log_warn "Emails will not be sent until verification is complete."
    else
        log_error "Failed to send verification email. Check if SES is available in region ${YELLOW}$REGION${NC}"
        log_info "SES availability varies by region. Check AWS Console if unsure."
        exit 1
    fi
fi
echo ""

# -------------------------------------------------------------------
# Check SES production access
# -------------------------------------------------------------------
log_info "Checking SES production access..."

SES_PRODUCTION_ENABLED=$(aws ses get-account-sending-enabled \
  --region "$REGION" \
  --profile "$AWS_PROFILE" \
  --query 'Enabled' \
  --output text 2>/dev/null || echo "false")

if [[ "$SES_PRODUCTION_ENABLED" == "false" ]]; then
    log_warn "SES sending is disabled (account may still be in sandbox or restricted)"
    log_info "Request production access and sending quota increase via AWS Support"
else
    log_success "SES is in production mode (sending enabled)"
fi
echo ""

# -------------------------------------------------------------------
# Check SES sending quota
# -------------------------------------------------------------------

log_info "Checking SES sending quota..."

SES_QUOTA=$(aws --profile "$AWS_PROFILE" ses get-send-quota \
  --query 'Max24HourSend' \
  --output text 2>/dev/null || echo "0")

if [[ "$SES_QUOTA" != "0" ]]; then
    log_success "SES sending quota: ${YELLOW}$SES_QUOTA emails/24h${NC}"
else
    log_warn "SES may be in sandbox mode - verify both sender and recipient emails"
fi

# -------------------------------------------------------------------
# Final output
# -------------------------------------------------------------------
log_success "SES email setup completed!"
echo ""

log_info "Is SES production access enabled? ${YELLOW}$SES_PRODUCTION_ENABLED${NC}"

if [[ "$SES_PRODUCTION_ENABLED" == "false" || "$SES_QUOTA" == "0" ]]; then
    log_warn "To move out of SES sandbox mode:"
    log_info "1. Verify your email address"
    log_info "2. Request production access in AWS Console"
    log_info "3. Complete the SES sending review process"
fi

log_summary "SES email service configured! ${CYAN}Next:${NC} Run 10-deploy-lambda-function.sh"
