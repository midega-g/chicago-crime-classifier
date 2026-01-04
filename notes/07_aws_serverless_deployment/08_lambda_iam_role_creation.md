# Lambda IAM Role Creation

The creation of IAM roles for Lambda functions represents a critical security checkpoint in serverless architecture, where the principle of least privilege must be carefully balanced with functional requirements. The `08-create-lambda-role.sh` script establishes the security foundation that enables Lambda functions to interact with other AWS services while maintaining strict access controls that protect sensitive data and prevent unauthorized operations.

## IAM Role Architecture and Security Model

The Lambda IAM role serves as the security identity that Lambda functions assume when executing, determining exactly which AWS services and resources the function can access. This role-based security model implements AWS's principle of least privilege, ensuring that Lambda functions have only the minimum permissions necessary to perform their intended operations.

The security architecture consists of two fundamental components working together:

1. **Trust Policy**: Defines which entities can assume the role, establishing the foundational trust relationship between AWS Lambda service and the IAM role.

2. **Permissions Policies**: Define what actions the role can perform once assumed, specifying exactly which AWS services and resources can be accessed and what operations are permitted.

This separation of concerns ensures that even if a Lambda function is compromised, the potential damage is limited to the specific permissions granted to its execution role. The role cannot be assumed by unauthorized services or users, and it cannot perform operations beyond its defined scope.

## Script Initialization and Configuration Loading

The script begins with robust initialization and configuration loading that establishes the foundation for secure, repeatable deployments:

```bash
#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}
```

The `set -euo pipefail` directive implements strict error handling that prevents the script from continuing if any command fails, ensuring that partial deployments don't leave the system in an inconsistent state. The `-e` flag causes the script to exit immediately if any command returns a non-zero status, while `-u` treats unset variables as errors, preventing subtle bugs from undefined configuration values. The `-o pipefail` option ensures that pipeline failures are properly detected, even when the final command in a pipeline succeeds.

The configuration loading mechanism includes error handling that provides clear feedback if the shared configuration cannot be loaded. This fail-fast approach prevents deployment attempts with incomplete configuration, ensuring that all necessary parameters are available before beginning resource creation.

The trap mechanism ensures cleanup of temporary files:

```bash
trap 'rm -f lambda-trust-policy.json lambda-permissions-policy.json' EXIT
```

This cleanup occurs regardless of how the script exits, whether through successful completion, error conditions, or manual interruption, preventing accumulation of temporary files that could contain sensitive policy information.

## Existing Role Detection and Idempotency

The script implements intelligent detection of existing IAM roles to support idempotent deployments:

```bash
if aws --profile "$AWS_PROFILE" iam get-role \
    --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    log_warn "IAM role already exists: $ROLE_NAME"
    log_summary "Using existing IAM role"
    echo -e "${CYAN}Next:${NC} Run 09-setup-ses-email.sh"
    exit 0
fi
```

This detection mechanism serves several important purposes in the deployment workflow:

1. **Idempotency**: The script can be run multiple times without creating duplicate resources or causing errors, supporting iterative deployment and troubleshooting workflows.

2. **State Preservation**: Existing roles with their attached policies are preserved, preventing accidental deletion of carefully configured permissions during redeployment.

3. **Deployment Flexibility**: Teams can run the complete deployment sequence multiple times, with each script intelligently handling existing resources while creating only what's missing.

The error redirection `>/dev/null 2>&1` suppresses both standard output and error messages from the AWS CLI command, preventing cluttered output while still allowing the script to detect the command's success or failure through its exit code.

## Trust Policy Creation and Lambda Service Integration

The trust policy establishes the fundamental security relationship that allows AWS Lambda service to assume the IAM role:

```json
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
```

This trust policy implements several critical security principles:

**Service-Specific Trust**: The `"Principal": {"Service": "lambda.amazonaws.com"}` specification ensures that only the AWS Lambda service can assume this role. This prevents other AWS services, IAM users, or external entities from assuming the role, even if they somehow obtain the role ARN.

**Explicit Action Authorization**: The `"Action": "sts:AssumeRole"` explicitly grants the assume role permission, following the principle of explicit authorization where permissions must be specifically granted rather than assumed by default.

**Policy Version Specification**: The `"Version": "2012-10-17"` ensures that the policy uses the current IAM policy language version, providing access to all available policy features and maintaining compatibility with AWS security best practices.

The trust policy is written to a temporary file that is automatically cleaned up after use, preventing sensitive policy information from persisting on the filesystem where it could be inadvertently exposed or accessed by unauthorized processes.

## IAM Role Creation with Resource Tagging

The IAM role creation process includes comprehensive resource tagging that supports governance, cost allocation, and resource management:

```bash
aws --profile "$AWS_PROFILE" iam create-role \
    --role-name "$ROLE_NAME" \
    --tags Key=Project,Value=ChicagoCrimes Key=Env,Value=dev \
    --assume-role-policy-document file://lambda-trust-policy.json >/dev/null
```

The tagging strategy implements several organizational benefits:

**Project Identification**: The `Key=Project,Value=ChicagoCrimes` tag enables filtering and grouping of resources by project, supporting multi-project AWS accounts and simplifying resource management across different initiatives.

**Environment Classification**: The `Key=Env,Value=dev` tag distinguishes between development, staging, and production resources, enabling environment-specific policies and cost allocation strategies.

**Cost Allocation**: Tags enable detailed cost tracking and allocation, allowing organizations to understand the financial impact of different projects and environments.

**Automated Management**: Tags support automated resource management through AWS Config rules, Lambda functions, and other automation tools that can identify and act upon resources based on their tag values.

The role creation uses the `file://` prefix to reference the trust policy document, ensuring that the policy content is read from the temporary file rather than being embedded directly in the command line, which could expose sensitive information in process lists or command history.

## AWS Managed Policy Attachment

The script attaches the AWS managed basic execution policy that provides fundamental Lambda execution capabilities:

```bash
aws --profile "$AWS_PROFILE" iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole >/dev/null
```

The `AWSLambdaBasicExecutionRole` managed policy provides essential permissions that every Lambda function requires:

**CloudWatch Logs Integration**: The policy grants permissions to create log groups, create log streams, and write log events to CloudWatch Logs. This enables Lambda functions to generate detailed execution logs that are essential for debugging, monitoring, and auditing.

**AWS Managed Policy Benefits**: Using AWS managed policies ensures that the permissions stay current with AWS service updates and security best practices. AWS maintains these policies and updates them as needed to support new features or address security considerations.

**Separation of Concerns**: The basic execution policy handles fundamental Lambda requirements, while custom policies (added later) handle application-specific permissions, creating a clear separation between platform requirements and application needs.

## Custom Permissions Policy for Application Services

The custom permissions policy defines the specific AWS service interactions required for the Chicago Crime Prediction application:

```json
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
                "arn:aws:s3:::$UPLOAD_BUCKET/*"
            ]
        }
    ]
}
```

### S3 Object-Level Permissions

The S3 permissions are carefully scoped to support the file processing workflow while maintaining security:

**GetObject Permission**: Enables Lambda functions to read uploaded crime data files from the S3 bucket, supporting the core functionality of processing user-submitted data for prediction generation.

**PutObject Permission**: Allows Lambda functions to write processed results or intermediate files back to S3, enabling multi-stage processing workflows and result storage.

**Resource-Specific Scope**: The `"Resource": "arn:aws:s3:::$UPLOAD_BUCKET/*"` specification limits access to objects within the specific upload bucket, preventing access to other S3 buckets or resources that might contain sensitive information.

The object-level permissions (`/*` suffix) grant access to objects within the bucket but not to the bucket itself, following the principle of least privilege by providing only the access needed for file operations.

### S3 Bucket-Level Permissions

The bucket-level permissions complement the object-level permissions:

```json
{
    "Effect": "Allow",
    "Action": [
        "s3:ListBucket"
    ],
    "Resource": [
        "arn:aws:s3:::$UPLOAD_BUCKET"
    ]
}
```

**ListBucket Permission**: Enables Lambda functions to enumerate objects within the bucket, supporting workflows that need to discover or validate file existence before processing.

**Bucket-Specific Scope**: The resource specification without the `/*` suffix applies to the bucket itself rather than its contents, enabling bucket-level operations while maintaining strict access controls.

### DynamoDB Integration Permissions

The DynamoDB permissions support result storage and retrieval:

```json
{
    "Effect": "Allow",
    "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
    ],
    "Resource": "arn:aws:dynamodb:$REGION:$ACCOUNT_ID:table/$RESULTS_TABLE"
}
```

**GetItem Permission**: Allows Lambda functions to retrieve existing prediction results or user session information, supporting features like result caching and user history.

**PutItem Permission**: Enables creation of new records for prediction results, user sessions, or processing status information.

**UpdateItem Permission**: Supports modification of existing records, enabling status updates, result refinement, or session management.

**Table-Specific Scope**: The resource ARN limits access to the specific results table, preventing unauthorized access to other DynamoDB tables that might contain sensitive information.

### SES Email Notification Permissions

The SES permissions enable automated email notifications:

```json
{
    "Effect": "Allow",
    "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail"
    ],
    "Resource": "*"
}
```

**SendEmail Permission**: Enables Lambda functions to send formatted email notifications to users when prediction processing is complete.

**SendRawEmail Permission**: Supports sending of complex email formats, including attachments or custom formatting, providing flexibility in notification design.

**Global Resource Scope**: The `"Resource": "*"` specification is necessary for SES operations because email sending permissions apply globally rather than to specific resources. However, SES has built-in protections through verified sender addresses and sending limits that prevent abuse.

## Inline Policy Attachment and Management

The custom permissions are attached as an inline policy rather than a managed policy:

```bash
aws --profile "$AWS_PROFILE" iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "$INLINE_POLICY_NAME" \
    --policy-document file://lambda-permissions-policy.json >/dev/null
```

**Inline Policy Benefits**: Inline policies are directly attached to the role and cannot be accidentally attached to other roles, ensuring that these specific permissions remain associated only with the intended Lambda execution role.

**Policy Lifecycle Management**: Inline policies are automatically deleted when the role is deleted, simplifying cleanup operations and preventing orphaned policies that could create security risks.

**Version Control Integration**: The policy document is generated from the script, ensuring that policy changes are version-controlled and auditable through the deployment script history.

## IAM Propagation and Eventual Consistency

The script includes a waiting mechanism to handle IAM's eventual consistency model:

```bash
for i in {1..10}; do
  if aws --profile "$AWS_PROFILE" iam get-role \
       --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    log_success "IAM role is now available"
    break
  fi
  log_info "IAM not ready yet... retrying ($i/10)"
  sleep 6
done
```

**Eventual Consistency Handling**: IAM changes are eventually consistent across AWS regions and services, meaning that newly created roles might not be immediately available for use by other AWS services.

**Retry Logic**: The loop attempts to verify role availability up to 10 times with 6-second intervals, providing up to 60 seconds for IAM propagation to complete.

**Graceful Degradation**: If the role is not available after the maximum retry attempts, the script continues, allowing subsequent deployment steps to handle any remaining propagation delays.

**User Feedback**: Progress messages keep users informed about the waiting process, preventing confusion about apparent script delays.

## Security Best Practices Implementation

The script implements several security best practices that extend beyond basic functionality:

**Temporary File Management**: Policy documents are written to temporary files that are automatically cleaned up, preventing sensitive information from persisting on the filesystem.

**Output Suppression**: AWS CLI commands redirect output to `/dev/null` to prevent sensitive information like role ARNs from appearing in logs or terminal output where they might be inadvertently exposed.

**Error Handling**: Comprehensive error handling ensures that failures are detected and reported clearly, preventing partial deployments that could leave the system in an insecure state.

**Principle of Least Privilege**: Each permission is carefully scoped to the minimum required for functionality, reducing the potential impact of security breaches or misuse.

## Integration with Deployment Pipeline

The IAM role creation script is designed to integrate seamlessly with the broader deployment pipeline:

**Dependency Management**: The script creates the IAM role that will be required by subsequent Lambda deployment steps, ensuring that security infrastructure is in place before application deployment.

**Configuration Integration**: The role name and other parameters are sourced from the centralized configuration, ensuring consistency across all deployment scripts.

**Status Reporting**: Clear success and failure messages enable automated deployment systems to make decisions about whether to proceed with subsequent steps.

**Next Step Guidance**: The script provides explicit guidance about the next deployment step, supporting both manual and automated deployment workflows.
