# CloudFront Distribution Setup

The `03-create-cloudfront.sh` script establishes a CloudFront distribution that serves as the global content delivery network (CDN) for the Chicago Crimes application. The script implements a secure architecture where S3 buckets remain private and CloudFront becomes the only public entry point, using Origin Access Control (OAC) for authentication and comprehensive security policies.

The script is designed with idempotency as a core principle, detecting existing distributions and reusing them while ensuring all associated policies remain current and correctly configured.

## Loading Shared Configuration and Enforcing Safe Execution

The script begins by enabling strict Bash execution modes and loading shared configuration.

```bash
set -euo pipefail

source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}
```

The `set -euo pipefail` directive ensures that the script exits immediately if any command fails, if an undefined variable is used, or if a pipeline command fails silently. This prevents partial CloudFront configuration, which could leave the CDN in an inconsistent or insecure state.

## Validating Required Tooling and Prerequisites

Before any CloudFront operations, the script validates that required tools are available.

```bash
command -v jq >/dev/null 2>&1 || {
  log_error "jq is required but not installed. Please install jq and retry."
  exit 1
}
```

The `command -v jq` check ensures that the JSON processor is available, as the script relies heavily on `jq` to extract values from AWS CLI JSON responses. The `>/dev/null 2>&1` redirection suppresses all output, making this a silent check.

### Automatic Cleanup of Temporary Files

```bash
trap 'rm -f cloudfront-config.json s3-cloudfront-policy.json upload-cors-policy.json' EXIT
```

A trap ensures that temporary JSON configuration files are deleted regardless of whether the script exits successfully or due to an error, preventing stale configuration files from being accidentally reused.

### S3 Bucket Prerequisites Verification

```bash
if ! aws s3api head-bucket --bucket "$STATIC_BUCKET" --profile "$AWS_PROFILE" 2>/dev/null; then
  log_error "Static bucket $STATIC_BUCKET does not exist. Run 01-create-s3-buckets.sh first."
  exit 1
fi
```

The script verifies that both required S3 buckets exist before proceeding:

- `aws s3api head-bucket` - Checks bucket existence without listing contents
- `--bucket "$STATIC_BUCKET"` - Specifies the bucket name from centralized configuration
- `--profile "$AWS_PROFILE"` - Uses the configured AWS CLI profile
- `2>/dev/null` - Suppresses error messages for cleaner output
- The `!` operator inverts the exit code, triggering the error condition if the bucket doesn't exist

## Checking for Existing CloudFront Distribution

The script implements sophisticated logic to detect and reuse existing CloudFront distributions.

```bash
EXISTING_DIST=$(aws cloudfront list-distributions \
  --profile "$AWS_PROFILE" \
  --query "DistributionList.Items[?Comment=='$DISTRIBUTION_COMMENT'].Id | [0]" \
  --output text 2>/dev/null || echo "")
```

This command uses advanced AWS CLI query capabilities:

- `list-distributions` - Retrieves all CloudFront distributions in the account
- `--query "DistributionList.Items[?Comment=='$DISTRIBUTION_COMMENT'].Id | [0]"` - JMESPath query that:
  - Filters distributions by matching comment field
  - Extracts the ID field from matching distributions
  - Takes the first result `[0]`
- `--output text` - Returns raw text instead of JSON
- `|| echo ""` - Provides empty string fallback if the command fails

### Handling Existing Distributions

When an existing distribution is found, the script retrieves additional information and updates associated policies:

```bash
if [[ -n "$EXISTING_DIST" && "$EXISTING_DIST" != "None" ]]; then
    DIST_STATUS=$(aws cloudfront get-distribution \
      --profile "$AWS_PROFILE" \
      --id "$EXISTING_DIST" \
      --query 'Distribution.Status' \
      --output text)
    
    DOMAIN_NAME=$(aws cloudfront get-distribution \
      --profile "$AWS_PROFILE" \
      --id "$EXISTING_DIST" \
      --query 'Distribution.DomainName' \
      --output text)
```

The dual condition `[[ -n "$EXISTING_DIST" && "$EXISTING_DIST" != "None" ]]` handles both empty results and the specific "None" string that AWS CLI returns when no results are found.

## Origin Access Control (OAC) Management

CloudFront requires an Origin Access Control to securely access private S3 buckets.

### Checking for Existing OAC

```bash
EXISTING_OAC=$(aws cloudfront list-origin-access-controls \
  --profile "$AWS_PROFILE" \
  --query "OriginAccessControlList.Items[?Name=='$OAC_NAME'].Id | [0]" \
  --output text 2>/dev/null || echo "")
```

Similar to distribution detection, this command searches for existing OACs by name to enable reuse.

### Creating New OAC

```bash
OAC_RESPONSE=$(aws cloudfront create-origin-access-control \
    --origin-access-control-config \
    Name="$OAC_NAME",Description="OAC for Chicago Crimes static website",OriginAccessControlOriginType="s3",SigningBehavior="always",SigningProtocol="sigv4" \
    --profile "$AWS_PROFILE")

OAC_ID=$(echo "$OAC_RESPONSE" | jq -r '.OriginAccessControl.Id')
```

The OAC configuration parameters:

- `Name="$OAC_NAME"` - Creates a consistent identifier from centralized configuration
- `Description="OAC for Chicago Crimes static website"` - Human-readable description
- `OriginAccessControlOriginType="s3"` - Restricts to S3 origins only
- `SigningBehavior="always"` - Ensures all requests are cryptographically signed
- `SigningProtocol="sigv4"` - Uses AWS Signature Version 4 for authentication

The `jq -r '.OriginAccessControl.Id'` extracts the OAC ID from the JSON response without quotes.

## CloudFront Distribution Configuration

The script creates a comprehensive JSON configuration for the CloudFront distribution.

```bash
cat > cloudfront-config.json << EOF
{
  "CallerReference": "chicago-crimes-$(date +%s)",
  "Comment": "$DISTRIBUTION_COMMENT",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "PriceClass": "PriceClass_100",
  "Origins": { ... },
  "DefaultCacheBehavior": { ... },
  "CustomErrorResponses": { ... }
}
EOF
```

### Core Distribution Settings

- `"CallerReference": "chicago-crimes-$(date +%s)"` - Unique identifier using timestamp to ensure uniqueness across creation attempts
- `"Comment": "$DISTRIBUTION_COMMENT"` - Uses centralized configuration for consistent identification
- `"Enabled": true` - Activates the distribution immediately after creation
- `"DefaultRootObject": "index.html"` - Serves the main application file for root URL requests
- `"PriceClass": "PriceClass_100"` - Selects cost-effective pricing tier (North America and Europe)

### Origins Configuration

```json
"Origins": {
  "Quantity": 1,
  "Items": [
    {
      "Id": "S3-$STATIC_BUCKET",
      "DomainName": "$STATIC_BUCKET.s3.$REGION.amazonaws.com",
      "OriginAccessControlId": "$OAC_ID",
      "S3OriginConfig": {
        "OriginAccessIdentity": ""
      }
    }
  ]
}
```

The origins configuration:

- `"Quantity": 1` - CloudFront API requirement for explicit array size declaration
- `"Id": "S3-$STATIC_BUCKET"` - Unique identifier linking cache behaviors to origins
- `"DomainName": "$STATIC_BUCKET.s3.$REGION.amazonaws.com"` - Full regional S3 endpoint
- `"OriginAccessControlId": "$OAC_ID"` - Links to the previously created OAC
- `"OriginAccessIdentity": ""` - Empty string disables deprecated OAI mechanism

### Default Cache Behavior Configuration

```json
"DefaultCacheBehavior": {
  "TargetOriginId": "S3-$STATIC_BUCKET",
  "ViewerProtocolPolicy": "redirect-to-https",
  "Compress": true,
  "AllowedMethods": {
    "Quantity": 2,
    "Items": ["GET", "HEAD"],
    "CachedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"]
    }
  },
  "ForwardedValues": {
    "QueryString": false,
    "Cookies": { "Forward": "none" }
  },
  "MinTTL": 0,
  "DefaultTTL": 86400,
  "MaxTTL": 31536000
}
```

Cache behavior settings:

- `"ViewerProtocolPolicy": "redirect-to-https"` - Automatically redirects HTTP to HTTPS
- `"Compress": true` - Enables automatic compression for supported content types
- `"AllowedMethods"` - Restricts to read-only operations (GET, HEAD)
- `"ForwardedValues"` - Prevents query strings and cookies from being forwarded to S3
- TTL settings provide flexible caching: immediate expiration (MinTTL: 0), 24-hour default (DefaultTTL: 86400), up to 1-year maximum (MaxTTL: 31536000)

### Custom Error Responses for SPA Support

```json
"CustomErrorResponses": {
  "Quantity": 1,
  "Items": [
    {
      "ErrorCode": 404,
      "ResponsePagePath": "/index.html",
      "ResponseCode": "200",
      "ErrorCachingMinTTL": 300
    }
  ]
}
```

This configuration supports single-page applications (SPAs):

- `"ErrorCode": 404` - Captures requests for non-existent files
- `"ResponsePagePath": "/index.html"` - Redirects to main application file
- `"ResponseCode": "200"` - Returns success status to prevent browser error handling
- `"ErrorCachingMinTTL": 300` - Limits error response caching to 5 minutes

## S3 Bucket Policy Configuration

After creating the distribution, the script updates the S3 bucket policy to allow access only from the specific CloudFront distribution.

```bash
cat > s3-cloudfront-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$STATIC_BUCKET/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DISTRIBUTION_ID"
        }
      }
    }
  ]
}
EOF
```

The bucket policy implements strict security controls:

- `"Principal": { "Service": "cloudfront.amazonaws.com" }` - Restricts access to CloudFront service
- `"Action": "s3:GetObject"` - Limits to read-only access
- `"Resource": "arn:aws:s3:::$STATIC_BUCKET/*"` - Applies to all objects in the bucket
- `"Condition"` with `"AWS:SourceArn"` - Ensures only the specific distribution can access the bucket

## Upload Bucket CORS Policy Update

The script updates the upload bucket's CORS policy to allow requests from the CloudFront domain.

```bash
cat > upload-cors-policy.json << EOF
{
  "CORSRules": [
    {
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
      "AllowedOrigins": ["https://$DOMAIN_NAME"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 86400
    }
  ]
}
EOF
```

The CORS configuration:

- `"AllowedOrigins": ["https://$DOMAIN_NAME"]` - Restricts requests to the CloudFront domain
- `"AllowedMethods"` - Enables full HTTP method support for file operations
- `"ExposeHeaders": ["ETag"]` - Makes ETag header available for upload verification
- `"MaxAgeSeconds": 86400` - Caches CORS preflight responses for 24 hours

## Script Completion and Operational Guidance

The script concludes with comprehensive information about the created infrastructure and next steps in the deployment pipeline.

## How to Run the Script

To execute the script:

```bash
./03-create-cloudfront.sh
```

The script can be safely re-run multiple times, as it detects existing distributions and updates associated policies to ensure current configuration. CloudFront distribution deployment is asynchronous and may take 10-15 minutes to become fully available globally.
