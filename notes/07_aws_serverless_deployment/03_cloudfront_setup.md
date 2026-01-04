
# CloudFront Distribution Setup

The `03-create-cloudfront.sh` script is responsible for placing Amazon CloudFront in front of a private S3 bucket so that static website files can be served securely over HTTPS, globally, and without exposing the S3 bucket directly to the public internet. The overall design choice here is intentional: S3 remains private, CloudFront becomes the only public entry point, and access is tightly controlled using AWS-native mechanisms.

The script is written defensively and idempotently, meaning it can be run multiple times without accidentally creating duplicate infrastructure or breaking existing resources.

## Loading Shared Configuration and Enforcing Safe Execution

The script begins by enabling strict Bash execution modes and loading shared configuration and helper functions.

```bash
set -euo pipefail

source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}
```

The `set -euo pipefail` line ensures that the script exits immediately if any command fails, if an undefined variable is used, or if a pipeline command fails silently. This prevents partial infrastructure creation, which is especially important when working with cloud resources that incur cost or security risk.

Sourcing `00-config.sh` centralizes environment-specific values such as bucket names, AWS region, account ID, and logging helpers. If this file cannot be loaded, the script exits immediately because none of the downstream logic can safely run without it.

## Validating Required Tooling Early

Before any AWS calls are made, the script checks that `jq` is installed.

```bash
command -v jq >/dev/null 2>&1 || {
  log_error "jq is required but not installed. Please install jq and retry."
  exit 1
}
```

This check exists because AWS CLI responses are JSON, and the script relies on `jq` to extract values such as distribution IDs and domain names. Failing early avoids confusing errors later in the script where JSON parsing would silently break.

## Automatic Cleanup of Temporary Files

A trap is set to ensure that temporary JSON configuration files are deleted regardless of whether the script exits successfully or due to an error.

```bash
trap 'rm -f cloudfront-config.json s3-cloudfront-policy.json upload-cors-policy.json' EXIT
```

This keeps the project directory clean and prevents stale configuration files from being accidentally reused or committed to version control.

### Checking for an Existing CloudFront Distribution

Before creating anything, the script checks whether a CloudFront distribution with the expected comment already exists. The existing distribution detection uses advanced AWS CLI query capabilities with JMESPath syntax to search for distributions based on the comment field. The query string demonstrates several advanced techniques:

```bash
EXISTING_DIST=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='$DISTRIBUTION_COMMENT'].Id | [0]" \
  --output text)
```

- the `[?Comment=='$DISTRIBUTION_COMMENT']` filter selects only distributions with matching comments, while
- the `.Id | [0]` projection extracts the ID field from the first matching result.

The reasoning here is idempotency. CloudFront distributions are global resources and expensive to duplicate unintentionally. By using a known comment as an identifier, the script can safely detect and reuse an existing distribution rather than creating a new one.

The conditional logic implements robust checking that handles both empty results and the specific "None" string that AWS CLI returns when no results are found.

```sh
[[ -n "$EXISTING_DIST" && "$EXISTING_DIST" != "None" ]]
```

This dual checking mechanism prevents the script from attempting to use "None" as a valid distribution ID, which was identified as a specific failure mode during development and testing.

When an existing distribution is found, the script retrieves the domain name and provides clear feedback to the user about the existing resource.

```sh
aws cloudfront get-distribution \
  --id "$EXISTING_DIST" \
  --query 'Distribution.DomainName'
```

This approach eliminates unnecessary resource creation while ensuring users have the information needed to proceed with their deployment workflow.

## Creating or Reusing an Origin Access Control (OAC)

CloudFront needs a secure way to access a private S3 bucket. This is done using an Origin Access Control (OAC), which replaces the older Origin Access Identity (OAI) model.

```bash
OAC_NAME="$OAC_NAME"
```

The OAC name is intentionally stable and human-readable. This avoids collisions and uncontrolled resource sprawl while still allowing safe reuse across runs. The name assignment from centralized configuration ensures consistency across all deployment environments while allowing customization for different projects or environments.

The OAC detection follows the same pattern as distribution detection given that it checks for an existing OAC with that name and reuses it if found. If not, it creates a new one to avoid duplicate OAC:

```bash
aws cloudfront create-origin-access-control \
  --origin-access-control-config \
  # ... omitted command discussed below
```

The command above accepts a complex configuration string that defines multiple security aspects:

- The `Name="$OAC_NAME"` parameter creates a consistent identifier that enables resource reuse and management across deployments.
- The `Description="OAC for Chicago Crimes static website"` parameter provides human-readable documentation that appears in the AWS console and supports operational management.
- The `OriginAccessControlOriginType="s3"` parameter restricts the OAC to S3 origins, preventing its misuse with other origin types.
- The `SigningBehavior="always"` parameter ensures that all requests from CloudFront to S3 are cryptographically signed, providing authentication and integrity protection.
- The `SigningProtocol="sigv4"` parameter specifies the use of AWS Signature Version 4, the current standard for AWS API authentication.

This configuration ensures CloudFront is the *only* entity allowed to read from the bucket.

With that done, the OAC ID is extracted as a raw string output without JSON quotes through the `jq -r` flag. This ensures that the extracted ID can be used directly in subsequent AWS CLI commands without additional processing.

```sh
OAC_ID=$(echo "$OAC_RESPONSE" | jq -r '.OriginAccessControl.Id')
```

## Building the CloudFront Distribution Configuration

The CloudFront distribution configuration represents the most complex aspect of the script, involving a comprehensive JSON structure that defines caching behavior, origin settings, security policies, and error handling mechanisms.

- The `"CallerReference": "chicago-crimes-$(date +%s)"` field provides a unique identifier for each distribution creation request. CloudFront requires this field to be unique across all creation attempts, and the timestamp-based approach using `$(date +%s)` ensures uniqueness while providing a meaningful reference for troubleshooting and auditing purposes.

- The `"Comment": "$DISTRIBUTION_COMMENT"` field uses centralized configuration to provide consistent, human-readable identification of the distribution's purpose. This comment appears prominently in the CloudFront console and enables easy identification among potentially many distributions in an AWS account.

- The `"Enabled": true` setting ensures that the distribution begins serving traffic immediately after creation, while `"DefaultRootObject": "index.html"` configures the distribution to serve the main application file when users access the root URL.

- The `"PriceClass": "PriceClass_100"` configuration selects the most cost-effective CloudFront pricing tier, which includes edge locations in North America and Europe. This choice balances cost optimization with performance for the target user base while avoiding the higher costs associated with global edge location coverage.

### Origin Configuration and S3 Integration

The origins configuration section defines how CloudFront connects to and retrieves content from the S3 bucket, implementing the secure access patterns enabled by the Origin Access Control.

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

The origins array structure with `"Quantity": 1` and a single item in the `"Items"` array reflects CloudFront's API design, which requires explicit quantity declarations for array elements. This pattern appears throughout CloudFront configurations and represents AWS's approach to API consistency and validation.

The origin configuration includes several critical elements:

- The `"Id": "S3-$STATIC_BUCKET"` parameter creates a unique identifier that links cache behaviors to specific origins. The prefix pattern helps identify the origin type in complex distributions with multiple origins.
- The `"DomainName": "$STATIC_BUCKET.s3.$REGION.amazonaws.com"` parameter specifies the full S3 bucket domain name, including the region-specific endpoint. This explicit regional specification ensures correct routing and avoids potential issues with S3's global namespace.
- The `"OriginAccessControlId": "$OAC_ID"` parameter links the origin to the previously created OAC, enabling secure access to the private S3 bucket.
- The `"S3OriginConfig"` section with `"OriginAccessIdentity": ""` explicitly disables the deprecated OAI mechanism, ensuring that only the modern OAC approach is used for authentication.

### Cache Behavior Configuration and Performance Optimization

The default cache behavior configuration defines how CloudFront handles requests, implements security policies, and optimizes content delivery performance.

```json
"DefaultCacheBehavior": {
    "TargetOriginId": "S3-$STATIC_BUCKET",
    "ViewerProtocolPolicy": "redirect-to-https",
    "Compress": true,
}
```

- The `"TargetOriginId": "S3-$STATIC_BUCKET"` parameter links the cache behavior to the S3 origin, establishing the routing relationship between incoming requests and the content source.

- The `"ViewerProtocolPolicy": "redirect-to-https"` setting implements a critical security policy by automatically redirecting all HTTP requests to HTTPS. This configuration ensures that all user interactions with the application are encrypted, protecting against man-in-the-middle attacks and meeting modern security standards for web applications.

- The `"Compress": true` setting enables CloudFront's automatic compression for supported content types, reducing bandwidth usage and improving page load times for users. This optimization is particularly beneficial for text-based content like HTML, CSS, and JavaScript files.

The allowed methods configuration uses a nested structure that defines both allowed and cached methods:

```json
"AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    }
```

- `"Quantity": 2` and `"Items": ["GET", "HEAD"]` restricts the distribution to read-only operations, preventing unauthorized modification attempts.
- The `"CachedMethods"` subsection with the same `GET` and `HEAD` methods ensures that CloudFront caches responses for these operations, improving performance for repeated requests.

The forwarded values configuration controls which request parameters CloudFront forwards to the origin:

```json
"ForwardedValues": {
      "QueryString": false,
      "Cookies": { "Forward": "none" }
    }
```

- Setting the `"QueryString"` to `false` prevents query parameters from being forwarded to S3, which is appropriate for static content where query parameters don't affect the response. This configuration also improves cache efficiency by treating URLs with different query parameters as the same cached object.
- The `"Cookies": {"Forward": "none"}` configuration prevents cookie forwarding, which is unnecessary for static content and improves caching efficiency by avoiding cache fragmentation based on cookie values.

The TTL (Time To Live) configuration defines caching duration with three parameters:

- The `"MinTTL": 0` setting allows immediate cache expiration when explicitly requested through cache-control headers.
- The `"DefaultTTL": 86400` setting establishes a 24-hour default cache duration, providing good performance while allowing reasonable content freshness.
- The `"MaxTTL": 31536000` setting allows content to be cached for up to one year, enabling aggressive caching for truly static assets like images and fonts.

### Error Handling and Single-Page Application Support

The custom error responses configuration implements sophisticated error handling that supports modern single-page application (SPA) architectures while providing user-friendly error experiences.

The error response configuration addresses the common challenge of client-side routing in SPAs, where the browser requests URLs that don't correspond to actual files on the server.

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

The configuration includes:

- The `"ErrorCode": 404` parameter captures requests for non-existent files, which commonly occur when users directly access SPA routes or refresh pages on client-side routes.
- The `"ResponsePagePath": "/index.html"` parameter redirects these requests to the main application file, allowing the client-side router to handle the URL appropriately.
- The `"ResponseCode": "200"` parameter returns a successful HTTP status code, preventing browser error handling while allowing the application to manage the routing internally.
- The `"ErrorCachingMinTTL": 300` parameter limits caching of error responses to 5 minutes, ensuring that temporary issues don't persist indefinitely while still providing some caching benefit.

## Creating the CloudFront Distribution

With the configuration prepared, the distribution is created:

```bash
run_aws aws cloudfront create-distribution \
  --distribution-config file://cloudfront-config.json
```

With the distribution created, the script then extracts the distribution ID using `jq`, which is required for subsequent operation like policy updates and cache invalidation. It also extracts the CloudFront domain name, which users need to access the application and which must be configured in CORS policies.

## Locking Down the S3 Bucket Policy

Once CloudFront exists, the S3 bucket policy is updated to allow access **only** from this specific distribution.

The policy structure follows AWS IAM policy syntax with explicit version declaration and statement arrays. The `"Version": "2012-10-17"` field specifies the current IAM policy language version, ensuring compatibility with all IAM features.

```json
# ...omitted for brevity
"Principal": { "Service": "cloudfront.amazonaws.com" },
"Condition": {
  "StringEquals": {
    "AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DISTRIBUTION_ID"
  }
}
# ...omitted for brevity
```

The statement configuration implements several security principles:

- The `"Sid"` parameter provides a human-readable identifier for the policy statement, supporting policy management and auditing.
- The `"Effect"` parameter with the `"Allow"` argument grants access, while the specific conditions ensure that this access is tightly controlled.
- The `"Principal"` parameter restricts access to the CloudFront service, preventing direct access from other AWS services or external entities.
- The `"Action": "s3:GetObject"` parameter limits the granted permission to read-only access, preventing modification or deletion of bucket contents.
- The `"Resource": "arn:aws:s3:::$STATIC_BUCKET/*"` parameter restricts access to objects within the specific bucket, using the wildcard to include all objects while excluding bucket-level operations.

The condition block implements the most critical security control:

- The `"StringEquals"` condition type requires exact matching of the specified attribute.
- The `"AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DISTRIBUTION_ID"` condition ensures that only the specific CloudFront distribution can access the bucket, preventing access from other distributions even within the same AWS account.

## Updating the upload bucket CORS policy

The CORS (Cross-Origin Resource Sharing) policy update for the upload bucket enables secure file uploads from the web application while preventing unauthorized cross-origin requests.

The CORS configuration addresses the browser's same-origin policy, which would otherwise prevent the web application from uploading files directly to S3.

```json
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
```

The configuration includes:

- The `"AllowedHeaders": ["*"]` parameter permits all request headers, providing flexibility for various upload scenarios while maintaining security through origin restrictions.
- The `"AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"]` parameter enables the full range of HTTP methods required for file upload operations, including multipart uploads and cleanup operations.
- The `"AllowedOrigins": ["https://$DOMAIN_NAME"]` parameter restricts requests to the specific CloudFront domain, preventing unauthorized sites from using the upload functionality.
- The `"ExposeHeaders": ["ETag"]` parameter allows the browser to access the ETag header, which is commonly used for upload verification and caching decisions.
- The `"MaxAgeSeconds": 86400` parameter caches the CORS preflight response for 24 hours, reducing the overhead of CORS checks for repeated requests.

## Final output and operational guidance

At the end of the script, the user is informed that CloudFront deployment is asynchronous and may take 10–15 minutes. This is important because CloudFront resources are not immediately available after creation.

The script also reminds the user to:

- Update the API endpoint in the frontend code
- Redeploy the static site
- Invalidate CloudFront cache if necessary

These steps are operationally required because CloudFront caches content aggressively by design.

## How to run the script

To run the script normally:

```bash
./03-create-cloudfront.sh
```

Because the script is idempotent, it can be safely re-run if something fails midway or if configuration changes are introduced later.
