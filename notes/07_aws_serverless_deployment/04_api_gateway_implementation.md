# API Gateway Setup

The API Gateway deployment script, `04-create-api-gateway.sh`, provisions an Amazon API Gateway REST API that will later serve as the public HTTP interface for the backend of the Chicago Crimes application. This script implements a proxy-based architecture that enables flexible backend routing while maintaining strict separation between API structure and execution logic. At this stage, the API is intentionally created **without a backend integration**, allowing the infrastructure to be built incrementally and validated step by step. The design favors clarity, repeatability, and safe re-execution over speed.

## Enforcing safe execution and loading shared configuration

The script begins by enabling strict Bash execution rules and loading shared configuration and helper functions.

```bash
set -euo pipefail
source "$(dirname "$0")/00-config.sh"
```

These settings ensure the script fails immediately on errors, undefined variables, or broken pipelines. This combination becomes particularly critical for API Gateway deployment because the service involves multiple interdependent resources (APIs, resources, methods, deployments) where partial configuration can create confusing operational states that are difficult to diagnose and resolve.

The shared configuration file provides values such as the AWS profile, region, API name, deployment stage, and logging helpers. Centralizing these values avoids duplication and ensures consistent behavior across all infrastructure scripts.

## Validating required tooling before proceeding

Before making any AWS calls, the script verifies that `jq` is installed.

```bash
command -v jq >/dev/null 2>&1 || {
  log_error "jq is required but not installed."
  exit 1
}
```

This check exists because AWS CLI responses are JSON, and the script relies heavily on parsing those responses to extract IDs. Failing early avoids confusing downstream errors that would otherwise appear unrelated to missing tooling.

## Detecting an existing API Gateway

Rather than always creating a new API, the script first checks whether an API Gateway with the expected name already exists.

```bash
aws apigateway get-rest-apis \
  --query "items[?name=='$API_NAME'].id | [0]"
```

This decision makes the script idempotent. API Gateway resources are regional and persistent, and recreating them accidentally can break clients or introduce unnecessary complexity. If an existing API is found, the script prints its endpoint and exits cleanly, allowing downstream scripts to proceed without duplication.

### Creating the REST API

If no existing API is found, a new REST API is created.

```bash
aws apigateway create-rest-api \
  --name "$API_NAME" \
  --description "Chicago Crimes ML API with proxy integration"
```

At this point, the API exists only as a container. It has no resources, no methods, and no backend. This separation is intentional: it allows the API’s structure to be defined independently from its execution logic.

### Discovering the root resource

Every API Gateway REST API automatically contains a root resource (`/`). The script retrieves all resources associated with the newly created API and extracts the ID of this root node.

The root resource identification uses the JMESPath expression below to filter the resource list and extract the ID of the root resource which is required to attach methods and child resources:

```sh
.items[] | select(.path=="/") | .id
```

This expression demonstrates several advanced JMESPath techniques:

- The `.items[]` syntax iterates through all items in the resources array
- The `select(.path=="/")` filter identifies resources where the path field exactly matches the root path
- The `.id` projection extracts only the ID field from matching resources

A fallback mechanism is included in case the root resource is not explicitly labeled with the `"/"` path, which adds resilience against edge cases in AWS responses.

```sh
ROOT_RESOURCE_ID=$(echo "$RESOURCES_RESPONSE" | jq -r '.items[0].id')
```

This fallback was developed after encountering specific AWS API responses where the root resource was present but not properly identified by the path-based filter. The fallback approach selects the first resource in the list, which is typically the root resource in API Gateway's resource hierarchy.

The conditional logic implements comprehensive checking for both empty strings and JSON null values, ensuring that the script can handle various failure modes in the AWS API response parsing.

```sh
[[ -z "$ROOT_RESOURCE_ID" || "$ROOT_RESOURCE_ID" == "null" ]]
```

### Creating the `{proxy+}` Resource

To support a flexible backend architecture, the script creates a `{proxy+}` resource beneath the root.

```bash
aws --profile "$AWS_PROFILE" \
    apigateway create-resource \
    --rest-api-id "$API_ID" \
    --parent-id "$ROOT_RESOURCE_ID" \
    --path-part "{proxy+}"
```

This resource captures all subpaths (for example `/predict`, `/health`, or `/v1/items/123`) and forwards them through a single integration. This design dramatically simplifies backend routing and is the standard approach for Lambda-backed APIs.

The proxy resource creation command:

- The `--parent-id "$ROOT_RESOURCE_ID"` parameter establishes the hierarchical relationship between the root resource and the proxy resource, creating a tree structure where the proxy resource becomes a child of the root. This hierarchy is essential for API Gateway's request routing logic, which traverses the resource tree to match incoming requests to appropriate handlers.

- The `--path-part "{proxy+}"` parameter implements API Gateway's greedy path parameter syntax, which has specific semantic meaning in the API Gateway routing engine. The curly braces `{}` indicate that this is a path parameter rather than a literal path segment, while the `+` suffix specifies greedy matching behavior that captures all remaining path segments in a single parameter.

- The greedy path parameter `{proxy+}` enables the proxy resource to match any request path that extends beyond the root, including:

  - `/predict` → captured as `proxy = "predict"`
  - `/health/check` → captured as `proxy = "health/check"`
  - `/v1/models/chicago-crimes/predict` → captured as `proxy = "v1/models/chicago-crimes/predict"`

This pattern dramatically simplifies API Gateway configuration by eliminating the need to define individual resources for each backend endpoint. Instead, the backend application receives the full path information and can implement its own internal routing logic, providing maximum flexibility for API evolution and feature development.

Before creating the resource, the script checks whether it already exists, ensuring safe re-execution. The existing proxy resource detection uses JMESPath filtering to identify proxy resources by their path part rather than their full path.

 ```sh
jq -r '.items[] | select(.pathPart=="{proxy+}") | .id'
 ```

This approach is necessary because proxy resources have a different path representation in API Gateway's resource model, where the `pathPart` field contains the parameter definition while the `path` field might contain the resolved path structure.

### Explaining expected 500 errors (intentional behavior)

Before creating any methods, the script includes an explicit note explaining that requests will return HTTP 500 errors at this stage.

```text
# At this stage, methods are created WITHOUT backend integrations.
# Requests WILL return HTTP 500 until Lambda is attached.
```

This is an important piece of documentation embedded directly in the code. Without this explanation, a developer testing the API might incorrectly assume something is broken. In reality, this behavior is expected because API Gateway methods without integrations have no execution target.

### HTTP Method Configuration and Request Parameter Mapping

The HTTP method configuration implements API Gateway's method model, establishing the interface contract between clients and the backend while configuring request parameter mapping for proxy integration.

The root resource method creation, shown below, establishes a catch-all method on the root resource that handles all HTTP verbs (`GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`, `OPTIONS`).

```sh
aws --profile "$AWS_PROFILE" \
    apigateway put-method \
    --rest-api-id "$API_ID" \
    --resource-id "$ROOT_RESOURCE_ID" \
    --http-method ANY \
    --authorization-type NONE
```

This configuration ensures that requests sent directly to the API root URL are handled consistently with requests sent to deeper paths, preventing common operational issues where root-level health checks or documentation requests fail unexpectedly.

- The `--authorization-type NONE` parameter disables API Gateway's built-in authorization mechanisms, deferring authentication and authorization decisions to the backend application. This approach provides maximum flexibility for implementing custom authentication schemes, OAuth integration, or other security patterns that might not align with API Gateway's built-in authorization models.

The proxy resource method creation includes additional complexity through the  request  parameter, which configures API Gateway's request parameter mapping for proxy integration.

```sh
--request-parameters '{"method.request.path.proxy":true}'
```

This configuration tells API Gateway to extract the path parameter captured by the `{proxy+}` resource and make it available to the backend integration as `method.request.path.proxy`.

The request parameter mapping is essential for proxy integration because it enables the backend to receive the original request path information that was captured by the greedy path parameter. Without this mapping, the backend would receive only the base API Gateway request structure without knowledge of the specific path that was requested, making internal routing impossible.

The parameter mapping syntax `{"method.request.path.proxy":true}` follows API Gateway's parameter mapping model, where:

- `method.request.path.proxy` specifies the parameter location and name
- `true` indicates that the parameter is required and should be passed to the integration

This configuration becomes critical when the Lambda integration is established, as it ensures that the Lambda function receives complete request context including the original path, enabling sophisticated internal routing and request handling logic.

Authorization is intentionally set to `NONE` at this stage. Authentication and authorization are deferred until the full backend architecture is in place.

### Deploying the API to a stage

With resources and methods in place, the API is deployed to a stage defined in configuration.

```bash
aws apigateway create-deployment \
  --stage-name "$STAGE_NAME"
```

Deployments are required for changes to become publicly accessible. By using a configurable stage name (for example `dev`), the script supports multiple environments without code changes.

### Final output and operational guidance

At the end of the script, the API ID, endpoint URL, and resource IDs are printed for visibility.

```bash
https://$API_ID.execute-api.$REGION.amazonaws.com/$STAGE_NAME
```

A final warning reminds the user that HTTP 500 responses are expected until Lambda integration is added. This reinforces the earlier explanation and prevents unnecessary troubleshooting.

## How to run the script

To run the script normally:

```bash
./04-create-api-gateway.sh
```

The script can be safely re-run. If the API already exists, it will be reused rather than recreated.
