# DynamoDB Table Setup

The DynamoDB table deployment script, `05-create-dynamodb.sh`, represents the sophisticated implementation of Amazon DynamoDB's NoSQL database infrastructure, establishing the persistent data layer that serves as the primary storage mechanism for processing results in the Chicago Crimes prediction application. This script implements a serverless-first approach to data persistence, leveraging DynamoDB's managed infrastructure to provide scalable, high-performance storage without the operational overhead of traditional database management. By choosing DynamoDB's managed infrastructure, the application eliminates the need for database server provisioning, backup management, security patching, and capacity planning while gaining access to enterprise-grade features like automatic scaling, built-in security, and global replication capabilities.

The implementation demonstrates advanced AWS CLI operations, table schema design principles, and the intricate relationships between DynamoDB's billing models, key schemas, and operational characteristics.

## Script Foundation and Serverless Database Philosophy

The DynamoDB deployment script establishes a foundation built upon serverless database principles that eliminate the need for capacity planning, server management, and infrastructure scaling decisions while providing enterprise-grade performance and reliability.

The script initialization follows the established pattern of strict bash execution with `set -euo pipefail`, implementing comprehensive error handling that prevents partial DynamoDB configuration. The `-e` flag ensures immediate exit on any command failure, `-u` prevents undefined variable usage, and `-o pipefail` ensures pipeline failures are properly detected. This combination becomes particularly critical for DynamoDB deployment because the service involves complex table creation processes where partial configuration can create tables in inconsistent states that are difficult to diagnose and resolve.

The configuration loading mechanism uses `source "$(dirname "$0")/00-config.sh"` with explicit error handling that provides clear feedback when the centralized configuration cannot be loaded. This approach becomes essential for DynamoDB because the service requires precise coordination between regional table endpoints, account-specific table naming conventions, and application-specific schema definitions. The centralized configuration pattern ensures consistency across all deployment scripts while maintaining the flexibility to adapt to different AWS accounts, regions, and application requirements.

## Idempotent Table Management and Resource Discovery

The DynamoDB table management implements sophisticated idempotency patterns that allow safe re-execution while avoiding resource duplication and the associated costs and complexity of managing multiple table instances with potentially conflicting schemas.

The existing table detection uses the command below to query DynamoDB's control plane for information about the specified table:

```sh
aws --profile "$AWS_PROFILE" \
    dynamodb describe-table \
    --table-name "$RESULTS_TABLE"
```

This command represents a read-only operation that provides comprehensive metadata about the table's current state, including its schema definition, billing configuration, and operational status.

The table existence check `>/dev/null 2>&1` pattern suppresses both stdout and stderr output while preserving the command's exit code, enabling the script to detect table existence without cluttering the user interface with verbose AWS CLI responses. This approach allows the conditional logic to make decisions based on command success or failure while maintaining clean, user-friendly output formatting.

When an existing table is found, the script retrieves detailed status information using:

```sh
aws --profile "$AWS_PROFILE" \
    dynamodb describe-table \
    --table-name "$RESULTS_TABLE" \
    --query 'Table.TableStatus' \
    --output text
```

 This command demonstrates advanced AWS CLI query capabilities using JMESPath syntax to extract specific fields from complex JSON responses. The query `'Table.TableStatus'` navigates the nested JSON structure returned by the describe-table operation and extracts only the status field, while `--output text` returns the result as plain text rather than JSON, making it suitable for direct assignment to bash variables and user display.

The table status information provides critical operational context about the table's current state, which can include values like `"CREATING"`, `"ACTIVE"`, `"UPDATING"`, or `"DELETING"`. This status visibility enables users and operators to understand the table's readiness for application use and helps diagnose potential issues with table availability or configuration changes.

## Table Schema Design and Key Architecture

The DynamoDB table creation implements a carefully designed schema that balances application requirements with DynamoDB's performance characteristics and cost optimization principles.

### Table Creation

The table creation command initiates the table creation process with the application-specific table name defined in the centralized configuration.

```sh
aws --profile "$AWS_PROFILE" \
    dynamodb create-table \
    --table-name "$RESULTS_TABLE"
```

The table name becomes a critical identifier that must be consistent across all application components and deployment environments.

### Key Schema Data Type

The attribute definitions parameter defines the data types for attributes that will be used in key schemas or secondary indexes:

```sh
--attribute-definitions AttributeName=file_key,AttributeType=S
```

- In DynamoDB's schema model, only attributes used in keys need to be predefined, while all other attributes can be added dynamically as items are inserted.

- The specification `AttributeName=file_key,AttributeType=S` defines a single attribute named `"file_key"` with data type `"S"` (String), establishing the foundation for the table's primary key structure.

- The choice of `"file_key"` as the primary key attribute reflects the application's data access patterns and business logic requirements. In the Chicago Crimes prediction application, each processing job corresponds to a specific file uploaded to S3, and the file key (S3 object key) provides a natural, unique identifier for tracking processing results. This design enables efficient retrieval of processing results based on the original file identifier, supporting both application queries and operational monitoring requirements.

### Hashing in DynamoDB

The key schema parameter establishes the table's primary key structure using DynamoDB's hash key model.

```sh
--key-schema AttributeName=file_key,KeyType=HASH
```

The `KeyType=HASH` specification indicates that this attribute serves as the partition key (also called hash key), which DynamoDB uses to distribute items across multiple partitions for scalability and performance.

The hash key design provides several important characteristics:

- **Uniform distribution**: DynamoDB uses the hash key value to distribute items across multiple partitions, enabling horizontal scaling and high throughput
- **Direct access**: Applications can retrieve specific items directly using the hash key value without scanning multiple items
- **Predictable performance**: Hash key access provides consistent, low-latency performance regardless of table size
- **Cost efficiency**: Direct key access minimizes read capacity consumption compared to scan or query operations

The single-attribute primary key design (hash key only, without a range key) reflects the application's access patterns where each file processing job produces a single result record that needs to be retrieved by file identifier. This design optimizes for the primary use case while maintaining simplicity in the data model.

### Billing Model Selection and Cost Optimization

The billing mode configuration `--billing-mode PAY_PER_REQUEST` implements DynamoDB's on-demand pricing model, which represents a strategic decision that aligns with serverless architecture principles and application usage patterns.

The `PAY_PER_REQUEST` billing mode provides several advantages for the Chicago Crimes prediction application:

- **Cost optimization for variable workloads**: The on-demand model charges only for actual read and write operations, eliminating the need to provision and pay for unused capacity. This approach is particularly beneficial for applications with unpredictable or intermittent usage patterns, where traditional provisioned capacity might result in over-provisioning and unnecessary costs.

- **Operational simplicity**: On-demand billing eliminates the need for capacity planning, monitoring, and adjustment procedures that are required with provisioned capacity models. The application can handle traffic spikes and quiet periods automatically without manual intervention or complex auto-scaling configurations.

- **Instant scalability**: The on-demand model can handle virtually unlimited throughput without pre-provisioning, enabling the application to process large batches of files or handle sudden increases in usage without performance degradation or capacity planning delays.

- **Development and testing efficiency**: During development and testing phases, the on-demand model provides cost-effective access to DynamoDB functionality without the overhead of capacity estimation and provisioning for non-production workloads.

The trade-offs of the on-demand model include slightly higher per-operation costs compared to optimally-provisioned capacity, but for applications with variable or unpredictable usage patterns, the operational benefits and cost predictability typically outweigh the marginal cost differences.

## Table Activation and Operational Readiness

The table activation process implements sophisticated waiting mechanisms that ensure the table is fully operational before the script completes, preventing race conditions and operational issues in subsequent deployment steps.

The table waiting command uses AWS CLI's built-in waiting functionality to poll the table status until it reaches an operational state.

```sh
aws --profile "$AWS_PROFILE" \
    dynamodb wait table-exists \
    --table-name "$RESULTS_TABLE"
```

This command implements exponential backoff and retry logic internally, providing robust handling of the asynchronous table creation process.

The `wait table-exists` operation specifically waits for the table to reach the `"ACTIVE"` status, which indicates that the table is fully created, configured, and ready to accept read and write operations. This waiting mechanism is essential because DynamoDB table creation is an asynchronous process that can take several seconds to several minutes depending on the table configuration and AWS service load.

The waiting mechanism prevents common deployment issues where subsequent scripts or application components attempt to use the table before it's fully operational, which would result in errors and deployment failures. By ensuring the table is active before proceeding, the script provides a reliable foundation for the remaining deployment steps.

After the waiting period completes, the script retrieves the final table status using the same `describe-table` command pattern used in the existence check. This final status verification provides confirmation that the table creation process completed successfully and gives users visibility into the table's operational state.

## Data Access Patterns and Application Integration

The table design reflects careful consideration of the application's data access patterns and integration requirements with other AWS services in the serverless architecture.

The primary access pattern involves storing processing results when Lambda functions complete file processing operations, and retrieving those results when users query the system through the web interface or API endpoints. The `file_key`-based primary key enables efficient storage and retrieval operations that align with the application's workflow.

The integration with S3 event triggers creates a natural data flow where S3 object keys become DynamoDB primary keys, establishing a direct relationship between uploaded files and their processing results. This design enables efficient correlation between file uploads, processing operations, and result storage without complex data transformation or mapping logic.

The table structure supports the application's notification and monitoring requirements by providing a centralized location for tracking processing status, results, and metadata. The Lambda functions can update processing status in real-time, while the web interface can query current status and results for user display.

The schema design accommodates future extensibility by leveraging DynamoDB's flexible attribute model, where additional metadata, processing parameters, or result details can be added to items without schema modifications or table restructuring.

## Operational Considerations and Monitoring Integration

The DynamoDB table implementation includes considerations for operational monitoring, troubleshooting, and maintenance procedures that support long-term system reliability and performance.

The table naming convention using centralized configuration enables consistent identification across different deployment environments while supporting environment-specific table instances for development, testing, and production workflows.

The on-demand billing model provides built-in cost monitoring and optimization, with AWS CloudWatch metrics automatically tracking read and write operations, throttling events, and cost accumulation. This monitoring integration enables proactive cost management and performance optimization without additional configuration.

The table design supports operational procedures like backup and restore operations through DynamoDB's built-in backup functionality, point-in-time recovery options, and export capabilities for data analysis and archival requirements.

The single-region deployment model provides cost optimization and latency benefits for the target use case, while the table design could be extended to support global replication through DynamoDB Global Tables if multi-region requirements emerge in the future.

## Security and Access Control Architecture

The DynamoDB table implementation relies on AWS IAM for access control and security, integrating with the broader serverless architecture's security model through role-based permissions and service-to-service authentication.

The table access is controlled through IAM policies attached to Lambda execution roles, API Gateway integration roles, and other service components that need to interact with the table. This approach provides fine-grained access control without embedding credentials or managing database-level authentication systems.

The integration with AWS CloudTrail provides comprehensive audit logging for all table operations, enabling security monitoring, compliance reporting, and forensic analysis of data access patterns and modifications.

The table design supports data encryption at rest through DynamoDB's built-in encryption capabilities, and encryption in transit through AWS's standard HTTPS/TLS protocols for all API communications.
