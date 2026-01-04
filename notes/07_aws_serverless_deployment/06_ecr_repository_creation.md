# Container Registry Infrastructure for Serverless Lambda Deployment

The ECR repository deployment script, `07-create-ecr-repository.sh`, represents the foundational implementation of Amazon Elastic Container Registry infrastructure, establishing the private container registry that serves as the secure storage and distribution mechanism for Docker images in the Chicago Crimes prediction application's serverless architecture. This script implements AWS's managed container registry service to provide enterprise-grade image storage, security scanning, and lifecycle management without the operational overhead of maintaining private registry infrastructure.

The implementation demonstrates advanced AWS CLI operations, container registry security principles, and the intricate relationships between ECR repositories, Lambda container deployments, and CI/CD pipeline integration.

The container registry approach reflects a fundamental architectural decision that prioritizes managed infrastructure and integrated security over self-hosted registry solutions. By choosing ECR's managed infrastructure, the application eliminates the need for registry server provisioning, storage management, security patching, and backup procedures while gaining access to enterprise-grade features like vulnerability scanning, image signing, and seamless integration with AWS services like Lambda, ECS, and EKS.

## Script Foundation and Container Registry Architecture Philosophy

The ECR repository deployment script establishes a foundation built upon modern container registry principles that eliminate the need for self-managed registry infrastructure while providing enterprise-grade security, performance, and integration capabilities with AWS's serverless ecosystem.

The script initialization follows the established pattern of strict bash execution with `set -euo pipefail`, implementing comprehensive error handling that prevents partial ECR configuration. The `-e` flag ensures immediate exit on any command failure, `-u` prevents undefined variable usage, and `-o pipefail` ensures pipeline failures are properly detected. This combination becomes particularly critical for ECR deployment because the service involves complex repository creation processes where partial configuration can create repositories in inconsistent states that are difficult to diagnose and resolve, particularly when integrated with Lambda container deployments.

The configuration loading mechanism uses `source "$(dirname "$0")/00-config.sh"` with explicit error handling that provides clear feedback when the centralized configuration cannot be loaded. This approach becomes essential for ECR because the service requires precise coordination between regional registry endpoints, account-specific repository naming conventions, and application-specific image tagging strategies. The centralized configuration pattern ensures consistency across all deployment scripts while maintaining the flexibility to adapt to different AWS accounts, regions, and container deployment requirements.

## Idempotent Repository Management and Resource Discovery

The ECR repository management implements sophisticated idempotency patterns that allow safe re-execution while avoiding resource duplication and the associated costs and complexity of managing multiple repository instances with potentially conflicting configurations.

The existing repository detection uses the command below to query ECR's control plane for information about the specified repository.

```sh
aws --profile "$AWS_PROFILE" \
    ecr describe-repositories \
    --repository-names "$ECR_REPO"
```

This command represents a read-only operation that provides comprehensive metadata about the repository's current state, including its URI, creation timestamp, image scanning configuration, and lifecycle policies.

The repository existence check pattern `2>/dev/null || echo ""` demonstrates sophisticated error handling that suppresses stderr output while providing a fallback value when the repository doesn't exist. This approach prevents the script from failing when querying for non-existent repositories while enabling clean conditional logic based on the presence or absence of the repository.

The repository URI extraction uses advanced AWS CLI query capabilities with JMESPath syntax:

```sh
    --query 'repositories[0].repositoryUri' \
    --output text
```

This query demonstrates several important techniques:

- the `repositories[0]` selector accesses the first repository in the response array,
- the `.repositoryUri` projection extracts only the URI field, and
- `--output text` returns the result as plain text rather than JSON, making it suitable for direct assignment to bash variables and subsequent Docker operations.

The conditional logic `[[ -n "$REPO_URI" && "$REPO_URI" != "None" ]]` implements comprehensive checking that handles both empty results and AWS CLI's specific `"None"` return value when no repositories are found. This dual checking mechanism prevents the script from attempting to use invalid repository URIs in subsequent Docker operations, which would cause cryptic failures in the image build and push processes.

When an existing repository is found, the script provides clear feedback about the existing resource and exits gracefully, allowing subsequent scripts in the deployment pipeline to proceed with Docker image operations using the existing repository infrastructure.

## Repository Creation and Configuration Architecture

The ECR repository creation implements a carefully designed configuration that balances security requirements, operational efficiency, and integration capabilities with AWS's serverless Lambda container platform.

The repository creation command initiates the repository creation process with the application-specific repository name defined in the centralized configuration.

```sh
aws --profile "$AWS_PROFILE" \
    ecr create-repository \
    --repository-name "$ECR_REPO"
```

 The repository name becomes a critical identifier that must be consistent across all deployment scripts and container operations, as it forms part of the complete image URI used in Docker operations and Lambda function configurations.

The repository naming strategy reflects several important considerations:

- **Uniqueness**: The repository name must be unique within the AWS account and region, preventing conflicts with other applications or services
- **Consistency**: The name must be consistent across all deployment environments and scripts to ensure reliable automation
- **Readability**: The name should be human-readable and descriptive to support operational management and troubleshooting
- **Compliance**: The name must comply with ECR naming conventions, which allow lowercase letters, numbers, hyphens, underscores, and forward slashes

The image scanning configuration enables ECR's integrated vulnerability scanning capabilities, which automatically scan container images for known security vulnerabilities when they are pushed to the repository.

```sh
    --image-scanning-configuration scanOnPush=true
```

This configuration implements a security-first approach that provides several critical benefits:

- **Automated vulnerability detection**: ECR integrates with AWS's vulnerability database to identify known security issues in container images, including vulnerabilities in base images, application dependencies, and system packages. This automated scanning eliminates the need for separate security scanning tools and provides immediate feedback about image security posture.

- **Push-time scanning**: The `scanOnPush=true` configuration ensures that every image pushed to the repository is automatically scanned, providing immediate security feedback without requiring separate scanning workflows or manual intervention. This approach integrates security scanning directly into the CI/CD pipeline, enabling early detection of security issues.

- **Compliance and governance**: Automated vulnerability scanning supports compliance requirements and security governance policies by providing documented evidence of security scanning activities and vulnerability assessment results. This capability is particularly important for applications handling sensitive data or operating in regulated environments.

- **Cost optimization**: ECR's integrated scanning eliminates the need for separate vulnerability scanning infrastructure or third-party scanning services, reducing operational costs and complexity while providing enterprise-grade security capabilities.

The image tag mutability configuration allows image tags to be overwritten, providing flexibility for development and deployment workflows while supporting common container deployment patterns.

```sh
    --image-tag-mutability MUTABLE
```

The mutable tag configuration enables several important operational patterns:

- **Latest tag updates**: Development workflows can continuously update the `"latest"` tag with new image versions, simplifying development and testing procedures
- **Environment-specific tags**: Different deployment environments can use consistent tag names (like `"dev"`, `"staging"`, `"prod"`) that are updated as new versions are promoted through the deployment pipeline
- **Rollback capabilities**: Previous image versions remain available even when tags are updated, enabling quick rollback procedures if issues are detected
- **Simplified automation**: CI/CD pipelines can use consistent tagging strategies without requiring complex tag generation logic or version management systems

The trade-offs of mutable tags include potential confusion about which specific image version corresponds to a particular tag, but for applications with proper version control and deployment tracking, the operational benefits typically outweigh these concerns.

## Repository URI Generation and Integration Patterns

The repository URI extraction and management process demonstrates sophisticated integration patterns that enable seamless coordination between ECR repository creation and subsequent Docker operations in the deployment pipeline.

The repository URI retrieval uses similar approach as before, only that this time it is done after the repository has been created. Moreover, instead of repeating the same command to retrieve it, a helper function `get_ecr_repo_uri` defined in the `00-config.sh` is used as it will also be used in the subsequent scripts.

The obtained repository URI  will be used in subsequent Docker operations. It  follows the pattern `<account-id>.dkr.ecr.<region>.amazonaws.com/<repository-name>`, which encodes several critical pieces of information:

**Account isolation**: The account ID in the URI ensures that repository access is isolated to the specific AWS account, preventing accidental cross-account access or image confusion. This isolation is fundamental to ECR's security model and supports multi-tenant deployments where different applications or teams use separate AWS accounts.

**Regional specificity**: The region component ensures that Docker operations target the correct regional ECR endpoint, optimizing network performance and ensuring compliance with data residency requirements. Regional specificity also supports disaster recovery and multi-region deployment strategies.

**Repository identification**: The repository name component provides the specific repository identifier within the account and region, enabling precise targeting of image operations and supporting scenarios where multiple repositories exist within the same account.

The complete repository URI becomes the foundation for all subsequent Docker operations, including image tagging, pushing, and Lambda function configuration. The URI format is standardized across all AWS regions and accounts, providing consistency for automation and tooling integration.

## Container Registry Security and Access Control Architecture

The ECR repository implementation integrates with AWS's comprehensive security model to provide enterprise-grade access control, encryption, and audit capabilities without requiring additional security infrastructure or configuration.

The repository access control relies on AWS IAM for authentication and authorization, integrating with the broader serverless architecture's security model through role-based permissions and service-to-service authentication. This approach provides several security advantages:

1. **Fine-grained access control**: IAM policies can specify precise permissions for different operations (push, pull, delete) and different principals (users, roles, services), enabling least-privilege access patterns that minimize security exposure.

2. **Service integration**: AWS services like Lambda, ECS, and CodeBuild can access ECR repositories through IAM roles without requiring embedded credentials or complex authentication workflows, simplifying security management and reducing credential exposure risks.

3. **Cross-account access**: IAM policies and resource-based policies enable controlled cross-account access to repositories, supporting scenarios where different AWS accounts need to share container images while maintaining security boundaries.

4. **Audit and compliance**: Integration with AWS CloudTrail provides comprehensive audit logging for all repository operations, enabling security monitoring, compliance reporting, and forensic analysis of image access patterns and modifications. The encryption architecture provides comprehensive protection for container images at rest and in transit:

    - **Encryption at rest**: ECR automatically encrypts all container images using AWS-managed encryption keys, with options for customer-managed keys through AWS KMS for enhanced control and compliance requirements.

    - **Encryption in transit**: All communications with ECR use HTTPS/TLS encryption, protecting image data during push and pull operations and preventing man-in-the-middle attacks or data interception.

5. **Image signing and verification**: ECR integrates with AWS Signer and other image signing solutions to provide cryptographic verification of image integrity and authenticity, supporting supply chain security requirements and preventing tampering.

## Integration with Lambda Container Deployment Architecture

The ECR repository creation establishes the foundation for Lambda's container deployment model, which represents a sophisticated approach to serverless computing that combines the operational simplicity of Lambda with the flexibility and portability of container packaging.

The repository URI generated by this script becomes the critical link between the container build process and Lambda function deployment. Lambda's container support requires images to be stored in ECR repositories within the same AWS account, making the repository creation a prerequisite for container-based Lambda deployments.

The integration architecture supports several advanced deployment patterns:

- **Multi-stage builds**: The ECR repository can store intermediate build stages and final application images, supporting complex build processes that optimize image size and security through layer caching and build optimization techniques.

- **Version management**: The repository supports multiple image versions with different tags, enabling blue-green deployments, canary releases, and rollback procedures for Lambda functions without requiring separate repository instances.

- **Environment promotion**: Images can be built once and promoted through different deployment environments (development, staging, production) using consistent tagging strategies and repository access patterns.

- **CI/CD integration**: The repository integrates seamlessly with AWS CodePipeline, CodeBuild, and third-party CI/CD systems to provide automated build, test, and deployment workflows for containerized Lambda functions.

## Operational Considerations and Lifecycle Management

The ECR repository implementation includes considerations for long-term operational management, cost optimization, and maintenance procedures that support enterprise-scale container deployments.

The repository configuration supports automated lifecycle management through ECR lifecycle policies, which can automatically delete old or unused images based on age, count, or tag patterns. This capability is essential for controlling storage costs and maintaining repository organization as the number of image versions grows over time.

The image scanning configuration provides ongoing security monitoring that alerts operators to newly discovered vulnerabilities in existing images, enabling proactive security management and compliance maintenance. The scanning results integrate with AWS Security Hub and other security monitoring tools to provide centralized security visibility.

The repository metrics and monitoring integration with AWS CloudWatch provides operational visibility into repository usage patterns, image push and pull frequencies, and storage consumption trends. This monitoring capability supports capacity planning, cost optimization, and performance troubleshooting procedures.

The regional deployment model provides cost optimization and performance benefits for the target use case, while the repository design supports cross-region replication through ECR replication rules if multi-region deployment requirements emerge in the future.

## Cost Optimization and Storage Management Strategies

The ECR repository implementation incorporates several cost optimization strategies that balance storage costs with operational requirements and deployment flexibility.

The pay-per-use storage model charges only for actual image storage consumption, eliminating the need for capacity planning or pre-provisioning storage resources. This approach aligns with serverless architecture principles and provides cost predictability based on actual usage patterns.

The image layer deduplication automatically reduces storage costs by sharing common layers between different images in the repository. This deduplication is particularly beneficial for applications that use common base images or shared dependencies, as the storage cost is incurred only once for each unique layer.

The lifecycle policy integration enables automated cleanup of old or unused images, preventing storage cost accumulation from development and testing activities while preserving important production images and version history.

The regional storage model optimizes data transfer costs by storing images in the same region as the consuming Lambda functions, eliminating cross-region data transfer charges and improving deployment performance.
