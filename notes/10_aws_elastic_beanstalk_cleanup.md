# AWS Elastic Beanstalk Cleanup and Resource Termination

## Overview

When your application is no longer needed or when you want to prevent ongoing charges, thorough cleanup becomes essential. The Elastic Beanstalk termination process handles most resources automatically, but a few items require manual intervention to achieve a completely clean AWS account.

## Environment Termination

### Basic Environment Termination

The primary command to terminate an environment is:

```sh
eb terminate "${EB_APP_NAME}-env"
```

This command initiates the safe deletion of the environment along with the majority of its associated AWS resources, such as:

- EC2 instances
- Elastic Load Balancers
- Auto Scaling groups
- Security groups (when not in use by other resources)
- CloudWatch alarms
- SNS topics

The process typically completes within several minutes, after which Elastic Beanstalk no longer manages those components.

### Complete Application Termination

If you want to delete the application itself as well, use:

```sh
eb terminate "${EB_APP_NAME}-env" --all
```

Executing this step is the recommended first action for cleanup, as it eliminates most compute, networking, and monitoring costs associated with the environment.

## Manual Resource Cleanup

### S3 Bucket Cleanup

The `eb terminate` command does not fully delete certain resources in all scenarios. The most common exception is the region-specific Elastic Beanstalk S3 bucket (named in the format `elasticbeanstalk-<region>-<account_id>`). Elastic Beanstalk creates this bucket to store application versions, logs, configuration files, and other artifacts.

#### Step 1: Empty the S3 Bucket

First, ensure the bucket is completely empty by removing all remaining objects (including any versioned objects or delete markers):

```sh
aws s3 rm \
  s3://elasticbeanstalk-${AWS_REGION}-${AWS_ACCOUNT_ID} \
  --recursive \
  --profile ${AWS_PROFILE_NAME} \
  --region ${AWS_REGION}
```

#### Step 2: Modify Bucket Policy

While the above command automatically removes most objects within the bucket, the bucket itself remains due to a built-in bucket policy that contains an explicit `Deny` statement on the `s3:DeleteBucket` action. This protective policy prevents accidental deletion and must be modified or removed before the bucket can be deleted.

To modify the `Deny` statement for `s3:DeleteBucket` to `Allow`:

```sh
aws s3api get-bucket-policy \
  --bucket elasticbeanstalk-${AWS_REGION}-${AWS_ACCOUNT_ID} \
  --query Policy \
  --profile ${AWS_PROFILE_NAME} \
  --region ${AWS_REGION} \
  --output text | \
  jq '(.Statement[] | select(.Action=="s3:DeleteBucket")).Effect = "Allow"' > policy-modified.json
```

The code above uses `jq` to modify the policy JSON and saves it to `policy-modified.json`.

#### Step 3: Apply Updated Policy

Then apply the updated policy:

```sh
aws s3api put-bucket-policy \
  --bucket elasticbeanstalk-${AWS_REGION}-${AWS_ACCOUNT_ID} \
  --profile ${AWS_PROFILE_NAME} \
  --region ${AWS_REGION} \
  --policy file://policy-modified.json
```

#### Step 4: Delete the Bucket

Once the policy allows deletion, remove the empty bucket:

```sh
aws s3 rb \
  s3://elasticbeanstalk-${AWS_REGION}-${AWS_ACCOUNT_ID} \
  --profile ${AWS_PROFILE_NAME} \
  --region ${AWS_REGION}
```

#### Step 5: Clean Up Temporary Files

Finally, clean up the temporary file:

```sh
rm policy-modified.json
```

### Other Resources Requiring Manual Cleanup

In addition to the S3 bucket, Elastic Beanstalk does not always delete the following items automatically during environment termination:

#### Application Versions

- **Issue**: While Elastic Beanstalk deletes its tracking records of versions, the actual source bundles (.zip files, etc.) often remain in the Elastic Beanstalk S3 bucket
- **Solution**: Use the `--delete-source-bundle` option with `eb terminate --all` or manually delete from S3

#### RDS Databases

- **Issue**: If your environment includes an integrated RDS instance and you have not set its deletion policy to "Delete" (default is "Snapshot" or "Retain" in some configurations), the database persists after termination
- **Solution**: Change the policy to retain or snapshot before terminating to preserve data

#### Security Groups

- **Issue**: These are usually deleted, but they can remain if referenced by external resources (e.g., ENIs, other EC2 instances, or manual configurations)
- **Solution**: Manual deletion via the EC2 console or CloudFormation stack adjustments may be required

#### CloudFormation Stack Remnants

- **Issue**: In rare failure cases, the underlying CloudFormation stack may enter a `DELETE_FAILED` state, leaving partial resources
- **Solution**: Retry deletion in the CloudFormation console or retain problematic resources (like RDS) and delete the stack manually

## IAM Resource Cleanup

After terminating the Elastic Beanstalk environment and associated infrastructure, clean up the IAM resources created specifically for this project: the IAM user (`chicago_crimes_eb_access`), the custom policy (`ChicagoCrimesElasticBeanstalkAccess`), and the roles/instance profile (`aws-eb-service-role` and `aws-eb-ec2-role`).

### Important Deletion Order

**Critical**: Always **delete the IAM user last**. Before deleting the user, you must first remove all attached credentials (especially access keys) and detach policies. You **cannot delete a managed policy** while it is still attached to any user, group, or role. Therefore, detach the policy from the user **before** deleting the policy.

### Step-by-Step IAM Cleanup Process

**Note**: Use your admin/root account or a privileged account for these steps.

#### Step 1: Deactivate and Delete Access Keys

Access keys must be deactivated before they can be deleted, and the user cannot be deleted if active keys exist.

**List access keys:**

```sh
aws iam list-access-keys \
    --user-name chicago_crimes_eb_access \
    --profile <your-admin-profile>
```

**Deactivate (if active):**

```sh
aws iam update-access-key \
  --access-key-id <ACCESS_KEY_ID> \
  --status Inactive \
  --user-name chicago_crimes_eb_access \
  --profile <your-admin-profile>
```

**Delete:**

```sh
aws iam delete-access-key \
  --access-key-id <ACCESS_KEY_ID> \
  --user-name chicago_crimes_eb_access \
  --profile <your-admin-profile>
```

**Console alternative**: IAM → Users → `chicago_crimes_eb_access` → Security credentials → Access keys → Actions → Deactivate → Delete.

#### Step 2: Detach Custom Policy from User

```sh
aws iam detach-user-policy \
  --user-name chicago_crimes_eb_access \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ChicagoCrimesElasticBeanstalkAccess \
  --profile <your-admin-profile>
```

**Console**: IAM → Users → `chicago_crimes_eb_access` → Permissions → Remove the policy.

#### Step 3: Delete Custom Policy

Before deletion, ensure it has no other attachments (list with `aws iam list-entities-for-policy --policy-arn ...`) and delete non-default versions if any exist.

```sh
aws iam delete-policy \
  --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ChicagoCrimesElasticBeanstalkAccess \
  --profile <your-admin-profile>
```

**Console**: IAM → Policies → Search for the policy → Delete (after detaching and cleaning versions).

#### Step 4: Delete Project Roles

If the roles are no longer needed anywhere:

**Detach all policies from the roles first** (use `list-attached-role-policies` and `detach-role-policy`).

**Remove the role from the instance profile** (if attached):

```sh
aws iam remove-role-from-instance-profile \
  --instance-profile-name aws-eb-ec2-role \
  --role-name aws-eb-ec2-role \
  --profile <your-admin-profile>
```

**Delete the roles:**

```sh
aws iam delete-role --role-name aws-eb-service-role --profile <your-admin-profile>
aws iam delete-role --role-name aws-eb-ec2-role --profile <your-admin-profile>
```

**Console**: IAM → Roles → Select role → Delete (after detaching policies).

#### Step 5: Delete IAM User

Once all attachments are removed:

```sh
aws iam delete-user \
  --user-name chicago_crimes_eb_access \
  --profile <your-admin-profile>
```

**Console**: IAM → Users → Select user → Delete.

#### Step 6: Remove Local AWS CLI Profile

**Optional but recommended:**

- Edit or delete the profile from `~/.aws/credentials` and `~/.aws/config` (Linux/macOS) or `%USERPROFILE%\.aws\` (Windows)
- Verify removal:

  ```sh
  aws configure list-profiles
  ```

If you're using **GitHub Codespaces**, you can now safely delete the codespace or clear its secrets/environment variables related to AWS credentials.

## Final Verification

After completing all cleanup steps, verify that no resources remain:

```sh
# Check for any remaining Elastic Beanstalk applications
aws elasticbeanstalk describe-applications --profile <your-admin-profile>

# Check for any remaining S3 buckets with the elasticbeanstalk prefix
aws s3 ls --profile <your-admin-profile> | grep elasticbeanstalk

# Verify IAM user deletion
aws iam get-user --user-name chicago_crimes_eb_access --profile <your-admin-profile>
# This should return an error if the user was successfully deleted
```

## Important Warnings

⚠️ **Warning**: Deleting these IAM resources is irreversible. Ensure no other projects or scripts depend on them. If in doubt, deactivate access keys and detach policies first (steps 1–2) and monitor for issues before full deletion.

⚠️ **Data Loss**: Once S3 buckets and RDS instances are deleted, the data cannot be recovered unless you have backups or snapshots.

With these steps completed, your AWS account should be fully cleaned of the Chicago Crimes ML project resources, preventing any ongoing charges.
