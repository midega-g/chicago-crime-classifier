# S3 Bucket Infrastructure Setup

The `01-create-s3-buckets.sh` script establishes the foundational S3 storage infrastructure for the Chicago Crimes serverless application. The script creates and configures two distinct S3 buckets with different security profiles, lifecycle policies, and access patterns to support both static website hosting and file upload operations.

The script is designed with idempotency as a core principle, meaning it can be executed multiple times safely without creating duplicate resources or corrupting existing configurations. This design supports both manual deployment workflows and automated CI/CD pipelines.

## Loading Shared Configuration and Enforcing Safe Execution

The script begins by enabling strict Bash execution modes and loading shared configuration.

```bash
set -euo pipefail

source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}
```

The `set -euo pipefail` directive ensures that the script exits immediately if any command fails, if an undefined variable is used, or if a pipeline command fails silently. This prevents partial infrastructure creation, which is especially important when working with cloud resources that incur costs or security risks.

Sourcing `00-config.sh` centralizes environment-specific values such as bucket names, AWS region, account ID, and logging helpers. If this file cannot be loaded, the script exits immediately because none of the downstream logic can safely run without it.

## Automatic Cleanup of Temporary Files

A trap is set to ensure that temporary JSON configuration files are deleted regardless of whether the script exits successfully or due to an error.

```bash
trap 'rm -f upload-lifecycle-policy.json upload-cors-policy.json' EXIT
```

This keeps the project directory clean and prevents stale configuration files from being accidentally reused or committed to version control.

## Bucket Configuration Helper Function

The script defines a reusable function for applying consistent security configuration to both buckets.

```bash
apply_bucket_config() {
  local bucket="$1"
  local bucket_type="$2"

  # Ownership controls
  aws s3api put-bucket-ownership-controls \
    --bucket "$bucket" \
    --ownership-controls '{
      "Rules": [{"ObjectOwnership": "BucketOwnerEnforced"}]
    }' >/dev/null

  # Public access block
  aws s3api put-public-access-block \
    --bucket "$bucket" \
    --public-access-block-configuration '{
      "BlockPublicAcls": true,
      "IgnorePublicAcls": true,
      "BlockPublicPolicy": true,
      "RestrictPublicBuckets": true
    }' >/dev/null
}
```

### Ownership Controls Configuration

The `put-bucket-ownership-controls` command applies a JSON configuration that enforces bucket owner control over all objects:

- `"ObjectOwnership": "BucketOwnerEnforced"` - Forces the bucket owner to own all objects regardless of who uploads them
- This prevents permission issues caused by object-level ACLs and aligns with AWS security best practices
- The `>/dev/null` redirection suppresses command output for cleaner script execution

### Public Access Block Configuration

The `put-public-access-block` command applies comprehensive public access restrictions:

- `"BlockPublicAcls": true` - Prevents new public ACLs from being applied to the bucket or objects
- `"IgnorePublicAcls": true` - Ignores any existing public ACLs on the bucket or objects
- `"BlockPublicPolicy": true` - Prevents public bucket policies from being applied
- `"RestrictPublicBuckets": true` - Restricts access to buckets with public policies

This configuration provides defense-in-depth security by blocking all forms of public access, even if accidentally configured later.

## Static Website Bucket Creation and Configuration

The script checks for the existence of the static website bucket and creates it if necessary.

```bash
if aws s3api head-bucket --bucket "$STATIC_BUCKET" 2>/dev/null; then
  log_success "Bucket ${YELLOW}$STATIC_BUCKET${NC} exists"
else
  log_info "Creating static website bucket..."
  aws s3 mb "s3://$STATIC_BUCKET" --region "$REGION" --profile "$AWS_PROFILE"
  log_success "Static bucket created: ${YELLOW}$STATIC_BUCKET${NC}"
fi
```

### Bucket Existence Check

The `aws s3api head-bucket` command checks if a bucket exists without listing its contents:

- `--bucket "$STATIC_BUCKET"` - Specifies the bucket name from centralized configuration
- `2>/dev/null` - Redirects stderr to suppress error messages for non-existent buckets
- The command returns exit code 0 if the bucket exists, non-zero otherwise

### Bucket Creation

The `aws s3 mb` command creates a new S3 bucket:

- `s3://$STATIC_BUCKET` - Specifies the bucket name with S3 URI format
- `--region "$REGION"` - Explicitly sets the AWS region for the bucket
- `--profile "$AWS_PROFILE"` - Uses the specified AWS CLI profile for authentication

Explicit region specification ensures predictable bucket placement and avoids region-related access issues.

## Upload Bucket Creation and Advanced Configuration

The upload bucket follows the same creation pattern but receives additional configuration for lifecycle management, versioning, and CORS.

### Lifecycle Policy Configuration

The script creates a comprehensive lifecycle policy to manage storage costs and data retention.

```bash
cat > upload-lifecycle-policy.json <<EOF
{
  "Rules": [
    {
      "ID": "DeleteUploadsAfter1Day",
      "Status": "Enabled",
      "Filter": {},
      "Expiration": { "Days": 1 },
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 1
      }
    }
  ]
}
EOF
```

The lifecycle policy JSON structure includes:

- `"ID": "DeleteUploadsAfter1Day"` - Human-readable identifier for the lifecycle rule
- `"Status": "Enabled"` - Activates the lifecycle rule immediately
- `"Filter": {}` - Empty filter applies the rule to all objects in the bucket
- `"Expiration": { "Days": 1 }` - Automatically deletes objects after 1 day
- `"AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 1 }` - Cleans up failed multipart uploads after 1 day

This configuration prevents storage cost accumulation from temporary files and abandoned uploads.

The policy is applied using:

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket "$UPLOAD_BUCKET" \
  --lifecycle-configuration file://upload-lifecycle-policy.json >/dev/null
```

- `--lifecycle-configuration file://upload-lifecycle-policy.json` - References the JSON file created above
- The `file://` prefix tells AWS CLI to read configuration from a local file

### Versioning Configuration

Versioning is enabled to provide data protection and recovery capabilities.

```bash
aws s3api put-bucket-versioning \
  --bucket "$UPLOAD_BUCKET" \
  --versioning-configuration Status=Enabled >/dev/null
```

- `--versioning-configuration Status=Enabled` - Activates S3 versioning for the bucket
- With versioning enabled, object modifications create new versions rather than overwriting existing data
- This provides protection against accidental deletions and data corruption

### CORS Policy Configuration

Cross-Origin Resource Sharing (CORS) is configured to enable browser-based file uploads.

```bash
cat > upload-cors-policy.json <<EOF
{
  "CORSRules": [
    {
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
      "AllowedOrigins": ["*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 86400
    }
  ]
}
EOF
```

The CORS policy JSON configuration includes:

- `"AllowedHeaders": ["*"]` - Permits all request headers from the browser
- `"AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"]` - Enables full HTTP method support for file operations
- `"AllowedOrigins": ["*"]` - Initially allows requests from any origin (will be restricted later by CloudFront)
- `"ExposeHeaders": ["ETag"]` - Makes the ETag header available to JavaScript for upload verification
- `"MaxAgeSeconds": 86400` - Caches CORS preflight responses for 24 hours to reduce overhead

The policy is applied using:

```bash
aws s3api put-bucket-cors \
  --bucket "$UPLOAD_BUCKET" \
  --cors-configuration file://upload-cors-policy.json >/dev/null
```

- `--cors-configuration file://upload-cors-policy.json` - References the CORS policy JSON file
- This enables direct browser-to-S3 uploads without requiring a backend proxy

## Script Output and Operational Guidance

The script concludes with a comprehensive summary of the created infrastructure.

```bash
log_info "Buckets summary:"
log_info "  Static: ${YELLOW}$STATIC_BUCKET${NC}"
log_info "  Upload: ${YELLOW}$UPLOAD_BUCKET${NC} (versioned, lifecycle enabled)"

log_info "${CYAN}Note:${NC} This script is idempotent - safe to run repeatedly"
log_summary "S3 infrastructure setup completed! ${CYAN}Next:${NC} Run 02-deploy-static-website.sh"
```

The summary provides:

- Clear identification of created buckets with color-coded names
- Indication of special features enabled on each bucket
- Reminder about script idempotency for operational safety
- Guidance on the next step in the deployment pipeline

## How to Run the Script

To execute the script normally:

```bash
./01-create-s3-buckets.sh
```

The script can be safely re-run multiple times without creating duplicate resources or corrupting existing configurations. This idempotent behavior supports both development workflows and automated deployment pipelines.
