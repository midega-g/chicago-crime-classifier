# SNS Configuration Reference

This folder contains the original SNS-based email notification configuration that was replaced with SES.

## Files Included

1. **06-deploy-ml-lambda-docker-sns.sh** - Original deployment script with SNS setup
2. **ml-predictor-sns.py** - Original Lambda function using SNS for notifications
3. **09-cleanup-all-sns.sh** - Original cleanup script with SNS deletion

## Key SNS Components

### SNS Topic Creation

- Topic Name: `chicago-crimes-notifications`
- Topic ARN: `arn:aws:sns:REGION:ACCOUNT_ID:chicago-crimes-notifications`

### IAM Permissions

```json
{
    "Effect": "Allow",
    "Action": [
        "sns:Publish",
        "sns:Subscribe",
        "sns:ListSubscriptionsByTopic"
    ],
    "Resource": "arn:aws:sns:REGION:ACCOUNT_ID:chicago-crimes-notifications"
}
```

### Lambda Environment Variables

- `SNS_TOPIC_ARN` - Required for SNS publishing

## Migration to SES

SNS was replaced with SES because:

- **HTML Email Support**: SNS only supports plain text, SES supports rich HTML emails
- **Direct Email Delivery**: SES sends emails directly without requiring topic subscriptions
- **Better Email Features**: SES provides better email formatting and delivery options

## Usage Notes

These files are for reference only. The current system uses SES for email notifications.

# SNS Commands Reference

## Original SNS Setup Commands

### Create SNS Topic

```bash
aws sns create-topic --name chicago-crimes-notifications --region $REGION
```

### Subscribe Email to Topic

```bash
aws sns subscribe \
    --topic-arn "arn:aws:sns:$REGION:$ACCOUNT_ID:chicago-crimes-notifications" \
    --protocol email \
    --notification-endpoint "midegageorge2@gmail.com"
```

### List Subscriptions

```bash
aws sns list-subscriptions-by-topic \
    --topic-arn "arn:aws:sns:$REGION:$ACCOUNT_ID:chicago-crimes-notifications"
```

### Publish Message

```bash
aws sns publish \
    --topic-arn "arn:aws:sns:$REGION:$ACCOUNT_ID:chicago-crimes-notifications" \
    --subject "Test Subject" \
    --message "Test message content"
```

### Delete SNS Topic

```bash
aws sns delete-topic \
    --topic-arn "arn:aws:sns:$REGION:$ACCOUNT_ID:chicago-crimes-notifications"
```

## SNS vs SES Comparison

| Feature | SNS | SES |
|---------|-----|-----|
| Email Format | Plain text only | HTML + Plain text |
| Setup | Topic + Subscription | Direct email verification |
| Permissions | Topic-specific ARN | Wildcard resource |
| Delivery | Via topic subscription | Direct email delivery |
| Formatting | Limited | Rich HTML formatting |

## Migration Reasons

1. **HTML Support**: SES supports rich HTML emails with styling
2. **Simpler Setup**: No topic/subscription management needed
3. **Better Email Features**: Professional email formatting
4. **Direct Delivery**: No intermediate topic required
