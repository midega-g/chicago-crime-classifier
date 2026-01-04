# Docker Build and Push Implementation for AWS Lambda

## Overview

The `07-build-push-docker.sh` script implements a robust Docker build and push pipeline specifically designed for AWS Lambda container deployments. This script addresses the unique challenges of containerized Lambda functions, including ECR authentication token expiration, build context management, and efficient layer caching.

## Architecture Context

In our serverless architecture, Lambda functions can be deployed using container images stored in Amazon Elastic Container Registry (ECR). This approach provides several advantages over traditional ZIP-based deployments:

1. **Larger deployment packages**: Up to 10GB vs 250MB for ZIP files
2. **Familiar Docker workflows**: Standard containerization practices
3. **Better dependency management**: Complex dependencies handled through Docker layers
4. **Consistent runtime environment**: Identical local and production environments

## Script Implementation Analysis

### Configuration and Prerequisites

The script begins by loading centralized configuration from `00-config.sh`, which provides variables like `ECR_REPO`, `IMAGE_TAG`, `AWS_PROFILE`, and `REGION`.

```sh
source "$(dirname "$0")/00-config.sh" || { 
    echo "Failed to load config" >&2; exit 1; }
```

The Docker prerequisite check ensures the build environment is properly configured before proceeding.

```sh
command -v docker >/dev/null 2>&1 || { 
    log_error "Docker is required"; exit 1; }
```

### ECR Repository URI Resolution

The `get_ecr_repo_uri()` helper function retrieves the full ECR repository URI in the format `account-id.dkr.ecr.region.amazonaws.com/repository-name`.

```bash
REPO_URI=$(get_ecr_repo_uri)
REGISTRY_HOST="${REPO_URI%%/*}"
```

The registry host extraction (`${REPO_URI%%/*}`) isolates the ECR registry hostname, which is crucial for authentication stability. This separation allows Docker to maintain credentials at the registry level rather than the repository level.

### Conditional Build Optimization

The optimization below allows developers to skip rebuilding existing images by setting the `SKIP_BUILD` environment variable.

```bash
CURRENT_DIGEST=$(aws ecr describe-images \
    --repository-name "$ECR_REPO" \
    --image-ids imageTag="$IMAGE_TAG" \
    --query 'imageDetails[0].imageDigest' \
    --output text 2>/dev/null || echo "None")

if [[ "$CURRENT_DIGEST" != "None" && -n "${SKIP_BUILD:-}" ]]; then
    log_success "Image $IMAGE_TAG already exists - skipping build"
    exit 0
fi
```

The `aws ecr describe-images` command queries ECR for the specified image tag, returning the image digest if it exists. The `--query 'imageDetails[0].imageDigest'` parameter uses JMESPath to extract only the digest field, while `--output text` returns plain text instead of JSON. The `2>/dev/null || echo "None"` construct handles cases where the image doesn't exist, preventing script failure. To ensure that the script runs with the `SKIP_BUILD` functionality, use the following command in your terminal:

```sh
SKIP_BUILD=1 ./07-build-push-docker.sh
```

### Docker Build Process

The build process implements several critical optimizations:

```bash
cd "$(dirname "$0")/../.."

for attempt in {1..2}; do
    if DOCKER_BUILDKIT=1 docker buildx build \
        --platform linux/amd64 \
        -f aws/lambda/Dockerfile \
        -t "$ECR_REPO" .; then
        break
    fi
done
```

- **Build Context Management**: The script changes to the project root directory (`cd "$(dirname "$0")/../.."`) to ensure the Docker build context includes all necessary files. This is essential because the Dockerfile references files like `pyproject.toml`, `src/`, and `models/` that exist at the project root level. By changing to the project root directory before building, the script ensures all project files are available to the Docker build context. This is more reliable than copying files or using complex relative paths in the Dockerfile.

- **BuildKit Enablement**: `DOCKER_BUILDKIT=1` enables Docker's modern build engine, providing improved performance, better caching, and advanced features like multi-stage builds and build secrets.

- **Platform Specification**: `--platform linux/amd64` ensures the image is built for the correct architecture, as AWS Lambda runs on x86_64 processors. This is particularly important when building on ARM-based systems (like Apple Silicon Macs).

- **Dockerfile Path**: `-f aws/lambda/Dockerfile` specifies the Dockerfile location relative to the build context (project root).

- **Local Tagging**: `-t "$ECR_REPO"` tags the built image with the repository name for local reference.

### Image Tagging Strategy

The tagging strategy creates a properly formatted ECR image reference. The local image (tagged as `$ECR_REPO:latest`) is retagged with the full ECR URI and specific tag. This approach separates the build process from the deployment target, allowing the same image to be tagged for multiple environments.

```bash
docker tag "$ECR_REPO:latest" "$REPO_URI:$IMAGE_TAG"
```

### ECR Authentication Implementation

ECR authentication is one of the most critical aspects of the script, addressing the common "authorization token has expired" error. The script authenticates immediately before pushing rather than at the beginning of the script. This approach minimizes the time between authentication and usage, reducing the likelihood of token expiration during the push operation.

```bash
token=$(aws ecr get-login-password \
    --region "$REGION" \
    --profile "$AWS_PROFILE")
echo "$token" | docker login \
    --username AWS \
    --password-stdin "$REGISTRY_HOST"
sleep 2
```

- **Token Generation**: `aws ecr get-login-password` generates a temporary authentication token valid for 12 hours. The `--region` parameter ensures the token is generated for the correct ECR registry, while `--profile` uses the specified AWS credentials profile.

- **Secure Login**: The token is piped to `docker login` using `--password-stdin` to avoid exposing credentials in command history or process lists. The username is always `AWS` for ECR authentication.

- **Registry-Level Authentication**: Authenticating against `$REGISTRY_HOST` (e.g., `account-id.dkr.ecr.region.amazonaws.com`) rather than the full repository URI ensures credentials work for all repositories in that registry.

- **Credential Settling**: The `sleep 2` command provides time for Docker's credential helper to properly store and index the authentication token, preventing race conditions in subsequent operations.

### Push Implementation with Retry Logic

The push implementation addresses ECR's token expiration challenges through several mechanisms:

```bash
for attempt in {1..2}; do
    if [[ $attempt -gt 1 ]]; then
        token=$(aws ecr get-login-password \
            --region "$REGION" \
            --profile "$AWS_PROFILE")
        echo "$token" | docker login \
            --username AWS --password-stdin "$REGISTRY_HOST"
        sleep 2
    fi

    if timeout 900 docker push "$REPO_URI:$IMAGE_TAG"; then
        break
    fi
done
```

- **Fresh Authentication**: Before each retry attempt, the script obtains a fresh ECR token and re-authenticates. While this is not necessary in our case, it can be crucial at given times because ECR tokens can expire during long push operations, especially for large images.

- **Extended Timeout**: The `timeout 900` command allows up to 15 minutes for the push operation, accommodating large images and slower network connections. This timeout prevents indefinite hanging while providing sufficient time for legitimate operations.

- **Retry Strategy**: The two-attempt strategy balances reliability with efficiency. Most pushes succeed on the first attempt, but the retry handles transient network issues or token expiration.

### Pre-Push Diagnostics

These diagnostic commands provide valuable information for troubleshooting and optimization:

```bash
log_info "Image size: $(docker images "$REPO_URI:$IMAGE_TAG" \
    --format "{{.Size}}")"
log_info "Layer count: $(docker history "$REPO_URI:$IMAGE_TAG" | \
    tail -n +2 | wc -l)"
```

- **Image Size**: `docker images --format "{{.Size}}"` displays the compressed image size, helping identify bloated images that might cause push timeouts.

- **Layer Count**: `docker history | tail -n +2 | wc -l` counts the number of layers in the image. Excessive layers can impact push performance and Lambda cold start times.

### ECR Image Cleanup

The cleanup process manages ECR storage costs by removing untagged images:

```bash
OLD_IMAGES=$(aws ecr list-images \
  --repository-name "$ECR_REPO" \
  --filter tagStatus=UNTAGGED \
  --query 'imageIds[?imageDigest!=null]' \
  --output json 2>/dev/null || echo '[]')

if [[ "$OLD_IMAGES" != "[]" && -n "$OLD_IMAGES" ]]; then
    aws ecr batch-delete-image \
        --repository-name "$ECR_REPO" \
        --image-ids "$OLD_IMAGES" \
        --profile "$AWS_PROFILE" >/dev/null 2>&1
fi
```

- **Untagged Image Identification**: `--filter tagStatus=UNTAGGED` identifies images that are no longer referenced by any tags. These typically result from pushing new versions of the same tag.

- **Digest Filtering**: `--query 'imageIds[?imageDigest!=null]'` ensures only images with valid digests are selected for deletion, preventing errors from malformed image references.

- **Batch Deletion**: `aws ecr batch-delete-image` efficiently removes multiple images in a single API call, reducing the number of requests and improving performance.

### Final Verification

The final verification step confirms the image was successfully pushed and is available in ECR. This check prevents false positives where the push command appears to succeed but the image isn't actually available for Lambda deployment.

```bash
aws ecr describe-images \
    --repository-name "$ECR_REPO" \
    --image-ids imageTag="$IMAGE_TAG" >/dev/null 2>&1
```

## Performance Optimizations

### Docker Layer Caching

The script leverages Docker's built-in layer caching by using BuildKit and structuring the Dockerfile to maximize cache hits. Dependencies are installed before copying application code, ensuring dependency layers are cached across builds.

### Conditional Building

The `SKIP_BUILD` environment variable allows developers to skip rebuilding existing images, significantly reducing deployment time during development and testing.

### Efficient Cleanup

The batch deletion of untagged images prevents ECR storage costs from accumulating while minimizing API calls through batch operations.

## Integration with Lambda Deployment

This script produces a container image URI that can be used directly with AWS Lambda's container image support. The resulting image includes:

- **Lambda Runtime Interface**: Provided by the `public.ecr.aws/lambda/python:3.12` base image
- **Application Code**: Copied from the `src/` directory
- **Dependencies**: Installed via UV package manager
- **Lambda Handler**: The `lambda_function.py` file containing the Lambda entry point

The image URI output by this script (`$REPO_URI:$IMAGE_TAG`) is used by subsequent deployment scripts to create or update the Lambda function configuration.
