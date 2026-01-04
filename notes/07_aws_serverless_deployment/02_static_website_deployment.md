
# Static Website Deployment – Implementation Notes

The `02-deploy-static-website.sh` script is responsible for deploying the frontend assets of the Chicago Crimes application to Amazon S3. It takes a local directory containing static website files and synchronizes its contents with a designated S3 bucket in a controlled, repeatable, and safe manner. Rather than creating infrastructure, the script assumes that the required S3 bucket already exists and focuses on validating prerequisites and synchronizing static assets in a controlled way.

## Execution Safety and Configuration

The script begins by enabling strict Bash execution rules:

```bash
set -euo pipefail
```

This ensures that the script exits immediately if any command fails, if an undefined variable is used, or if an error occurs inside a pipeline. These safeguards prevent partial deployments and make failures visible early.

Configuration values are loaded from a shared configuration file:

```bash
source "$(dirname "$0")/00-config.sh"
```

This file provides values such as the AWS region, S3 bucket name, and logging helpers. Separating configuration from logic allows the same script to be reused across environments without modification.

## Dry-Run Support

The script supports a dry-run mode that simulates deployment actions without making changes in AWS:

```bash
DRY_RUN="${DRY_RUN:-false}"
```

When dry-run mode is enabled, all S3 operations are executed in simulation mode. This is especially useful for validating changes in CI/CD pipelines or testing updates to the deployment process without risking data loss.

## Preflight Validation

Before deploying any files, the script performs several checks to ensure that the environment is correctly configured.

It first validates that the project root variable is defined:

```bash
if [[ -z "${PROJECT_ROOT:-}" ]]; then
  log_error "PROJECT_ROOT is not set. Check 00-config.sh"
  exit 1
fi
```

It then verifies that the static website directory exists locally:

```bash
STATIC_WEB_DIR="$PROJECT_ROOT/aws/static-web"

if [[ ! -d "$STATIC_WEB_DIR" ]]; then
  log_error "Static web directory not found: $STATIC_WEB_DIR"
  exit 1
fi
```

Finally, the script confirms that the target S3 bucket exists in AWS:

```bash
if ! aws s3api head-bucket --bucket "$STATIC_BUCKET" 2>/dev/null; then
  log_error "Bucket $STATIC_BUCKET does not exist. Run 01-create-s3-buckets.sh first."
  exit 1
fi
```

These checks ensure that deployment only proceeds when all prerequisites are satisfied, reducing the risk of silent failures.

## Deployment Context and Operator Feedback

Before any files are uploaded, the script logs the deployment context to make it clear what will happen:

```bash
log_info "Deployment context:"
log_info "  Source directory : $STATIC_WEB_DIR"
log_info "  Target bucket    : s3://$STATIC_BUCKET/"
log_info "  AWS region       : $REGION"
log_info "  DRY_RUN mode     : $DRY_RUN"
```

This feedback is particularly helpful when deploying to multiple environments or reviewing CI logs.

For additional transparency, the script logs how many files will be considered for deployment:

```bash
FILE_COUNT=$(find "$STATIC_WEB_DIR" -type f | wc -l | tr -d ' ')
log_info "Preparing to deploy $FILE_COUNT static files"
```

This acts as a lightweight integrity check and helps detect unexpected changes in the source directory.

## Synchronizing Static Assets to S3

The bulk of the deployment is handled by the `aws s3 sync` command:

```bash
run_aws aws s3 sync "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
  --delete \
  --cache-control "max-age=86400" \
  --region "$REGION"
```

This command ensures that the contents of the S3 bucket match the local directory. Files removed locally are also removed from S3, keeping the deployed state consistent.

When dry-run mode is enabled, the same command is executed with the `--dryrun` flag:

```bash
SYNC_FLAGS+=(--dryrun)
```

This causes AWS to report what would change without actually uploading or deleting any files.

## Explicit Content-Type Handling

To avoid issues caused by incorrect MIME type inference, the script explicitly sets content types for key file categories.

For the main HTML file, a short cache duration is applied to allow rapid updates:

```bash
aws s3 cp index.html s3://$STATIC_BUCKET/index.html \
  --content-type "text/html" \
  --cache-control "max-age=300"
```

JavaScript files are uploaded with the correct content type and a longer cache duration:

```bash
aws s3 cp "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
  --recursive \
  --exclude "*" \
  --include "*.js" \
  --content-type "application/javascript" \
  --cache-control "max-age=86400"
```

CSS files are handled similarly:

```bash
aws s3 cp "$STATIC_WEB_DIR/" "s3://$STATIC_BUCKET/" \
  --recursive \
  --exclude "*" \
  --include "*.css" \
  --content-type "text/css" \
  --cache-control "max-age=86400"
```

This explicit handling ensures predictable browser behavior and prepares the site for CDN delivery.

## Completion and Next Steps

After deployment, the script logs a success message and indicates where the files were uploaded:

```bash
log_success "Static website deployment completed successfully!"
log_info "Files deployed to: s3://$STATIC_BUCKET/"
```

If dry-run mode was used, the script clearly states that no changes were made:

```bash
log_warn "DRY_RUN was enabled — no actual changes were made"
```

The script also provides guidance about the broader architecture, reminding operators that the site is intended to be accessed through CloudFront and that frontend configuration values must be updated to point to the correct backend endpoints.

## Running the Script

For a standard deployment, the script is run as follows:

```bash
./02-deploy-static-website.sh
```

To simulate the deployment without making any changes in AWS, dry-run mode can be enabled:

```bash
DRY_RUN=true ./02-deploy-static-website.sh
```

This dual execution model allows the same script to be used safely in both local development and automated deployment pipelines.
