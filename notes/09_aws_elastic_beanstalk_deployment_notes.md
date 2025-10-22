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

## Elastic Beanstalk CLI Installation

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

When your application is no longer needed or when you want to avoid ongoing costs, proper cleanup is essential. The termination command removes all associated AWS resources:

```sh
eb terminate crime-arrest-classifier-env
```

This command safely removes the environment and all its associated resources, including EC2 instances, load balancers, security groups, and auto-scaling configurations. Proper termination prevents unexpected charges and maintains a clean AWS account structure.

## Advantages for ML Deployment

The Elastic Beanstalk deployment approach provides significant advantages for machine learning model deployment, including automatic scaling based on demand, built-in health monitoring and recovery, simplified deployment and rollback procedures, and integration with other AWS services. This deployment strategy transforms a local machine learning model into a robust, production-ready service capable of handling real-world traffic patterns while maintaining high availability and performance standards.
