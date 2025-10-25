# Deployment Execution and Infrastructure Cleanup: Orchestrating Serverless Operations

The deployment and cleanup operations represent the practical implementation of our serverless infrastructure, transforming theoretical configurations into running AWS resources. These operations involve both the orchestrated deployment through the master script and the careful cleanup processes that ensure resources can be safely removed without leaving orphaned components or incurring unexpected costs. Understanding these operations requires knowledge of bash script execution, AWS resource dependencies, and the interactive elements that provide safety mechanisms during potentially destructive operations.

## Script Execution Permissions and Bash Environment Setup

Before any deployment scripts can be executed, the Unix file system permissions must be configured to allow script execution. The command that accomplishes this is fundamental to Unix-like systems and represents the first step in preparing for deployment.

```sh
chmod +x deploy/*.sh
```

The `chmod` command modifies file permissions, with `+x` adding execute permissions to the specified files. The wildcard pattern `deploy/*.sh` applies this permission change to all files in the deploy directory that end with the `.sh` extension. In Unix file systems, files are not executable by default when created, which is a security feature that prevents accidental execution of potentially harmful code. The execute permission must be explicitly granted before bash scripts can be run.

In terms of AWS console equivalents, this operation doesn't have a direct parallel because the AWS console doesn't involve file system permissions. However, the concept is similar to enabling or activating a service or feature in the AWS console before it can be used. The permission change is a one-time operation that prepares the scripts for execution, much like how you might need to enable certain AWS services or accept terms of service before using them for the first time.

The bash environment setup involves understanding how scripts are executed and how they interact with the shell environment. When a script is executed with `./deploy/script-name.sh`, the `./` prefix tells the shell to look for the script in the current directory rather than searching the system PATH. This explicit path specification prevents confusion when multiple scripts with similar names exist in different directories and ensures that the correct script is executed.

The shebang line `#!/bin/bash` at the beginning of each script tells the system which interpreter to use for executing the script. This line is crucial because it ensures that the script runs with bash-specific features and syntax, rather than with a more basic shell that might not support all the commands and constructs used in the scripts. Different Unix-like systems may have different default shells, so the shebang line provides consistency across different environments.

## Master Deployment Script Orchestration

The master deployment script `04-step1-s3-and-cloudfront.sh` provides orchestrated execution of the individual deployment components, ensuring that operations occur in the correct order and with appropriate error handling. This script demonstrates the principle of composition in deployment automation, where complex operations are built from simpler, focused components.

The script begins with the standard initialization pattern, loading the centralized configuration and setting up error handling. The `set -e` directive ensures that if any individual deployment step fails, the entire process stops immediately rather than continuing with potentially invalid configurations. This fail-fast approach is crucial for infrastructure deployment because partial deployments can be difficult to troubleshoot and may leave resources in inconsistent states.

The orchestration approach uses sequential execution of the individual deployment scripts:

```sh
./deploy/01-create-s3-buckets.sh
./deploy/02-deploy-static-website.sh
./deploy/03-create-cloudfront.sh
```

Each script is executed as a separate process, which means that any environment variables or temporary files created by one script don't affect the others unless explicitly designed to do so. This isolation helps prevent unexpected interactions between deployment steps and makes the overall process more predictable and debuggable.

The master script provides comprehensive status reporting throughout the deployment process, with clear section headers and progress indicators. This feedback is essential for long-running deployments like CloudFront distributions, which can take 10-15 minutes to complete. The status messages help users understand that the deployment is progressing normally even when individual steps take significant time.

The script also provides guidance about next steps and important configuration requirements. After the infrastructure is deployed, users need to update API Gateway URLs in the JavaScript files and potentially perform other configuration tasks. The master script serves as documentation for these post-deployment requirements, ensuring that users don't miss critical configuration steps.

## Individual Script Execution and Dependencies

While the master script provides convenient orchestration, the individual deployment scripts can also be executed independently, which is valuable for development, testing, and troubleshooting scenarios. Understanding the dependencies between scripts is crucial for successful independent execution.

The S3 bucket creation script `01-create-s3-buckets.sh` has no dependencies on other deployment components and can be executed at any time. This script creates the foundational storage infrastructure that other components depend on, making it the logical first step in any deployment sequence.

The static website deployment script `02-deploy-static-website.sh` depends on the existence of the static website S3 bucket created by the first script. If executed independently, this script will fail if the target bucket doesn't exist. The script doesn't include bucket creation logic because that would violate the single responsibility principle and could lead to configuration inconsistencies.

The CloudFront distribution script `03-create-cloudfront.sh` depends on both the S3 bucket existence and the presence of content in the bucket. While CloudFront can be configured to point to an empty bucket, the distribution won't serve meaningful content until the static files are deployed. The script also creates S3 bucket policies that reference the CloudFront distribution, creating a circular dependency that requires careful ordering of operations.

When executing scripts independently, users must understand these dependencies and execute scripts in the correct order. The error messages from failed dependencies are usually clear enough to indicate what's missing, but understanding the relationships helps prevent errors and reduces troubleshooting time.

## Interactive Confirmation and Safety Mechanisms

The deployment scripts include several interactive confirmation mechanisms that provide safety checks for potentially destructive operations. These confirmations are particularly important when dealing with existing resources that might contain valuable data or configurations.

The S3 bucket creation script includes interactive prompts when existing buckets are detected:

```sh
read -p "Delete all objects and recreate bucket? (yes/no): " confirm
```

The `read` command with the `-p` flag displays a prompt and waits for user input, storing the response in the specified variable. This mechanism provides a safety check that prevents accidental deletion of existing data. The prompt is explicit about what will happen if the user confirms the operation, ensuring informed consent for potentially destructive actions.

The confirmation logic uses bash conditional statements to check the user's response:

```sh
if [ "$confirm" = "yes" ]; then
    echo "Emptying bucket..."
    aws s3 rm s3://$STATIC_BUCKET --recursive
else
    echo "Keeping existing bucket and contents"
fi
```

The exact string comparison `"$confirm" = "yes"` requires users to type "yes" exactly, preventing accidental confirmation from partial or mistyped responses. This strict comparison is a safety feature that ensures users must explicitly confirm destructive operations.

In AWS console terms, these confirmations are similar to the warning dialogs that appear when attempting to delete resources. The console typically shows warnings about the consequences of deletion and requires explicit confirmation before proceeding. The script-based approach provides similar safety mechanisms while enabling automation.

## Cleanup Script Architecture and Resource Dependencies

The cleanup script `05-cleanup-step1.sh` implements the reverse of the deployment process, removing AWS resources in an order that respects their dependencies. Understanding cleanup operations is crucial for cost management and environment hygiene, particularly in development and testing scenarios where resources may be created and destroyed frequently.

The cleanup script begins with comprehensive warnings about the destructive nature of the operations:

```sh
echo "WARNING: This will delete S3 buckets and CloudFront distribution!"
echo "Resources to be deleted:"
echo "- S3 buckets: $STATIC_BUCKET, $UPLOAD_BUCKET"
echo "- CloudFront distribution"
```

This warning provides users with specific information about what will be deleted, allowing them to make informed decisions about whether to proceed. The explicit listing of resources helps prevent accidental deletion of the wrong infrastructure, particularly important in environments where multiple applications or versions might be deployed.

The confirmation mechanism in the cleanup script uses the same pattern as the deployment scripts:

```sh
read -p "Are you sure you want to continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi
```

The cleanup process must handle resource dependencies carefully because AWS prevents deletion of resources that are still referenced by other resources. CloudFront distributions must be disabled and fully deployed before they can be deleted, and S3 buckets must be completely empty before deletion is allowed.

## CloudFront Distribution Cleanup Complexity

The CloudFront distribution cleanup represents the most complex part of the cleanup process due to the service's global nature and the time required for configuration changes to propagate worldwide. The cleanup process involves multiple steps that must be executed in sequence with appropriate waiting periods.

The first step identifies existing distributions that match our application:

```sh
DISTRIBUTIONS=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='$DISTRIBUTION_COMMENT'].Id" --output text)
```

This command uses the same JMESPath query syntax discussed in the deployment analysis, filtering distributions by their comment field to identify those belonging to our application. The query approach ensures that only the correct distributions are targeted for deletion, preventing accidental removal of unrelated CloudFront distributions.

The distribution disabling process requires careful handling of ETags, which are AWS's mechanism for preventing concurrent modifications:

```sh
aws cloudfront get-distribution-config --id $DIST_ID > dist-config.json
ETAG=$(jq -r '.ETag' dist-config.json)
jq '.DistributionConfig.Enabled = false | .DistributionConfig' dist-config.json > dist-config-disabled.json
aws cloudfront update-distribution --id $DIST_ID --distribution-config file://dist-config-disabled.json --if-match $ETAG
```

The ETag extraction and usage pattern ensures that the distribution configuration hasn't changed between the time we read it and the time we attempt to modify it. This prevents race conditions that could occur if multiple processes were attempting to modify the same distribution simultaneously.

The waiting mechanism uses AWS CLI's built-in wait functionality with timeout protection:

```sh
timeout 900 aws cloudfront wait distribution-deployed --id $DIST_ID || echo "Timeout waiting for distribution deployment"
```

The `timeout 900` command limits the wait to 15 minutes (900 seconds), preventing the script from hanging indefinitely if there are issues with the CloudFront deployment. The `|| echo` construct provides feedback if the timeout occurs, helping users understand why the script continued without waiting for full deployment.

After the distribution is disabled and deployed, a fresh ETag must be obtained for the deletion operation:

```sh
FRESH_CONFIG=$(aws cloudfront get-distribution --id $DIST_ID)
FRESH_ETAG=$(echo $FRESH_CONFIG | jq -r '.ETag')
aws cloudfront delete-distribution --id $DIST_ID --if-match $FRESH_ETAG
```

This fresh ETag requirement was discovered during our development process when we encountered `"PreconditionFailed"` errors. The ETag changes when the distribution is updated, so the original ETag from the disable operation is no longer valid for the delete operation.

## Origin Access Control Cleanup Challenges

The Origin Access Control cleanup presented unique challenges during development, requiring sophisticated error handling and retry mechanisms. The OAC cleanup process demonstrates the complexity of managing AWS resource dependencies and the importance of robust error handling in cleanup operations.

The OAC identification process finds all OACs associated with our application:

```sh
OAC_IDS=$(aws cloudfront list-origin-access-controls \
    --query "OriginAccessControlList.Items[?contains(Name, 'chicago-crimes-oac')].Id" \
    --output text)
```

The `contains()` function in the JMESPath query allows for partial name matching, which is necessary because our OAC creation process appends timestamps to ensure uniqueness. This approach finds all OACs related to our application, regardless of when they were created.

The OAC deletion process requires obtaining the ETag for each OAC before deletion:

```sh
OAC_CONFIG=$(aws cloudfront get-origin-access-control --id $OAC_ID 2>/dev/null)
if [ $? -eq 0 ]; then
    OAC_ETAG=$(echo $OAC_CONFIG | jq -r '.ETag')
    aws cloudfront delete-origin-access-control --id $OAC_ID --if-match $OAC_ETAG
fi
```

The `2>/dev/null` redirection suppresses error messages when attempting to get OAC details, and the `$?` variable check examines the exit status of the previous command. This pattern handles cases where OACs might have been deleted by other processes or might not exist, preventing the script from failing on missing resources.

The error handling approach was developed after encountering "InvalidIfMatchVersion" errors during testing. These errors occurred because OAC deletion, like CloudFront distribution operations, requires ETags to prevent concurrent modification issues. The solution involves always obtaining fresh ETags immediately before deletion attempts.

## S3 Bucket Cleanup and Data Protection

The S3 bucket cleanup process implements a two-step approach that first empties buckets and then deletes them. This approach is necessary because AWS prevents deletion of non-empty buckets, and the two-step process provides additional safety by making the deletion process explicit and visible.

The bucket emptying process uses recursive deletion to remove all objects:

```sh
aws s3 rm s3://$STATIC_BUCKET --recursive 2>/dev/null || echo "Static bucket not found or already empty"
```

The `--recursive` flag ensures that objects in subdirectories are also deleted, which is necessary for complete bucket emptying. The `2>/dev/null` redirection suppresses error messages that would occur if the bucket doesn't exist, and the `|| echo` construct provides informative feedback about the operation's outcome.

The bucket deletion operation follows the emptying:

```sh
aws s3 rb s3://$STATIC_BUCKET 2>/dev/null || echo "Static bucket not found"
```

The `rb` command stands for "remove bucket" and will only succeed if the bucket is completely empty. The error suppression and feedback mechanisms handle cases where buckets might not exist or might have been deleted by other processes.

This two-step approach provides visibility into the cleanup process and allows for intervention if needed. Users can see that objects are being deleted before the bucket itself is removed, providing an opportunity to cancel the operation if unexpected content is discovered.

## Interactive CLI Behavior and User Experience

Throughout the deployment and cleanup processes, users encounter various interactive elements that require understanding of CLI behavior and appropriate responses. These interactions are designed to provide safety and control while maintaining the automation benefits of scripted deployment.

The `yes/no` prompts require exact string matching and are case-sensitive. Users must type `"yes"` exactly to confirm destructive operations, with any other response (including "y", "Yes", or "YES") being treated as a negative response. This strict matching prevents accidental confirmation and ensures that users must explicitly acknowledge the consequences of their actions.

Some AWS CLI operations, particularly CloudFront wait commands, may display progress information or require user interaction to continue. The `aws cloudfront wait` command can sometimes pause and require pressing `'q'` to quit or `Enter` to continue, depending on the terminal configuration and the amount of output being displayed. Understanding this behavior helps prevent confusion when scripts appear to hang during long-running operations.

The timeout mechanisms implemented in the scripts provide escape hatches for operations that might hang indefinitely. When timeouts occur, the scripts continue with appropriate error messages, allowing users to assess the situation and take corrective action if needed. This approach balances automation with user control, ensuring that scripts don't become unresponsive while still providing feedback about unusual conditions.

## Error Recovery and Troubleshooting Strategies

The deployment and cleanup scripts include various mechanisms for error recovery and troubleshooting, reflecting lessons learned during development and testing. Understanding these mechanisms helps users diagnose and resolve issues that may arise during deployment or cleanup operations.

The idempotent design of the deployment scripts means they can be run multiple times without causing errors or inconsistencies. If a deployment fails partway through, users can typically re-run the same script after addressing the underlying issue. The existence checking mechanisms prevent errors from attempting to create resources that already exist, while the configuration validation ensures that existing resources are properly configured.

The cleanup scripts include comprehensive error handling that allows partial cleanup when some resources can't be deleted. This approach prevents cleanup failures from leaving environments in inconsistent states and provides clear feedback about which operations succeeded and which failed.

The logging and output mechanisms in both deployment and cleanup scripts provide detailed information about operations being performed and their outcomes. This information is valuable for troubleshooting and for understanding the state of the infrastructure at any point in the process.

## Best Practices for Production Deployment

The deployment and cleanup processes demonstrate several best practices that are important for production use of serverless infrastructure. These practices include comprehensive error handling, user confirmation for destructive operations, and clear documentation of dependencies and requirements.

The centralized configuration approach ensures consistency across different environments and makes it easy to deploy the same application to development, staging, and production environments with appropriate parameter changes. The configuration file serves as documentation of the deployment parameters and can be version-controlled along with the application code.

The modular script design allows for flexible deployment strategies, including partial deployments for testing and incremental updates for production changes. The clear separation of concerns between different scripts makes it easy to understand and modify individual components without affecting the entire deployment process.

The safety mechanisms and confirmation prompts provide protection against accidental destructive operations while still enabling automation. These mechanisms are particularly important in production environments where accidental deletion of resources could have significant business impact.

The comprehensive cleanup capabilities ensure that development and testing environments can be easily created and destroyed, supporting agile development practices and cost management. The ability to completely remove all traces of a deployment is crucial for maintaining clean AWS accounts and preventing resource sprawl that can lead to unexpected costs and security issues.
