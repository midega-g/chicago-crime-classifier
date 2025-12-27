#!/bin/bash

# Chicago Crimes Serverless Deployment - ML Lambda Function (Docker)
# This script creates Lambda function using container image

set -e

# Load configuration
source "$(dirname "$0")/00-config.sh"

echo "Deploying ML Lambda function using Docker..."

# Part 1: Create ECR repository
echo "Part 1: Creating ECR repository..."
REPO_URI=$(aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION --query 'repositories[0].repositoryUri' --output text 2>/dev/null || echo "")

if [ -z "$REPO_URI" ] || [ "$REPO_URI" = "None" ]; then
    echo "Creating ECR repository..."
    if aws ecr create-repository --repository-name $ECR_REPO --region $REGION > /dev/null 2>&1; then
        REPO_URI=$(aws ecr describe-repositories --repository-names $ECR_REPO --region $REGION --query 'repositories[0].repositoryUri' --output text)
        echo "✓ ECR repository created: $REPO_URI"
    else
        echo "Error: Failed to create ECR repository"
        exit 1
    fi
else
    echo "✓ ECR repository exists: $REPO_URI"
fi
echo ""

# Part 2: Build and push Docker image
echo "Part 2: Authenticating with AWS Public ECR..."

# Retry AWS Public ECR login with timeout handling
for i in {1..3}; do
    echo "Attempt $i: Logging into AWS Public ECR..."
    if timeout 60 aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws; then
        echo "✓ AWS Public ECR login successful"
        break
    else
        echo "Warning: AWS Public ECR login attempt $i failed"
        if [ $i -eq 3 ]; then
            echo "Error: All AWS Public ECR login attempts failed - continuing anyway"
            echo "Note: If build fails, check network connectivity to public.ecr.aws"
        else
            sleep 5
        fi
    fi
done

echo "Building Docker image..."
# Build from project root with lambda/Dockerfile with retry
for attempt in {1..2}; do
    echo "Build attempt $attempt/2..."
    if docker build -f lambda/Dockerfile -t $ECR_REPO .; then
        echo "✓ Docker image built successfully"
        break
    else
        echo "Build attempt $attempt failed"
        if [ $attempt -eq 2 ]; then
            echo "Error: Failed to build Docker image after 2 attempts"
            exit 1
        else
            echo "Retrying build in 10 seconds..."
            sleep 10
        fi
    fi
done

# Tag image
IMAGE_TAG="latest"
docker tag $ECR_REPO:latest $REPO_URI:$IMAGE_TAG

# Logout and login to ECR with fresh token
echo "Clearing Docker credentials..."
docker logout $REPO_URI 2>/dev/null || true
docker logout 2>/dev/null || true

echo "Getting fresh ECR token and logging in..."
ECR_TOKEN=$(aws ecr get-login-password --region $REGION)
if echo $ECR_TOKEN | docker login --username AWS --password-stdin $REPO_URI; then
    echo "✓ ECR login successful with fresh token"
else
    echo "Error: ECR login failed"
    exit 1
fi

echo "Pushing image to ECR..."
# Retry push with exponential backoff
for attempt in {1..3}; do
    echo "Push attempt $attempt/3..."
    if docker push $REPO_URI:$IMAGE_TAG; then
        echo "✓ Image pushed successfully"
        break
    else
        echo "Push attempt $attempt failed"
        if [ $attempt -eq 3 ]; then
            echo "Error: Failed to push image after 3 attempts"
            exit 1
        else
            echo "Getting fresh ECR token and retrying in $((attempt * 5)) seconds..."
            sleep $((attempt * 5))
            ECR_TOKEN=$(aws ecr get-login-password --region $REGION)
            echo $ECR_TOKEN | docker login --username AWS --password-stdin $REPO_URI
        fi
    fi
done

# Clean up old ECR images (keep only latest)
echo "Cleaning up old ECR images..."
OLD_IMAGES=$(aws ecr list-images --repository-name $ECR_REPO --region $REGION --filter tagStatus=UNTAGGED --query 'imageIds[?imageDigest!=null]' --output json 2>/dev/null || echo '[]')
if [ "$OLD_IMAGES" != "[]" ] && [ "$OLD_IMAGES" != "" ]; then
    if aws ecr batch-delete-image --repository-name $ECR_REPO --region $REGION --image-ids "$OLD_IMAGES" > /dev/null 2>&1; then
        echo "✓ Old untagged images cleaned up"
    else
        echo "Warning: Failed to clean up old images"
    fi
else
    echo "✓ No old images to clean up"
fi
# Verify image exists in ECR
echo "Verifying image exists in ECR..."
if aws ecr describe-images --repository-name $ECR_REPO --image-ids imageTag=$IMAGE_TAG --region $REGION > /dev/null 2>&1; then
    echo "✓ Image verified in ECR: $REPO_URI:$IMAGE_TAG"
else
    echo "Error: Image not found in ECR"
    exit 1
fi
echo ""

# Part 3: Create IAM role (same as before)
echo "Part 3: Creating IAM role..."
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

if aws iam create-role \
    --role-name chicago-crimes-lambda-role \
    --assume-role-policy-document file://lambda-trust-policy.json \
    --region $REGION > /dev/null 2>&1; then
    echo "✓ IAM role created successfully"
else
    echo "Warning: IAM role creation failed (may already exist)"
fi

# Part 4: Setup and verify SES email
echo "Part 4: Setting up SES email verification..."

# Check if email is already verified using list-identities
VERIFIED_IDENTITIES=$(aws ses list-identities --region $REGION --query 'Identities' --output text 2>/dev/null || echo "")

if echo "$VERIFIED_IDENTITIES" | grep -q "$ADMIN_EMAIL"; then
    echo "✓ Email already verified in SES: $ADMIN_EMAIL"

    # Check verification status
    VERIFICATION_STATUS=$(aws ses get-identity-verification-attributes --identities "$ADMIN_EMAIL" --region $REGION --query "VerificationAttributes.\"$ADMIN_EMAIL\".VerificationStatus" --output text 2>/dev/null || echo "Unknown")
    echo "✓ Verification status: $VERIFICATION_STATUS"
else
    echo "Email not verified. Sending verification email to: $ADMIN_EMAIL"
    if aws ses verify-email-identity --email-address "$ADMIN_EMAIL" --region $REGION 2>/dev/null; then
        echo "✓ Verification email sent to: $ADMIN_EMAIL"
        echo "⚠ IMPORTANT: Check your email and click the verification link!"
        echo "⚠ Emails will not be sent until verification is complete."
    else
        echo "Warning: Failed to send verification email. Check if SES is available in region $REGION"
        echo "Available SES regions: us-east-1, us-west-2, eu-west-1, ap-southeast-1, ap-southeast-2"
    fi
fi

# Check SES sending quota
SES_QUOTA=$(aws ses get-send-quota --region $REGION --query 'Max24HourSend' --output text 2>/dev/null || echo "0")
if [ "$SES_QUOTA" != "0" ]; then
    echo "✓ SES sending quota: $SES_QUOTA emails/24h"
else
    echo "⚠ SES may be in sandbox mode - verify both sender and recipient emails"
fi
echo ""

# Part 5: Attach policies
echo "Part 5: Attaching policies..."
if aws iam attach-role-policy \
    --role-name chicago-crimes-lambda-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole > /dev/null 2>&1; then
    echo "✓ Basic execution policy attached"
else
    echo "Warning: Basic execution policy attachment failed (may already exist)"
fi

# Create custom policy
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
                "ses:SendEmail",
                "ses:SendRawEmail"
            ],
            "Resource": "*"
        }
    ]
}
EOF

if aws iam put-role-policy \
    --role-name chicago-crimes-lambda-role \
    --policy-name ChicagoCrimesLambdaPolicy \
    --policy-document file://lambda-permissions-policy.json > /dev/null 2>&1; then
    echo "✓ Custom permissions policy attached"
else
    echo "Warning: Custom permissions policy attachment failed (may already exist)"
fi

echo "Waiting for IAM policies to propagate..."
echo "(This can take up to 60 seconds for new roles)"
sleep 30
echo ""

# Part 6: Create/Update Lambda function
echo "Part 6: Creating Lambda function..."
if aws lambda get-function --function-name $FUNCTION_NAME --region $REGION > /dev/null 2>&1; then
    echo "Function exists, updating..."
    if aws lambda update-function-code \
        --function-name $FUNCTION_NAME \
        --image-uri $REPO_URI:$IMAGE_TAG \
        --region $REGION > /dev/null 2>&1; then
        echo "✓ Function code updated successfully"
    else
        echo "Error: Failed to update function code"
        exit 1
    fi
else
    echo "Creating new function..."

    CREATE_OUTPUT=$(timeout 60 aws lambda create-function \
        --function-name $FUNCTION_NAME \
        --role arn:aws:iam::$ACCOUNT_ID:role/chicago-crimes-lambda-role \
        --code ImageUri=$REPO_URI:$IMAGE_TAG \
        --package-type Image \
        --environment Variables="{UPLOAD_BUCKET=$UPLOAD_BUCKET,RESULTS_TABLE=$RESULTS_TABLE}" \
        --timeout 300 \
        --memory-size 2048 \
        --region $REGION 2>&1)

    CREATE_EXIT_CODE=$?

    if [ $CREATE_EXIT_CODE -eq 0 ]; then
        FUNCTION_ARN=$(echo "$CREATE_OUTPUT" | jq -r '.FunctionArn' 2>/dev/null || echo "unknown")
        echo "✓ Function created successfully: $FUNCTION_ARN"
    elif [ $CREATE_EXIT_CODE -eq 124 ]; then
        echo "Function creation timed out (60s)"
        echo "AWS CLI hung - try running the script again"
        exit 1
    else
        echo "Function creation failed:"
        echo "$CREATE_OUTPUT"
        exit 1
    fi
fi

echo "Waiting for function to be ready..."
sleep 30

# Force update function configuration to ensure new code is active
echo "Forcing function update..."
aws lambda update-function-configuration \
    --function-name $FUNCTION_NAME \
    --environment Variables="{UPLOAD_BUCKET=$UPLOAD_BUCKET,RESULTS_TABLE=$RESULTS_TABLE}" \
    --region $REGION > /dev/null 2>&1

echo "Waiting for configuration update..."
sleep 10
echo ""

# Part 7: Configure S3 trigger (same as before)
echo "Part 7: Configuring S3 trigger..."
if aws lambda add-permission \
    --function-name $FUNCTION_NAME \
    --principal s3.amazonaws.com \
    --action lambda:InvokeFunction \
    --source-arn arn:aws:s3:::$UPLOAD_BUCKET \
    --statement-id s3-trigger \
    --region $REGION > /dev/null 2>&1; then
    echo "✓ S3 permission added successfully"
else
    echo "Warning: S3 permission add failed (may already exist or function not ready)"
fi

# Create S3 notification configuration
cat > s3-notification.json << EOF
{
    "LambdaFunctionConfigurations": [
        {
            "Id": "ProcessUploadedFiles",
            "LambdaFunctionArn": "arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "uploads/"
                        }
                    ]
                }
            }
        }
    ]
}
EOF

if aws s3api put-bucket-notification-configuration \
    --bucket $UPLOAD_BUCKET \
    --notification-configuration file://s3-notification.json 2>/dev/null; then
    echo "✓ S3 notification configuration applied successfully"
else
    echo "Warning: S3 notification configuration failed - bucket may not exist"
fi
echo ""

# Part 8: Configure API Gateway Lambda integration
echo "Part 8: Configuring API Gateway integration..."

# Get API ID
API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text --region $REGION 2>/dev/null || echo "")

if [ ! -z "$API_ID" ] && [ "$API_ID" != "None" ]; then
    echo "✓ Found API Gateway: $API_ID"

    # Get proxy resource ID
    PROXY_RESOURCE_ID=$(aws apigateway get-resources --rest-api-id $API_ID --region $REGION --query 'items[?pathPart==`{proxy+}`].id' --output text 2>/dev/null || echo "")

    if [ ! -z "$PROXY_RESOURCE_ID" ] && [ "$PROXY_RESOURCE_ID" != "None" ]; then
        echo "✓ Found proxy resource: $PROXY_RESOURCE_ID"

        # Create Lambda integration
        LAMBDA_ARN="arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME"

        if aws apigateway put-integration \
            --rest-api-id $API_ID \
            --resource-id $PROXY_RESOURCE_ID \
            --http-method ANY \
            --type AWS_PROXY \
            --integration-http-method POST \
            --uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations" \
            --region $REGION > /dev/null 2>&1; then
            echo "✓ Lambda integration configured"
        else
            echo "Warning: Lambda integration failed (may already exist)"
        fi

        # Add Lambda permission for API Gateway
        if aws lambda add-permission \
            --function-name $FUNCTION_NAME \
            --statement-id api-gateway-invoke \
            --action lambda:InvokeFunction \
            --principal apigateway.amazonaws.com \
            --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*" \
            --region $REGION > /dev/null 2>&1; then
            echo "✓ API Gateway permissions added"
        else
            echo "Warning: Permission add failed (may already exist)"
        fi

        # Deploy API
        if aws apigateway create-deployment \
            --rest-api-id $API_ID \
            --stage-name prod \
            --region $REGION > /dev/null 2>&1; then
            echo "✓ API Gateway deployed"
        else
            echo "Warning: API deployment failed"
        fi

        echo "✓ API Gateway integration completed"
        echo "✓ Test URL: https://$API_ID.execute-api.$REGION.amazonaws.com/prod/health"
    else
        echo "Warning: Proxy resource not found - run API Gateway setup first"
    fi
else
    echo "Warning: API Gateway not found - run API Gateway setup first"
fi
echo ""

echo "Docker-based ML Lambda function deployed successfully!"
echo "✓ Function: $FUNCTION_NAME"
echo "✓ Image: $REPO_URI:$IMAGE_TAG"
echo "✓ Package type: Container"
echo "✓ S3 trigger configured"
echo "✓ API Gateway integration configured"
echo ""

# Clean up
rm -f lambda-trust-policy.json lambda-permissions-policy.json s3-notification.json

echo "Deployment completed successfully!"
echo ""
echo "Testing API Gateway endpoint..."
if command -v curl > /dev/null 2>&1; then
    echo "Testing: https://$API_ID.execute-api.$REGION.amazonaws.com/prod/health"

    HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" "https://$API_ID.execute-api.$REGION.amazonaws.com/prod/health" 2>/dev/null)
    HTTP_CODE=$(echo "$HEALTH_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$HEALTH_RESPONSE" | head -n -1)

    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ API Gateway health check successful"
        echo "Response: $RESPONSE_BODY"
    else
        echo -e "\033[31mWarning: API Gateway health check failed (HTTP $HTTP_CODE)\033[0m"
        echo "Response: $RESPONSE_BODY"
    fi
else
    echo "curl not available - skipping API test"
    echo "✓ Use this URL to test: https://$API_ID.execute-api.$REGION.amazonaws.com/prod/health"
fi
echo ""

echo "=== DEPLOYMENT SUMMARY ==="
echo "✓ Docker image built and pushed: $REPO_URI:$IMAGE_TAG"
echo "✓ Lambda function deployed: $FUNCTION_NAME"
echo "✓ S3 trigger configured for bucket: $UPLOAD_BUCKET"
echo "✓ DynamoDB table: $RESULTS_TABLE"
echo "✓ SES email service configured (verify your email if prompted)"
if [ ! -z "$API_ID" ] && [ "$API_ID" != "None" ]; then
    echo "✓ API Gateway integrated: https://$API_ID.execute-api.$REGION.amazonaws.com/prod"
else
    echo "⚠ API Gateway not found - run 04-create-api-gateway.sh first"
fi
echo ""
echo "Next steps:"
echo "1. Test the API endpoint: https://$API_ID.execute-api.$REGION.amazonaws.com/prod/health"
echo "2. Upload test files to S3: s3://$UPLOAD_BUCKET/uploads/"
echo "3. Check DynamoDB for processing results"
echo "4. Monitor CloudWatch logs for function execution"
echo ""
echo "--------------------------------DEPLOYMENT COMPLETE-----------------------------------"
