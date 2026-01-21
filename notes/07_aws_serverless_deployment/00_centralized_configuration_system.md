# Centralized Configuration Management - Updated

## Overview

The `00-config.sh` script serves as the centralized configuration hub for the Chicago Crimes serverless deployment system. It provides environment loading, color definitions, logging utilities, and helper functions for AWS resource management.

## Project Root Discovery

The script begins by enabling strict Bash execution modes and establishing the project structure.

```bash
set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
```

The `set -euo pipefail` line ensures that the script exits immediately if any command fails, if an undefined variable is used, or if a pipeline command fails silently. This prevents partial configuration loading, which is especially important when working with cloud resources that depend on consistent configuration.

The project root detection uses `git rev-parse --show-toplevel` to find the repository root, with a fallback to the current directory. This approach works whether scripts are run from the project root or subdirectories, enabling reliable `.env` file location regardless of execution context.

## Environment Variable Loading with Safety Checks

Before any configuration is set, the script loads sensitive credentials from the `.env` file.

```bash
if [ -f "$ENV_FILE" ]; then
    set -a                  # Enable automatic export of all variables
    source "$ENV_FILE"
    set +a                  # Disable automatic export of all variables
else
    echo "Error: .env file not found at $ENV_FILE" >&2
    exit 1
fi
```

This loading mechanism implements several safety measures:

- The `[ -f "$ENV_FILE" ]` test ensures the file exists before attempting to load it
- `set -a`: Enables the `allexport` option. Every variable assignment after this command is automatically exported to the environment, making it available to child processes
- `set +a`: Disables the `allexport` option. Variables are only exported if explicitly done with the `export` command
- Error output is directed to stderr using `>&2`
- The script exits with status 1 if the `.env` file is missing, preventing deployment with incomplete configuration

The `set -a` flag enables automatic export of all variables that are set or modified, ensuring that credentials loaded from `.env` become available to child processes without manual export statements.

## Configuration Export Statements

The script exports numerous configuration variables for use across deployment scripts:

```bash
export REGION="${AWS_REGION}"
export STATIC_BUCKET="chicago-crimes-web-bucket"
export FUNCTION_NAME="chicago-crimes-lambda-predictor"
# ... omitted for brevity
```

The configuration structure follows a clear pattern:

- **AWS Core variables** reference values from the `.env` file using variable expansion
- **Resource names** are hardcoded to ensure consistency across all deployment scripts
- **Export statements** make all variables available to child processes and AWS CLI commands

This approach prevents typos in resource names that could create orphaned AWS resources while allowing environment-specific customization through the `.env` file.

## Color Definitions

The primary colors are also defined for terminal output:

```bash
export RED='\033[0;31m'
export GREEN='\033[0;32m'
# ... omitted for brevity
```

These ANSI escape codes enable colored terminal output for better visual feedback during script execution.

## Logging System

### Status Indicators

Four main status indicators provide consistent messaging:

- `INFO`: Cyan-colored informational messages
- `SUCCESS`: Green checkmark for successful operations  
- `WARN`: Yellow warning messages
- `ERROR`: Red error messages

### Logging Helper Functions

The logging functions provide standardized output formatting:

- `log_info()`: Displays informational messages with cyan "info" prefix
- `log_success()`: Shows success messages with green checkmark
- `log_warn()`: Outputs warnings with yellow "warn" prefix  
- `log_error()`: Displays errors with red "error" prefix and returns exit code 1

Each logging function follows consistent patterns:

- All output is directed to stderr using `>&2`, separating log messages from command output
- The `echo -e` flag enables interpretation of color escape sequences
- The `$*` expansion includes all function arguments as a single string
- The `log_error` function returns status 1, allowing calling scripts to handle errors appropriately

This logging system provides consistent formatting and error handling across all deployment scripts.

## Box Drawing Logic

### `log_section()` Function

The `log_section()` function creates visually appealing bordered sections for script output. Here's how the box drawing logic works:

**Step 1: Calculate Dimensions**

```bash
local title="$*"
local length=${#title}
local padding=$(( (75 - length) / 2 ))
```

The function calculates the title length and determines how much padding is needed to center the text within a 75-character wide box.

**Step 2: Build Padding Strings**

```bash
local left_pad=""
local right_pad=""
for ((i=0; i<padding; i++)); do left_pad+=" "; done
for ((i=0; i< (75 - length - padding); i++)); do right_pad+=" "; done
```

Two loops create the left and right padding strings. The right padding accounts for any remainder when the title length doesn't divide evenly, ensuring the box stays aligned.

**Step 3: Draw the Box**

```bash
echo -e "\n${BLUE}┌─────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${BLUE}│${NC}${left_pad}${CYAN}${title}${NC}${right_pad}${BLUE}│${NC}"
echo -e "${BLUE}└─────────────────────────────────────────────────────────────────┘${NC}"
```

The function draws a three-line box using Unicode box-drawing characters:

- Top border: `┌` (top-left) + `─` (horizontal) + `┐` (top-right)
- Middle line: `│` (vertical) + centered title + `│` (vertical)
- Bottom border: `└` (bottom-left) + `─` (horizontal) + `┘` (bottom-right)

The title is displayed in cyan color while the box frame uses blue, with proper color reset (`${NC}`) to prevent color bleeding.

## AWS Resource Helper Functions

The script includes several helper functions for dynamic AWS resource retrieval:

### `get_ecr_repo_uri()`

Retrieves the ECR repository URI using AWS CLI. Queries the ECR service for the repository and extracts the URI field, returning empty string if not found.

### `verify_ecr_image_exists()`

Checks if a Docker image exists in the ECR repository. Uses the same query pattern as `get_ecr_repo_uri()` to verify repository existence.

### `get_api_gateway_id()`

Fetches the API Gateway REST API ID by name. Uses JMESPath query to filter APIs by name and returns the first match.

### `get_lambda_function_arn()`

Retrieves the Lambda function ARN for the specified function name. Queries the Lambda service configuration and extracts the ARN field.

### `get_cloudfront_distribution_id()`

Gets the CloudFront distribution ID by matching the distribution comment. Searches through all distributions and returns the ID of the matching one.

### `get_cloudfront_distribution_url()`

Similar to the ID function but returns the domain name (URL) of the CloudFront distribution instead of the ID.

All helper functions include error handling with `2>/dev/null || echo ""` to return empty strings when resources don't exist, preventing script failures during initial deployments.

## Usage Pattern

Other deployment scripts source this configuration file to access all defined variables and functions:

```bash
source "$(dirname "$0")/00-config.sh" || {
  echo "Failed to load config" >&2
  exit 1
}
```

This pattern ensures:

- The `$(dirname "$0")` expression finds the directory containing the current script
- Relative path resolution works regardless of script execution location
- The `|| { ... }` construct executes the error block if sourcing fails
- Scripts cannot continue with missing or incomplete configuration

## Benefits of This Centralized Approach

The centralized configuration system provides several critical advantages:

**Consistency**: All scripts use identical AWS profiles, regions, and resource names, preventing deployment inconsistencies that could lead to orphaned resources or failed deployments.

**Maintainability**: Configuration changes in one file automatically affect all scripts, reducing maintenance overhead and ensuring that updates are applied uniformly across the entire deployment system.

**Error Prevention**: Centralized resource naming prevents typos that could create duplicate or orphaned AWS resources, while strict error handling prevents silent failures.

**Security**: Sensitive credentials are loaded once from `.env` files with proper error handling, reducing the risk of credential exposure or misconfiguration.

**Debugging**: The unified logging system provides consistent output formatting and error reporting across all scripts, making it easier to troubleshoot deployment issues.

**User Experience**: Color-coded output and consistent formatting improve readability and reduce the likelihood of deployment errors caused by unclear feedback.
