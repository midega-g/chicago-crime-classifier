#!/usr/bin/env bash

set -euo pipefail

# Load configuration
source "$(dirname "$0")/00-config.sh" || {
  log_error "Failed to load config"
  exit 1
}

# Check dependencies
command -v jq >/dev/null 2>&1 || {
  log_error "jq is required but not installed"
  log_info "Install with: apt-get install jq (Ubuntu) or brew install jq (macOS)"
  exit 1
}

# Script parameters
MINUTES_BACK=${1:-5}
FOLLOW_MODE=${2:-false}

# Enable case-insensitive matching for log highlighting
shopt -s nocasematch

# Function to display log lines with enhanced color coding
display_log_line() {
    local line="$1"

    if [[ "$line" == *"ERROR"* ]] || [[ "$line" == *"error"* ]] || \
       [[ "$line" == *"Error"* ]] || [[ "$line" == *"Exception"* ]] || \
       [[ "$line" == *"Traceback"* ]] || [[ "$line" == *"Task timed out"* ]]; then
        echo -e "${RED}$line${NC}"
    elif [[ "$line" == *"WARNING"* ]] || [[ "$line" == *"warning"* ]] || \
         [[ "$line" == *"Warning"* ]]; then
        echo -e "${YELLOW}$line${NC}"
    elif [[ "$line" == *"START RequestId"* ]]; then
        echo -e "${GREEN}$line${NC}"
    elif [[ "$line" == *"END RequestId"* ]]; then
        echo -e "${GREEN}$line${NC}"
    else
        echo "$line"
    fi
}

log_section "CloudWatch Logs Viewer"

log_info "Function: ${YELLOW}$FUNCTION_NAME${NC}"
log_info "Region: ${YELLOW}$REGION${NC}"
log_info "Time Range: ${YELLOW}Last $MINUTES_BACK minutes${NC}"

# Calculate start time (X minutes ago)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    START_TIME=$(date -v-"${MINUTES_BACK}"M +%s)000
else
    # Linux
    START_TIME=$(date -d "${MINUTES_BACK} minutes ago" +%s)000
fi

LOG_GROUP="/aws/lambda/$FUNCTION_NAME"
FAILURE_COUNT=0
MAX_FAILURES=3

# Verify log group exists
if ! aws --profile "$AWS_PROFILE" logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP" \
    --region "$REGION" \
    --query "logGroups[?logGroupName=='$LOG_GROUP']" \
    --output text > /dev/null 2>&1; then
    log_error "Log group not found: $LOG_GROUP"
    log_info "Lambda function may not have been invoked yet"
    exit 1
fi

log_success "Found log group: $LOG_GROUP"

# Check if log streams exist and provide helpful info
STREAM_COUNT=$(aws --profile "$AWS_PROFILE" logs describe-log-streams \
    --log-group-name "$LOG_GROUP" \
    --region "$REGION" \
    --query 'length(logStreams)' \
    --output text 2>/dev/null || echo "0")

if [ "$STREAM_COUNT" -eq 0 ]; then
    log_warn "No log streams found - Lambda may not have been invoked yet"
    log_info "Try invoking the Lambda function first, then run this script"
else
    log_info "Found $STREAM_COUNT log streams"
fi

if [ "$FOLLOW_MODE" = "true" ] || [ "$FOLLOW_MODE" = "follow" ]; then
    log_info "Following logs (Ctrl+C to stop)..."
    echo ""

    # Follow mode - continuously poll for new logs
    LAST_TIMESTAMP=$START_TIME

    while true; do
        # Get new logs since last check with better error handling
        if ! EVENTS=$(aws --profile "$AWS_PROFILE" logs filter-log-events \
            --log-group-name "$LOG_GROUP" \
            --start-time "$LAST_TIMESTAMP" \
            --region "$REGION" \
            --output json 2>/dev/null); then

            FAILURE_COUNT=$((FAILURE_COUNT + 1))

            if [ $FAILURE_COUNT -eq 1 ]; then
                log_warn "AWS CloudWatch API call failed (attempt $FAILURE_COUNT)"
            elif [ $FAILURE_COUNT -ge $MAX_FAILURES ]; then
                log_error "AWS CloudWatch API failed $MAX_FAILURES times consecutively"
                log_error "Check your AWS credentials, permissions, or network connection"
                exit 1
            fi

            # Exponential backoff
            SLEEP_TIME=$((2 ** FAILURE_COUNT))
            sleep "$SLEEP_TIME"
            continue
        fi

        # Reset failure count on success
        FAILURE_COUNT=0

        # Parse and display new events with proper timestamp tracking
        EVENT_COUNT=$(echo "$EVENTS" | jq -r '.events | length' 2>/dev/null || echo "0")

        if [ "$EVENT_COUNT" -gt 0 ]; then
            # Sort events by timestamp and display
            echo "$EVENTS" | jq -r '.events | sort_by(.timestamp) | .[] |
                "\(.timestamp | tonumber / 1000 | strftime("%H:%M:%S")) | \(.message)"' 2>/dev/null | \
            while IFS= read -r line; do
                if [ ! -z "$line" ]; then
                    display_log_line "$line"
                fi
            done

            # Update last timestamp to the latest event timestamp
            LAST_TIMESTAMP=$(echo "$EVENTS" | jq -r '.events | max_by(.timestamp) | .timestamp + 1' 2>/dev/null || echo "$LAST_TIMESTAMP")
        fi

        sleep 2
    done
else
    # One-time fetch
    log_info "Fetching logs from $(date -d @$((START_TIME/1000)) 2>/dev/null || date -r $((START_TIME/1000)) 2>/dev/null || echo "$START_TIME")..."
    echo ""

    if ! EVENTS=$(aws --profile "$AWS_PROFILE" logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --start-time "$START_TIME" \
        --region "$REGION" \
        --output json 2>/dev/null); then
        log_error "Failed to fetch CloudWatch logs"
        log_error "Check your AWS credentials, permissions, or network connection"
        exit 1
    fi

    EVENT_COUNT=$(echo "$EVENTS" | jq -r '.events | length' 2>/dev/null || echo "0")

    if [ "$EVENT_COUNT" -eq 0 ]; then
        log_warn "No log events found in the specified time range"
        log_info "Try increasing the time range or invoke the Lambda function first"
    else
        log_info "Found $EVENT_COUNT log events"
        echo ""

        # Sort events by timestamp and display
        echo "$EVENTS" | jq -r '.events | sort_by(.timestamp) | .[] |
            "\(.timestamp | tonumber / 1000 | strftime("%Y-%m-%d %H:%M:%S")) | \(.message)"' 2>/dev/null | \
        while IFS= read -r line; do
            display_log_line "$line"
        done
    fi
fi

log_success "Log fetch complete"
