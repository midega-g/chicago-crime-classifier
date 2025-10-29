# flake8: noqa: E501
# Chicago Crimes ML Predictor - SNS VERSION
# This is the original Lambda function that used SNS for email notifications

import os

import boto3

# Reference configuration (would import from config in actual implementation)
ADMIN_EMAIL = "midegageorge2@gmail.com"
DEFAULT_RESULTS_TABLE = "chicago-crimes-results"
DEFAULT_UPLOAD_BUCKET = "chicago-crimes-uploads"
DEFAULT_REGION = "af-south-1"
S3_CONFIG = {
    "addressing_style": "virtual",
    "use_accelerate_endpoint": False,
    "use_dualstack_endpoint": False,
}

# Initialize AWS clients with SNS
REGION = os.environ.get("AWS_REGION", DEFAULT_REGION)
s3_config = boto3.session.Config(region_name=REGION, s3=S3_CONFIG)
s3_client = boto3.client("s3", config=s3_config)
dynamodb = boto3.resource("dynamodb", region_name=REGION)
# SNS client instead of SES
sns_client = boto3.client("sns", region_name=REGION)

# Environment variables including SNS_TOPIC_ARN
UPLOAD_BUCKET = os.environ.get("UPLOAD_BUCKET", DEFAULT_UPLOAD_BUCKET)
RESULTS_TABLE = os.environ.get("RESULTS_TABLE", DEFAULT_RESULTS_TABLE)
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")  # Required for SNS


def send_notification(summary, file_key):
    """Send email notification with prediction results via SNS"""

    if not SNS_TOPIC_ARN:
        print("SNS_TOPIC_ARN not configured, skipping notification")
        return

    try:
        # Ensure email subscription
        ensure_email_subscription()

        subject = f"Chicago Crimes Prediction Results - {file_key}"

        # Plain text message for SNS (HTML not supported)
        message = f"""Chicago Crimes Prediction Analysis Complete

File: {file_key}
Processing completed successfully.

RESULTS SUMMARY:
• Total Cases Analyzed: {summary['total_cases']:,}
• Predicted Arrests: {summary['predicted_arrests']:,}
• Average Arrest Probability: {summary['avg_probability']:.1%}
• High Risk Cases (>70%): {summary['high_risk_cases']:,}

Risk Distribution:
• High Risk Cases: {summary['high_risk_cases']:,} ({(summary['high_risk_cases']/summary['total_cases'])*100:.1f}%)
• Predicted Arrest Rate: {(summary['predicted_arrests']/summary['total_cases'])*100:.1f}%

This automated analysis helps identify cases with higher likelihood of arrest for resource allocation planning.

---
Chicago Crimes ML Prediction System"""

        # Send notification via SNS
        sns_client.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject, Message=message)

        print(f"Email notification sent for {file_key}")

    except Exception as e:
        print(f"Failed to send notification: {str(e)}")


def ensure_email_subscription():
    """Ensure admin email is subscribed to SNS topic"""
    try:
        # List current subscriptions
        response = sns_client.list_subscriptions_by_topic(TopicArn=SNS_TOPIC_ARN)

        # Check if email already subscribed
        for subscription in response["Subscriptions"]:
            if (
                subscription["Endpoint"] == ADMIN_EMAIL
                and subscription["Protocol"] == "email"
            ):
                return  # Already subscribed

        # Subscribe email
        sns_client.subscribe(
            TopicArn=SNS_TOPIC_ARN, Protocol="email", Endpoint=ADMIN_EMAIL
        )

        print(f"Subscribed {ADMIN_EMAIL} to SNS topic")

    except Exception as e:
        print(f"Error managing email subscription: {str(e)}")


# [Rest of Lambda function code would be the same...]
