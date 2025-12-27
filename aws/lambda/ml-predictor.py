# flake8: noqa: E501
import os
import sys
import json
from io import BytesIO, StringIO
from decimal import Decimal

import boto3
import pandas as pd
from config import (
    API_PATHS,
    S3_CONFIG,
    ADMIN_EMAIL,
    CORS_HEADERS,
    DEFAULT_REGION,
    ERROR_MESSAGES,
    RISK_THRESHOLDS,
    LAMBDA_MODEL_PATH,
    DEFAULT_RESULTS_TABLE,
    DEFAULT_UPLOAD_BUCKET,
)

from chicago_crimes.data_loader import prepare_features, load_location_mapping
from chicago_crimes.model_trainer import load_model
from chicago_crimes.feature_engineer import convert_to_dict_features

# HTML Email Template
EMAIL_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
  <style>
    body {{
      font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif;
      background-color: #f1f5f9;
      margin: 0;
      padding: 40px 0;
    }}
    .container {{
      max-width: 600px;
      margin: auto;
      background-color: #ffffff;
      border-radius: 10px;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
      padding: 30px;
    }}
    h2 {{
      color: #1d4ed8;
      border-bottom: 2px solid #e2e8f0;
      padding-bottom: 10px;
      margin-bottom: 20px;
      margin-top: 0;
    }}
    .metrics-grid {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 15px;
      margin: 20px 0;
    }}
    .metric-card {{
      background-color: #f8fafc;
      border-radius: 8px;
      padding: 15px;
      border-left: 4px solid #3b82f6;
    }}
    .metric-label {{
      font-size: 12px;
      color: #64748b;
      text-transform: uppercase;
      font-weight: bold;
      margin-bottom: 5px;
    }}
    .metric-value {{
      font-size: 24px;
      font-weight: bold;
      color: #1e293b;
    }}
    .high-risk {{
      border-left-color: #dc2626;
    }}
    .arrest-rate {{
      border-left-color: #059669;
    }}
    .file-info {{
      background-color: #fef3c7;
      border: 1px solid #f59e0b;
      border-radius: 6px;
      padding: 12px;
      margin: 15px 0;
    }}
    .file-name {{
      font-weight: bold;
      color: #92400e;
      word-break: break-all;
    }}
    .footer {{
      margin-top: 30px;
      font-size: 12px;
      color: #94a3b8;
      text-align: center;
      border-top: 1px solid #e2e8f0;
      padding-top: 15px;
    }}
  </style>
</head>
<body>
  <div class="container">
    <h2>🚔 Chicago Crimes Prediction Results</h2>

    <div class="file-info">
      <div class="file-name">📁 {file_key}</div>
    </div>

    <div class="metrics-grid">
      <div class="metric-card">
        <div class="metric-label">Total Cases</div>
        <div class="metric-value">{total_cases:,}</div>
      </div>
      <div class="metric-card">
        <div class="metric-label">Predicted Arrests</div>
        <div class="metric-value">{predicted_arrests:,}</div>
      </div>
      <div class="metric-card arrest-rate">
        <div class="metric-label">Arrest Probability</div>
        <div class="metric-value">{avg_probability:.1%}</div>
      </div>
      <div class="metric-card high-risk">
        <div class="metric-label">High Risk Cases</div>
        <div class="metric-value">{high_risk_cases:,}</div>
      </div>
    </div>

    <div class="footer">
      🤖 Automated analysis from Chicago Crimes ML Prediction System<br>
      This analysis helps identify cases with higher arrest likelihood for resource planning.
    </div>
  </div>
</body>
</html>
"""


class DecimalEncoder(json.JSONEncoder):
    def default(self, o):
        if isinstance(o, Decimal):
            return float(o)
        return super(DecimalEncoder, self).default(o)


# Add the src directory to Python path
sys.path.append("/opt/src")

# Initialize AWS clients with region
REGION = os.environ.get("AWS_REGION", DEFAULT_REGION)

# Configure S3 client with regional endpoint to fix presigned URL generation
s3_config = boto3.session.Config(region_name=REGION, s3=S3_CONFIG)
s3_client = boto3.client("s3", config=s3_config)
dynamodb = boto3.resource("dynamodb", region_name=REGION)
ses_client = boto3.client("ses", region_name=REGION)

# Environment variables
UPLOAD_BUCKET = os.environ.get("UPLOAD_BUCKET", DEFAULT_UPLOAD_BUCKET)
RESULTS_TABLE = os.environ.get("RESULTS_TABLE", DEFAULT_RESULTS_TABLE)

# Load location mapping at startup (lightweight)
location_mapping = load_location_mapping()

# Lazy load model (heavy operation)
pipeline = None


def get_model():
    global pipeline
    if pipeline is None:
        model_path = (
            LAMBDA_MODEL_PATH if os.environ.get("AWS_LAMBDA_FUNCTION_NAME") else None
        )
        pipeline = load_model(model_path)
    return pipeline


def lambda_handler(event, context):
    """
    Lambda function to process uploaded crime data and return predictions.
    Triggered by S3 upload events or API Gateway requests.
    """

    try:
        # Handle S3 trigger events
        if "Records" in event:
            return handle_s3_event(event)

        # Handle API Gateway requests
        if "httpMethod" in event:
            return handle_api_request(event)

        return {
            "statusCode": 400,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Content-Type": "application/json",
            },
            "body": json.dumps({"error": ERROR_MESSAGES["INVALID_EVENT"]}),
        }

    except Exception as e:
        print(f"Lambda error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Content-Type": "application/json",
            },
            "body": json.dumps({"error": str(e)}),
        }


def handle_s3_event(event):
    """Process S3 upload event and generate predictions."""

    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]

        # Download file from S3
        response = s3_client.get_object(Bucket=bucket, Key=key)
        file_content = response["Body"].read()

        # Process the file
        try:
            if key.endswith(".csv.gz"):
                try:
                    df = pd.read_csv(BytesIO(file_content), compression="gzip")
                except Exception as gz_error:
                    if "CRC check failed" in str(gz_error):
                        error_msg = ERROR_MESSAGES["CORRUPTED_GZIP"].format(key)
                    else:
                        error_msg = ERROR_MESSAGES["DECOMPRESS_FAILED"].format(
                            str(gz_error)
                        )
                    print(f"Gzip error for {key}: {error_msg}")
                    store_error_result(key, error_msg)
                    return {"statusCode": 500, "body": json.dumps({"error": error_msg})}
            else:
                df = pd.read_csv(StringIO(file_content.decode("utf-8")))

            # Parse the 'date' column if it exists
            if "date" in df.columns:
                df["date"] = pd.to_datetime(df["date"], errors="coerce")

        except Exception as e:
            error_msg = ERROR_MESSAGES["FILE_PROCESSING_FAILED"].format(str(e))
            print(f"Error reading file {key}: {error_msg}")
            store_error_result(key, error_msg)
            return {"statusCode": 500, "body": json.dumps({"error": error_msg})}

        # Generate predictions
        results = process_predictions(df, key)

        # Store results in DynamoDB
        store_results(results, key)

    return {"statusCode": 200, "body": json.dumps({"message": "Processing completed"})}


def handle_api_request(event):
    """Handle direct API requests for predictions."""

    try:
        path = event.get("rawPath", event.get("path", ""))
        # Handle proxy path
        if path.startswith("/prod/"):
            path = path[5:]  # Remove /prod prefix
        elif (
            "pathParameters" in event
            and event["pathParameters"]
            and "proxy" in event["pathParameters"]
        ):
            path = "/" + event["pathParameters"]["proxy"]
        method = event["httpMethod"]

        if method == "POST" and path == API_PATHS["UPLOAD_URL"]:
            return handle_get_upload_url(event)

        elif method == "GET" and path.startswith(API_PATHS["RESULTS"]):
            return handle_get_results(event)

        elif method == "POST" and path == API_PATHS["PREDICT"]:
            body = json.loads(event["body"])

            # Single prediction
            if isinstance(body, dict):
                df = pd.DataFrame([body])
            else:
                df = pd.DataFrame(body)

            results = process_predictions(df, "api_request")

            return {
                "statusCode": 200,
                "headers": {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*",
                },
                "body": json.dumps(results),
            }

        elif method == "OPTIONS":
            # Handle CORS preflight requests
            return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

        elif method == "GET" and path == API_PATHS["HEALTH"]:
            return {
                "statusCode": 200,
                "headers": {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*",
                },
                "body": json.dumps({"status": "healthy"}),
            }

        return {
            "statusCode": 404,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Content-Type": "application/json",
            },
            "body": json.dumps({"error": ERROR_MESSAGES["NOT_FOUND"]}),
        }

    except Exception as e:
        print(f"API request error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Content-Type": "application/json",
            },
            "body": json.dumps({"error": str(e)}),
        }


def process_predictions(df, source_key):
    """Process DataFrame and generate predictions."""

    # Prepare features
    processed_df = prepare_features(df.copy(), location_mapping)
    processed_df = processed_df.dropna()

    # Make predictions using lazy-loaded model
    feature_cols = [col for col in processed_df.columns if col not in ["arrest", "id"]]
    X = processed_df[feature_cols]
    X_dict = convert_to_dict_features(X)

    model = get_model()
    predictions = model.predict(X_dict)
    probabilities = model.predict_proba(X_dict)[:, 1]

    # Create results
    results = {
        "predictions": predictions.tolist(),
        "probabilities": probabilities.tolist(),
        "risk_levels": [
            (
                "High"
                if p > RISK_THRESHOLDS["HIGH"]
                else "Medium" if p > RISK_THRESHOLDS["MEDIUM"] else "Low"
            )
            for p in probabilities
        ],
        "summary": {
            "total_cases": len(predictions),
            "predicted_arrests": int(sum(predictions)),
            "avg_probability": float(probabilities.mean()),
            "high_risk_cases": sum(
                1 for p in probabilities if p > RISK_THRESHOLDS["HIGH"]
            ),
        },
        "source": source_key,
    }

    return results


def store_results(results, file_key):
    """Store prediction results in DynamoDB and send email notification."""

    table = dynamodb.Table(RESULTS_TABLE)

    # Store in DynamoDB with file_key as primary key
    table.put_item(
        Item={
            "file_key": file_key,
            "total_cases": results["summary"]["total_cases"],
            "predicted_arrests": results["summary"]["predicted_arrests"],
            "avg_probability": Decimal(str(results["summary"]["avg_probability"])),
            "high_risk_cases": results["summary"]["high_risk_cases"],
            "processed_at": pd.Timestamp.now().strftime("%Y-%m-%d %H:%M:%S"),
            "status": "completed",
        }
    )

    # Send email notification
    send_notification(results["summary"], file_key)


def store_error_result(file_key, error_message):
    """Store error information in DynamoDB for user feedback."""

    table = dynamodb.Table(RESULTS_TABLE)

    table.put_item(
        Item={
            "file_key": file_key,
            "error_message": error_message,
            "processed_at": pd.Timestamp.now().strftime("%Y-%m-%d %H:%M:%S"),
            "status": "error",
        }
    )


def handle_get_upload_url(event):
    """Generate presigned URL for S3 upload."""
    body = json.loads(event["body"])
    filename = body["filename"]
    content_type = body.get("contentType", "text/csv")

    # Generate unique key
    import uuid
    from datetime import datetime

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    unique_id = str(uuid.uuid4())[:8]
    key = f"uploads/{timestamp}_{unique_id}_{filename}"

    # Generate presigned URL with correct regional endpoint
    upload_url = s3_client.generate_presigned_url(
        "put_object",
        Params={"Bucket": UPLOAD_BUCKET, "Key": key, "ContentType": content_type},
        ExpiresIn=3600,
        HttpMethod="PUT",
    )

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps({"uploadUrl": upload_url, "key": key}),
    }


def handle_get_results(event):
    """Get prediction results from DynamoDB."""
    from urllib.parse import unquote

    # Extract file key from path
    path = event.get("rawPath", event.get("path", ""))
    if path.startswith("/prod/"):
        path = path[5:]  # Remove /prod prefix

    # Extract key from /get-results/{key} path
    if path.startswith("/get-results/"):
        file_key = unquote(path[13:])  # Remove /get-results/ prefix
    else:
        path_params = event.get("pathParameters", {})
        file_key = unquote(path_params.get("key", ""))

    print(f"Looking for results with file_key: '{file_key}'")

    if not file_key:
        return {
            "statusCode": 400,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
            },
            "body": json.dumps({"error": "Missing file key parameter"}),
        }

    table = dynamodb.Table(RESULTS_TABLE)

    # Query by file_key
    response = table.get_item(Key={"file_key": file_key})

    if "Item" in response:
        item = response["Item"]

        # Check if processing failed
        if item.get("status") == "error":
            return {
                "statusCode": 400,
                "headers": {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*",
                },
                "body": json.dumps(
                    {
                        "status": "error",
                        "error": item.get("error_message", "Processing failed"),
                        "processed_at": item.get("processed_at"),
                    }
                ),
            }

        # Return successful results
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
            },
            "body": json.dumps(
                {
                    "status": "completed",
                    "data": {
                        "summary": {
                            "total_cases": item["total_cases"],
                            "predicted_arrests": item["predicted_arrests"],
                            "avg_probability": item["avg_probability"],
                            "high_risk_cases": item["high_risk_cases"],
                        }
                    },
                },
                cls=DecimalEncoder,
            ),
        }
    else:
        return {
            "statusCode": 404,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
            },
            "body": json.dumps(
                {"status": "processing", "message": "Results not ready yet"}
            ),
        }


def send_notification(summary, file_key):
    """Send HTML email notification with prediction results"""

    try:
        subject = f"Chicago Crimes Prediction Results - {file_key}"

        # Format HTML email using template
        html_message = EMAIL_TEMPLATE.format(
            file_key=file_key,
            total_cases=summary["total_cases"],
            predicted_arrests=summary["predicted_arrests"],
            avg_probability=summary["avg_probability"],
            high_risk_cases=summary["high_risk_cases"],
        )

        # Send HTML email via SES
        ses_client.send_email(
            Source=ADMIN_EMAIL,
            Destination={"ToAddresses": [ADMIN_EMAIL]},
            Message={
                "Subject": {"Data": subject},
                "Body": {"Html": {"Data": html_message}},
            },
        )

        print(f"HTML email notification sent for {file_key}")

    except Exception as e:
        print(f"Failed to send notification: {str(e)}")
