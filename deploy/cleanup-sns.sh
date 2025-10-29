#!/bin/bash

# Cleanup SNS resources for Chicago Crimes project

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "Cleaning up SNS resources..."

# Delete SNS topic
echo "Deleting SNS topic..."
if aws sns delete-topic --topic-arn "arn:aws:sns:$REGION:$ACCOUNT_ID:chicago-crimes-notifications" --region $REGION 2>/dev/null; then
    echo "✓ SNS topic deleted"
else
    echo "Warning: SNS topic not found or already deleted"
fi

# Remove SNS permissions from Lambda (if they exist)
echo "Removing SNS permissions from Lambda..."
if aws lambda remove-permission --function-name $FUNCTION_NAME --statement-id sns-invoke --region $REGION 2>/dev/null; then
    echo "✓ SNS Lambda permissions removed"
else
    echo "Warning: SNS Lambda permissions not found"
fi

# Update Lambda environment variables to remove SNS_TOPIC_ARN
echo "Updating Lambda environment variables..."
if aws lambda update-function-configuration \
    --function-name $FUNCTION_NAME \
    --environment Variables="{UPLOAD_BUCKET=$UPLOAD_BUCKET,RESULTS_TABLE=$RESULTS_TABLE}" \
    --region $REGION > /dev/null 2>&1; then
    echo "✓ Lambda environment variables updated (SNS_TOPIC_ARN removed)"
else
    echo "Warning: Failed to update Lambda environment variables"
fi

# Verify cleanup
echo ""
echo "Verifying cleanup..."
SNS_TOPICS=$(aws sns list-topics --region $REGION --query 'Topics[?contains(TopicArn, `chicago-crimes`)]' --output text 2>/dev/null || echo "")
if [ -z "$SNS_TOPICS" ]; then
    echo "✓ No chicago-crimes SNS topics found"
else
    echo "Warning: Found remaining SNS topics: $SNS_TOPICS"
fi

echo ""
echo "SNS cleanup completed!"
echo "Next step: Redeploy Lambda with SES permissions using 06-deploy-ml-lambda-docker.sh"
