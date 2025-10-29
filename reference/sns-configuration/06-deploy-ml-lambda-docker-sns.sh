#!/bin/bash

# Chicago Crimes Serverless Deployment - ML Lambda Function (Docker) - SNS VERSION
# This is the original deployment script that used SNS for email notifications

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "Deploying ML Lambda function using Docker with SNS..."

# [ECR and Docker build sections would be here - truncated for reference]

# Part 4: Create SNS topic
echo "Part 4: Creating SNS topic..."
if SNS_TOPIC_ARN=$(aws sns create-topic --name chicago-crimes-notifications --region $REGION --query 'TopicArn' --output text 2>/dev/null); then
    echo "✓ SNS Topic created: $SNS_TOPIC_ARN"
else
    echo "Error: Failed to create SNS topic"
    exit 1
fi
echo ""

# Part 5: Attach policies with SNS permissions
echo "Part 5: Attaching policies..."

# Create custom policy with SNS permissions
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
                "arn:aws:s3:::$UPLOAD_BUCKET",
                "arn:aws:s3:::$UPLOAD_BUCKET/*"
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
                "sns:Publish",
                "sns:Subscribe",
                "sns:ListSubscriptionsByTopic"
            ],
            "Resource": "arn:aws:sns:$REGION:$ACCOUNT_ID:chicago-crimes-notifications"
        }
    ]
}
EOF

# Part 6: Create Lambda function with SNS environment variable
echo "Part 6: Creating Lambda function..."
CREATE_OUTPUT=$(timeout 60 aws lambda create-function \
    --function-name $FUNCTION_NAME \
    --role arn:aws:iam::$ACCOUNT_ID:role/chicago-crimes-lambda-role \
    --code ImageUri=$REPO_URI:$IMAGE_TAG \
    --package-type Image \
    --environment Variables="{UPLOAD_BUCKET=$UPLOAD_BUCKET,RESULTS_TABLE=$RESULTS_TABLE,SNS_TOPIC_ARN=$SNS_TOPIC_ARN}" \
    --timeout 300 \
    --memory-size 2048 \
    --region $REGION 2>&1)

echo "✓ SNS topic: chicago-crimes-notifications"
echo "✓ Lambda configured with SNS_TOPIC_ARN environment variable"

# [Rest of deployment script would continue...]
