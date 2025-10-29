# CloudFront Distribution and Origin Access Control: Global Content Delivery Implementation

The CloudFront distribution script represents the most complex component of our serverless foundation, implementing global content delivery with sophisticated security controls and performance optimizations. This script, `03-create-cloudfront.sh`, transforms our private S3 bucket into a globally accessible web application while maintaining strict security through Origin Access Control mechanisms. Understanding this script requires deep knowledge of both AWS CLI operations and the intricate relationships between CloudFront, S3, and IAM security policies.

## Script Initialization and Configuration Management

The CloudFront deployment script follows the established pattern of bash initialization and configuration loading, but the complexity of CloudFront requires additional error handling and validation mechanisms.

- The script begins with the familiar `#!/bin/bash` shebang and `set -e` error handling directive, ensuring that any failure in the complex CloudFront configuration process stops execution immediately rather than creating partially configured resources.

- The configuration loading mechanism uses `source "$(dirname "$0")/00-config.sh"` to import the centralized configuration variables that define bucket names, account IDs, and regional settings.
  - This centralized approach becomes particularly important for CloudFront because the service involves multiple AWS regions and requires precise coordination between different AWS services.
  - The CloudFront service itself is global, but it must reference region-specific S3 buckets and account-specific IAM policies, making consistent configuration critical for successful deployment.

- The script's opening echo statement provides user feedback about the complex process that's beginning.

    ```sh
    `echo "Creating CloudFront distribution with Origin Access Control..."
    ```

  - CloudFront distributions can take 10-15 minutes to deploy globally, so clear communication about the process helps users understand that the deployment is progressing normally even when it appears to be taking a long time.

## Origin Access Control Creation and Management

The Origin Access Control (OAC) creation represents one of the most sophisticated aspects of the CloudFront deployment, implementing AWS's modern security model for CloudFront-to-S3 communication. The script begins by checking for existing OACs to avoid the common error of attempting to create duplicate resources.

The command below demonstrates advanced AWS CLI query capabilities using JMESPath syntax.

```sh
aws cloudfront \
    list-origin-access-controls \
    --query "OriginAccessControlList.Items[?Name=='chicago-crimes-oac'].Id" \
    --output text
```

- The `--query` parameter filters the results to find OACs with names matching our application, while the `[?Name=='chicago-crimes-oac']` syntax uses JMESPath filtering to select only items where the Name field equals our specific value.
- The `.Id` suffix extracts only the ID field from matching items, and `--output text` returns the result as plain text rather than JSON, making it suitable for direct assignment to bash variables.

In AWS console terms, this query is equivalent to navigating to the CloudFront service, selecting "Origin access control" from the left sidebar, and manually searching through the list of OACs to find one with the name "chicago-crimes-oac." The CLI approach automates this search and returns the ID directly, eliminating the manual steps required in the console.

The conditional logic implements robust checking for existing OACs.

```sh
if [ ! -z "$EXISTING_OAC" ] && [ "$EXISTING_OAC" != "None" ]; then
```

- The `! -z` test checks whether the variable is not empty, while the `!= "None"` comparison handles the specific case where AWS CLI returns the string "None" when no results are found. This dual checking mechanism prevents the script from attempting to use "None" as a valid OAC ID, which was a specific issue we encountered during development and resolved through iterative testing.

When no existing OAC is found, the script creates a new one using `aws cloudfront create-origin-access-control` with a comprehensive configuration.

- The `--origin-access-control-config` parameter accepts a complex configuration string that defines the OAC's behavior.
- The `Name="chicago-crimes-oac-$TIMESTAMP"` parameter creates a unique name by appending a timestamp, ensuring that multiple deployments don't conflict with each other. This approach was developed after encountering naming conflicts during testing and represents a robust solution for environments where multiple developers might be deploying simultaneously.
- The `Description="OAC for Chicago Crimes static website"` parameter provides human-readable documentation about the OAC's purpose, which appears in the AWS console and helps with resource management.
- The `OriginAccessControlOriginType="s3"` parameter specifies that this OAC is designed for S3 origins, while `SigningBehavior="always"` and `SigningProtocol="sigv4"` configure the cryptographic signing behavior that authenticates CloudFront requests to S3.

In the AWS console, creating an OAC involves navigating to CloudFront, selecting "Origin access control" from the sidebar, clicking "Create control setting," entering the name and description, selecting "S3" as the origin type, and configuring the signing settings. The CLI approach automates these steps while ensuring consistent configuration across deployments.

The OAC ID extraction uses the command below to parse the JSON response from the creation command.

```sh
echo $OAC_RESPONSE | jq -r '.OriginAccessControl.Id'
```

- The `jq` tool is essential for processing JSON responses from AWS CLI commands, and the `-r` flag returns raw string output without JSON quotes. This extracted ID is crucial for subsequent configuration steps that reference the OAC.

## CloudFront Distribution Configuration

The CloudFront distribution configuration represents the most complex part of the script, involving a large JSON configuration that defines caching behavior, origin settings, and security policies. The script uses a here-document (heredoc) to embed this JSON configuration directly in the bash script, making the configuration visible and maintainable within the deployment automation.

The `cat > cloudfront-config.json << EOF` syntax begins the heredoc that will create the CloudFront configuration file.

- This approach keeps the configuration close to where it's used while allowing complex JSON structures to be embedded in the bash script without complicated escaping.
- The configuration file is temporary and will be cleaned up after use, ensuring that sensitive configuration doesn't remain on the filesystem.

The `"CallerReference": "chicago-crimes-$(date +%s)"` field provides a unique identifier for the distribution creation request. CloudFront requires this field to be unique for each creation attempt, and using `$(date +%s)` generates a timestamp-based unique value. This approach prevents errors when attempting to create multiple distributions or retry failed deployments.

The `"Comment": "$DISTRIBUTION_COMMENT"` field uses the centralized configuration to provide a human-readable description of the distribution. This comment appears in the CloudFront console and helps identify the distribution's purpose among potentially many distributions in an AWS account.

--- subtopic here ---

The `"DefaultCacheBehavior"` section defines how CloudFront handles requests and caching for this distribution.

- The `"TargetOriginId": "S3-$STATIC_BUCKET"` parameter links this cache behavior to the S3 origin that will be defined later in the configuration.
- The `"ViewerProtocolPolicy": "redirect-to-https"` setting ensures that all HTTP requests are automatically redirected to HTTPS, providing security for user interactions with the application.
- The `"TrustedSigners"` configuration with `"Enabled": false` indicates that this distribution doesn't use signed URLs or signed cookies for access control. For a public web application, this is appropriate, but the configuration could be modified to enable signed URLs for restricted access scenarios.
- The `"ForwardedValues"` section controls which request parameters CloudFront forwards to the origin.
  - The `"QueryString": false` setting means that query parameters in URLs won't be forwarded to S3, which is appropriate for static content where query parameters don't affect the response.
  - The `"Cookies": {"Forward": "none"}` configuration similarly prevents cookie forwarding, which is unnecessary for static content and improves caching efficiency.

- The caching time configuration uses `"MinTTL": 0`, `"DefaultTTL": 86400`, and `"MaxTTL": 31536000` to define minimum, default, and maximum cache times in seconds.
  - The default TTL of 86400 seconds (24 hours) provides good performance for static content while allowing daily updates.
  - The maximum TTL of 31536000 seconds (1 year) allows for very long caching of content that rarely changes, while the minimum TTL of 0 allows for immediate cache expiration when necessary.

- The `"Compress": true` setting enables automatic compression of text-based content, reducing bandwidth usage and improving load times for users. CloudFront automatically compresses CSS, JavaScript, HTML, and other text-based content when this setting is enabled.

- The `"AllowedMethods"` configuration specifies which HTTP methods CloudFront will accept and cache.
  - The `"Items": ["GET", "HEAD"]` setting restricts the distribution to read-only operations, which is appropriate for static content hosting.
  - The `"CachedMethods"` subsection specifies that both GET and HEAD requests will be cached, optimizing performance for these common operations.

### Origin Configuration and S3 Integration

The `"Origins"` section defines the S3 bucket that serves as the source for CloudFront content.

- The `"Id": "S3-$STATIC_BUCKET"` parameter creates a unique identifier that links back to the cache behavior configuration.
- The `"DomainName": "$STATIC_BUCKET.s3.$REGION.amazonaws.com"` parameter specifies the S3 bucket's regional endpoint, which is important for performance and ensures that CloudFront connects to the bucket in the correct region.

- The `"S3OriginConfig"` section with `"OriginAccessIdentity": ""` represents the legacy approach to S3-CloudFront integration.
  - By leaving this empty, we indicate that we're using the modern Origin Access Control approach instead of the older Origin Access Identity method. This configuration choice reflects AWS's current best practices and provides better security and functionality.

- The `"OriginAccessControlId": "$OAC_ID"` parameter links the distribution to the OAC created earlier in the script. This connection is crucial for security because it tells CloudFront to use the OAC for authenticating requests to S3, while the corresponding S3 bucket policy will restrict access to only this specific OAC.

### Distribution Behavior and Error Handling

The `"Enabled": true` setting ensures that the distribution is active immediately after creation. Setting this to false would create the distribution but leave it disabled, requiring a separate activation step. For automated deployment, immediate activation is typically desired.

The `"DefaultRootObject": "index.html"` configuration tells CloudFront what file to serve when users request the root URL of the distribution. This is equivalent to the "Default root object" setting in the CloudFront console and ensures that users accessing the main domain see the application's home page.

The `"CustomErrorResponses"` section implements single-page application (SPA) behavior by redirecting 404 errors to the main application page.

- The configuration below means that when CloudFront encounters a 404 error (typically from requests for client-side routes), it will serve the index.html file with a 200 status code instead. This allows JavaScript-based routing to handle the request appropriately.

    ```sh
        # code ignored for brevity
        {
        "ErrorCode": 404,
        "ResponsePagePath": "/index.html",
        "ResponseCode": "200"
        ...
        }
    ```

- The `"ErrorCachingMinTTL": 300` setting caches error responses for 5 minutes, preventing repeated requests for non-existent resources from overwhelming the origin while still allowing relatively quick recovery when content is added.

The `"PriceClass": "PriceClass_100"` setting optimizes costs by using only the most cost-effective CloudFront edge locations. This provides good global coverage while minimizing expenses, which is appropriate for applications that don't require the absolute lowest latency worldwide.

## Distribution Creation and Response Processing

The distribution creation command below uses the `file://` prefix to read the configuration from the JSON file created by the heredoc. This approach is necessary because the configuration is too complex to specify directly on the command line.

```sh
aws cloudfront create-distribution \
    --distribution-config file://cloudfront-config.json
```

The response processing extracts key information from the creation response using `jq` commands with the following commands:

```sh
DISTRIBUTION_ID=$(echo $DISTRIBUTION_RESPONSE | jq -r '.Distribution.Id')
DOMAIN_NAME=$(echo $DISTRIBUTION_RESPONSE | jq -r '.Distribution.DomainName')
```

- The `DISTRIBUTION_ID` is the unique distribution ID that will be needed for subsequent operations like invalidations or updates while `DOMAIN_NAME` is the CloudFront domain name that users will use to access the application. In the AWS console, this information would be visible immediately after distribution creation in the CloudFront distributions list, showing the distribution ID, domain name, and deployment status.

## S3 Bucket Policy Configuration for CloudFront Access

The S3 bucket policy configuration represents the security integration between CloudFront and S3, ensuring that only the specific CloudFront distribution can access the S3 bucket contents. This policy is created using another heredoc that generates the JSON policy document.

- The policy structure follows AWS IAM policy syntax with `"Version": "2012-10-17"` indicating the policy language version.
- The `"Statement"` array contains the specific permissions being granted.

  - The `"Sid": "AllowCloudFrontServicePrincipal"` field provides a human-readable identifier for this policy statement.
  - The `"Effect": "Allow"` field grants permission rather than denying it.
  - The `"Principal": {"Service": "cloudfront.amazonaws.com"}` field specifies that the CloudFront service is being granted access, rather than a specific user or role.
  - The `"Action": "s3:GetObject"` field grants permission to read objects from the bucket, which is the minimum permission needed for CloudFront to serve content.
  - The `"Resource": "arn:aws:s3:::$STATIC_BUCKET/*"` field specifies that this permission applies to all objects in the static bucket, using the `/*` wildcard to include all objects.
  - The `"Condition"` section implements the crucial security restriction that limits access to only the specific CloudFront distribution. As shown in the command below, the  condition ensures that only requests from the specific distribution can access the bucket. This prevents direct access to S3 objects while allowing CloudFront to serve them globally.

    ```sh
    "StringEquals": {
        "AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DISTRIBUTION_ID"
        }
    ```

To apply the policy to the bucket, we then use:

```sh
aws s3api put-bucket-policy \
    --bucket $STATIC_BUCKET \
    --policy file://s3-cloudfront-policy.json
```

In the AWS console, this would involve navigating to the S3 bucket, selecting the Permissions tab, editing the bucket policy, and pasting the JSON policy document.

## Error Handling and Pitfall Prevention

The CloudFront script implements several error handling mechanisms that address common deployment issues we encountered during development. The OAC existence checking prevents the `"OriginAccessControlAlreadyExists"` error that occurs when attempting to create duplicate OACs. The timestamp-based naming approach ensures that even when OACs exist, new ones can be created with unique names.

The dual checking for empty strings and `"None"` values addresses the specific behavior of AWS CLI when no results are found. This was a particular issue we discovered during testing, where the CLI would return `"None"` as a string rather than an empty result, causing the script to attempt to use `"None"` as a valid OAC ID.

The cleanup operations at the end of the script remove temporary JSON files that contain configuration information. While these files don't contain secrets in this case, establishing good cleanup practices prevents security issues in more complex deployments.

```sh
rm -f cloudfront-config.json s3-cloudfront-policy.json
```

The comprehensive error output and status reporting help users understand the deployment progress and identify issues when they occur. CloudFront deployments can take significant time, so clear communication about the process helps prevent users from assuming the deployment has failed when it's actually progressing normally.

## AWS Console Equivalents and Manual Verification

Understanding the AWS console equivalents for the CloudFront deployment helps with troubleshooting and verification of the automated deployment. Creating a CloudFront distribution through the console involves navigating to the CloudFront service, clicking "Create distribution," selecting "Single website or app" as the delivery method, and configuring numerous settings across multiple pages.

The origin configuration in the console requires selecting "S3" as the origin type, entering the S3 bucket domain name, and configuring the Origin Access Control settings. The cache behavior configuration involves setting up default cache behaviors, allowed HTTP methods, and caching policies. The distribution settings page includes options for price class, custom error pages, and other advanced settings.

The OAC creation through the console involves a separate process in the CloudFront Origin Access Control section, where you create the control setting and then reference it in the distribution configuration. The S3 bucket policy must be configured separately in the S3 console, requiring navigation to the bucket's permissions tab and manual entry of the policy JSON.

The automated approach provided by the script offers significant advantages over manual console configuration, including consistency, repeatability, and the ability to deploy to multiple environments reliably. However, understanding the console equivalents provides valuable context for troubleshooting and helps in understanding the relationships between different AWS services and their configurations.
