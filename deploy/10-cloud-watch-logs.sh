#!/bin/bash

# Dynamic CloudWatch Logs Viewer for Chicago Crimes Lambda
# Usage: ./watch-logs.sh [minutes_back] [follow]

set -e

# Configuration
FUNCTION_NAME="chicago-crimes-predictor"
LOG_GROUP="/aws/lambda/$FUNCTION_NAME"
REGION="af-south-1"

# Default to last 5 minutes if no argument provided
MINUTES_BACK=${1:-5}
FOLLOW_MODE=${2:-false}

# Calculate start time (X minutes ago)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    START_TIME=$(date -v-${MINUTES_BACK}M +%s)000
else
    # Linux
    START_TIME=$(date -d "${MINUTES_BACK} minutes ago" +%s)000
fi

echo "🔍 Watching CloudWatch logs for: $FUNCTION_NAME"
echo "📅 From: $(date -d @$((START_TIME/1000))) (last $MINUTES_BACK minutes)"
echo "🌍 Region: $REGION"
echo "📋 Log Group: $LOG_GROUP"
echo "----------------------------------------"

if [ "$FOLLOW_MODE" = "true" ] || [ "$FOLLOW_MODE" = "follow" ]; then
    echo "👀 Following logs (Ctrl+C to stop)..."
    echo ""

    # Follow mode - continuously poll for new logs
    LAST_TIMESTAMP=$START_TIME

    while true; do
        # Get new logs since last check
        EVENTS=$(aws logs filter-log-events \
            --log-group-name "$LOG_GROUP" \
            --start-time "$LAST_TIMESTAMP" \
            --region "$REGION" \
            --output json 2>/dev/null || echo '{"events":[]}')

        # Parse and display new events
        echo "$EVENTS" | jq -r '.events[] |
            "\(.timestamp | tonumber / 1000 | strftime("%H:%M:%S")) | \(.message)"' 2>/dev/null | \
        while IFS= read -r line; do
            if [ ! -z "$line" ]; then
                echo "$line"
                # Update last timestamp
                TIMESTAMP=$(echo "$line" | cut -d'|' -f1 | tr -d ' ')
                if [ ! -z "$TIMESTAMP" ]; then
                    LAST_TIMESTAMP=$(date -d "$TIMESTAMP" +%s)000 2>/dev/null || LAST_TIMESTAMP=$LAST_TIMESTAMP
                fi
            fi
        done

        sleep 2
    done
else
    # One-time fetch
    echo "📖 Fetching logs..."
    echo ""

    aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --start-time "$START_TIME" \
        --region "$REGION" \
        --output json | \
    jq -r '.events[] |
        "\(.timestamp | tonumber / 1000 | strftime("%Y-%m-%d %H:%M:%S")) | \(.message)"' | \
    while IFS= read -r line; do
        if [[ "$line" == *"ERROR"* ]] || [[ "$line" == *"error"* ]]; then
            echo -e "\033[31m$line\033[0m"  # Red for errors
        elif [[ "$line" == *"WARNING"* ]] || [[ "$line" == *"warning"* ]]; then
            echo -e "\033[33m$line\033[0m"  # Yellow for warnings
        elif [[ "$line" == *"START RequestId"* ]]; then
            echo -e "\033[32m$line\033[0m"  # Green for start
        elif [[ "$line" == *"END RequestId"* ]]; then
            echo -e "\033[32m$line\033[0m"  # Green for end
        else
            echo "$line"
        fi
    done
fi

echo ""
echo "✅ Log fetch complete"
