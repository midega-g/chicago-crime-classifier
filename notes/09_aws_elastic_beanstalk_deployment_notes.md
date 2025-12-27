# AWS Elastic Beanstalk Deployment for Crime Arrest Classification Service

AWS Elastic Beanstalk provides a powerful platform-as-a-service solution for deploying web applications and services without the complexity of managing underlying infrastructure. For our crime arrest classification service, Elastic Beanstalk offers an ideal deployment strategy that handles load balancing, auto-scaling, health monitoring, and application versioning automatically. This approach transforms our containerized machine learning model into a production-ready web service that can handle varying traffic loads while maintaining high availability.

## Pre-Deployment Configuration

The deployment process begins with establishing proper AWS credentials and regional configuration. Before proceeding with Elastic Beanstalk deployment, it's essential to verify your AWS CLI configuration to ensure proper authentication and regional settings. The command below checks available AWS profiles:

```sh
aws configure list-profiles
```

Once you identify the appropriate profile, you can examine its configuration details using the following command, replacing `<myprofile>` with your actual profile name:

```sh
aws configure list --profile <myprofile>
```

To determine the specific region configured for your profile, use this command:

```sh
aws configure get region --profile <myprofile>
```

These preliminary steps ensure that your deployment targets the correct AWS region and uses the appropriate credentials, which is crucial for both security and cost optimization.

## Elastic Beanstalk CLI Installation (Optional)

The next phase involves installing the AWS Elastic Beanstalk CLI, which serves as the primary interface for managing deployments. Rather than using traditional pip installation, modern Python package management with `uv` provides faster and more reliable dependency resolution. The command below installs the Elastic Beanstalk CLI as a development dependency:

```sh
uv add awsebcli --dev
```

Installing as a development dependency is appropriate because the CLI tool is only needed during the deployment process, not within the running application container. After installation, verify that the CLI is properly accessible by checking its availability and help documentation:

```sh
eb --help
```

Alternatively, you can verify the installation location:

```sh
which eb
```

## Application Initialization

The initialization of an Elastic Beanstalk application establishes the foundational configuration for your deployment environment. The `eb init` command creates the necessary project structure and configuration files. For our crime arrest classification service, the initialization command specifies Docker as the platform, sets the application name, defines the target region, and uses a specific AWS profile:

```sh
eb init \
    -p docker crime-arrest-classifier \
    -r <region> \
    --profile <profile>
```

eb init \
    -p docker crime-arrest-classifier \
    -r us-east-1 \
    --profile r-dietto

This command produces output confirming the application creation: "Application crime-arrest-classifier has been created." The initialization process creates a `.elasticbeanstalk` directory containing a `config.yml` file that stores essential configuration parameters including the application name, default environment settings, platform specification, and regional deployment preferences. This configuration file serves as the blueprint for all subsequent deployment operations and can be version-controlled alongside your application code.

## Local Testing

Before deploying to the cloud, Elastic Beanstalk provides local testing capabilities that simulate the production environment. The local testing feature rebuilds the Docker image to incorporate any recent changes, including newly added dependencies like the Elastic Beanstalk CLI. The command below initiates local testing on port 8000:

```sh
eb local run --port 8000
```

During local testing, Elastic Beanstalk recreates the Docker image since modifications were made to the project dependencies. This process ensures that the local test environment accurately reflects the production deployment, including all recent code changes and dependency updates. Local testing provides confidence that the application will function correctly in the cloud environment before incurring deployment costs.

## Cloud Deployment

The cloud deployment process transforms your local application into a fully managed, scalable web service. The `eb create` command provisions all necessary AWS resources and deploys your application:

```sh
eb create crime-arrest-classifier-env
```

This deployment command initiates a comprehensive provisioning process that creates multiple AWS resources automatically. The output below demonstrates the extensive infrastructure setup that occurs during deployment:

```txt
Creating application version archive "app-1fb9-251022_200949986533".
Uploading: [##################################################] 100% Done...
Environment details for: crime-arrest-classifier-env
  Application name: crime-arrest-classifier
  Region: af-south-1
  Deployed Version: app-1fb9-251022_200949986533
  Environment ID: e-pkdgapqcmu
  Platform: arn:aws:elasticbeanstalk:af-south-1::platform/Docker running on 64bit Amazon Linux 2023/4.7.2
  Tier: WebServer-Standard-1.0
  CNAME: UNKNOWN
  Updated: 2025-10-22 17:11:16.230000+00:00
```

### Infrastructure Provisioning and Components

The deployment process creates several critical infrastructure components automatically. First, Elastic Beanstalk establishes an S3 storage bucket for environment data and application versions, as indicated by the message "Using `elasticbeanstalk-af-south-1-076181803615` as Amazon S3 storage bucket for environment data." Security groups are created to control network access, with both application-specific and load balancer security groups being provisioned.

The auto-scaling infrastructure includes the creation of an Auto Scaling group that can automatically adjust the number of running instances based on demand. The system also establishes scaling policies for both scale-up and scale-down operations, ensuring that your application can handle traffic spikes while minimizing costs during low-demand periods. CloudWatch alarms are configured to monitor application performance and trigger scaling actions when predefined thresholds are exceeded.

Load balancing capabilities are implemented through an Application Load Balancer that distributes incoming requests across multiple instances. The load balancer includes health checks to ensure that traffic is only routed to healthy instances, and it provides a stable endpoint for accessing your application. The final deployment message confirms successful completion: "Application available at crime-arrest-classifier-env.eba-jtwzks97.af-south-1.elasticbeanstalk.com."

### Monitoring and Management

To monitor and manage your deployed application, navigate to the AWS Console and ensure that your selected region matches the deployment region specified in your configuration. If you cannot locate your application in the console, use the hamburger menu to navigate to the Elastic Beanstalk service section. The console provides comprehensive monitoring capabilities, including application health status, request metrics, log access, and configuration management options.

Understanding the cost implications of Elastic Beanstalk deployment is crucial for budget management. While Elastic Beanstalk itself does not incur additional charges beyond the underlying AWS resources, the deployed infrastructure includes EC2 instances, load balancers, and other services that generate costs. The AWS Free Tier provides limited usage of these resources for new accounts, making it possible to experiment with deployments at minimal cost. For production deployments, consider implementing cost optimization strategies such as scheduled scaling, instance right-sizing, and environment termination during non-business hours.

### Security Consideration

Security considerations are paramount when deploying machine learning services to the cloud. By default, Elastic Beanstalk creates publicly accessible endpoints, which means your application is available to anyone with the URL. For production deployments, implement proper access controls through security groups, VPC configurations, and authentication mechanisms. Consider restricting access to specific IP ranges, implementing API authentication, or deploying within a private subnet with controlled access points.

### Cleanup and Termination

When your application is no longer needed or when you want to prevent ongoing charges, thorough cleanup becomes essential. The Elastic Beanstalk termination process handles most resources automatically, but a few items require manual intervention to achieve a completely clean AWS account.

The primary command to terminate an environment is:

```sh
eb terminate crime-arrest-classifier-env
```

This command initiates the safe deletion of the environment along with the majority of its associated AWS resources, such as EC2 instances, Elastic Load Balancers, Auto Scaling groups, security groups (when not in use by other resources), CloudWatch alarms, and SNS topics. The process typically completes within several minutes, after which Elastic Beanstalk no longer manages those components. Executing this step is the recommended first action for cleanup, as it eliminates most compute, networking, and monitoring costs associated with the environment.

However, the `eb terminate` command does not fully delete certain resources in all scenarios. The most common exception is the region-specific Elastic Beanstalk S3 bucket (named in the format `elasticbeanstalk-<region>-<account_id>`, such as `elasticbeanstalk-af-south-1-134618180303`). Elastic Beanstalk creates this bucket to store application versions, logs, configuration files, and other artifacts. To clean up this S3 bucket, first ensure it is completely empty by removing all remaining objects (including any versioned objects or delete markers):

```sh
ACCOUNT_ID=<enter-your-account-id>

aws s3 rm s3://elasticbeanstalk-af-south-1-${ACCOUNT_ID} --recursive
```

While this command automatically removes most objects within the bucket, the bucket itself remains due to a built-in bucket policy that contains an explicit Deny statement on the `s3:DeleteBucket` action. This protective policy prevents accidental deletion and must be modified or removed before the bucket can be deleted. To do so, run the command below to modify the Deny statement for `s3:DeleteBucket` to `Allow`:

```sh
aws s3api get-bucket-policy \
  --bucket elasticbeanstalk-af-south-1-${ACCOUNT_ID} \
  --query Policy \
  --output text | \
  jq '(.Statement[] | select(.Action=="s3:DeleteBucket")).Effect = "Allow"' > policy-modified.json
```

Then apply the updated policy:

```sh
aws s3api put-bucket-policy \
  --bucket elasticbeanstalk-af-south-1-${ACCOUNT_ID} \
  --policy file://policy-modified.json
```

Once the policy allows deletion, remove the empty bucket:

```sh
aws s3 rb s3://elasticbeanstalk-af-south-1-${ACCOUNT_ID}
```

Finally, clean up the temporary file:

```sh
rm policy-modified.json
```

**Other services and resources that may require manual cleanup**  
In addition to the S3 bucket, Elastic Beanstalk does not always delete the following items automatically during environment termination:

- **Application versions stored in S3** — While Elastic Beanstalk deletes its tracking records of versions, the actual source bundles (.zip files, etc.) often remain in the Elastic Beanstalk S3 bucket unless you explicitly choose to delete them during application deletion (via the console or `--delete-source-bundle` option with `eb delete-application`).
- **RDS databases** — If your environment includes an integrated RDS instance and you have not set its deletion policy to "Delete" (default is "Snapshot" or "Retain" in some configurations), the database persists after termination. To preserve data, change the policy to retain or snapshot before terminating.
- **Security groups** — These are usually deleted, but they can remain if referenced by external resources (e.g., ENIs, other EC2 instances, or manual configurations). In such cases, termination may fail or leave orphaned groups, requiring manual deletion via the EC2 console or CloudFormation stack adjustments.
- **CloudFormation stack remnants** — In rare failure cases, the underlying CloudFormation stack may enter a `DELETE_FAILED` state, leaving partial resources. You can retry deletion in the CloudFormation console or retain problematic resources (like RDS) and delete the stack manually.
