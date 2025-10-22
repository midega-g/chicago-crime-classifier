# Web Service Deployment and FastAPI Implementation for Machine Learning Model Serving

## Rationale for Web Service Architecture in Machine Learning Deployment

The transition from local model execution to web service deployment addresses several critical operational requirements that emerge when machine learning models move from development to production environments. A web service architecture enables multiple users to access the trained arrest prediction model simultaneously without requiring local installation of dependencies, model files, or technical expertise in Python programming. This democratization of access allows police departments, analysts, and decision-makers to utilize the predictive capabilities through a simple web interface rather than command-line execution.

Web services provide scalability advantages that local execution cannot match, enabling the model to handle concurrent requests from multiple users while maintaining consistent performance. The stateless nature of HTTP requests ensures that each prediction operates independently, preventing interference between different user sessions or data uploads. Additionally, web deployment facilitates centralized model management, allowing updates to the trained model or feature engineering pipeline without requiring redistribution to individual users.

The web service approach also enables integration with existing police department systems through API endpoints, allowing the arrest prediction functionality to be embedded within larger law enforcement software ecosystems. This integration capability transforms the model from an isolated analytical tool into a component of comprehensive decision support systems.

## FastAPI and Uvicorn Selection for High-Performance Web Services

The selection of FastAPI as the web framework reflects specific technical requirements for serving machine learning models in production environments. FastAPI provides automatic API documentation generation, request validation, and high-performance asynchronous request handling that traditional frameworks like Flask cannot match. The framework's built-in support for type hints enables automatic request and response validation, reducing the likelihood of runtime errors when users upload malformed data files.

FastAPI's asynchronous capabilities become particularly important when handling file uploads and machine learning inference, as these operations can be time-intensive and would block other requests in synchronous frameworks. The framework's integration with Pydantic for data validation ensures that uploaded files and request parameters conform to expected formats before reaching the model inference code.

Uvicorn serves as the ASGI (Asynchronous Server Gateway Interface) server that executes the FastAPI application, providing the high-performance foundation necessary for production deployment. Unlike traditional WSGI servers, Uvicorn's asynchronous architecture enables efficient handling of I/O-bound operations such as file uploads and database queries without blocking other requests.

## Core Implementation Architecture

### Import Dependencies and Module Integration

The implementation begins with strategic import statements that establish the foundational libraries and modules required for web service functionality, file processing, and machine learning inference:

```python
import io
from pathlib import Path
import pandas as pd
import uvicorn
from fastapi import File, FastAPI, Request, UploadFile, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
```

The `io` module provides in-memory file-like objects that enable pandas to read uploaded file contents without writing to disk. The `pathlib.Path` offers object-oriented filesystem path manipulation that works consistently across operating systems. The `pandas` import enables DataFrame operations for data processing and CSV file handling.

The FastAPI imports include the core framework (`FastAPI`), file upload handling (`File`, `UploadFile`), request processing (`Request`), error handling (`HTTPException`), HTML response generation (`HTMLResponse`), template rendering (`Jinja2Templates`), and static file serving (`StaticFiles`).

The integration with existing machine learning pipeline components is achieved through:

```python
from chicago_crimes.data_loader import load_location_mapping, prepare_features
from chicago_crimes.feature_engineer import convert_to_dict_features
from chicago_crimes.model_trainer import load_model
```

These imports connect the web service to the existing machine learning pipeline, enabling reuse of data processing, feature engineering, and model loading functionality without code duplication.

### Application Initialization and Configuration

```python
app = FastAPI(title="Chicago Crime Arrest Prediction API", version="1.0.0")
```

This line creates the central FastAPI application instance that coordinates all HTTP request handling. The `title` parameter appears in the automatically generated API documentation, providing a professional presentation for users accessing the `/docs` endpoint. The `version` parameter enables API versioning for future updates and backward compatibility management.

### Directory Structure and Path Resolution

The path resolution system uses `Path(__file__).parent` to determine the directory containing the current script, enabling relative path calculations that work regardless of execution context:

```python
# Get directories relative to this file
CURRENT_DIR = Path(__file__).parent
WEB_DIR = CURRENT_DIR / "web"
STATIC_DIR = WEB_DIR / "static"
TEMPLATES_DIR = WEB_DIR / "templates"
DATA_DIR = CURRENT_DIR.parent / "data"
```

The `WEB_DIR` points to the web assets directory containing HTML templates and static files. The `STATIC_DIR` holds CSS, JavaScript, and image files served directly to browsers. The `TEMPLATES_DIR` contains Jinja2 HTML templates for dynamic page generation. The `DATA_DIR` stores uploaded files and prediction results, located at the project root level.

```python
# Create data directory if it doesn't exist
DATA_DIR.mkdir(exist_ok=True)
```

This ensures the data directory exists before attempting to save prediction results, preventing runtime errors when users upload files. The `exist_ok=True` parameter prevents exceptions if the directory already exists.

### Static File Mounting and Template Configuration

```python
# Mount static directories
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
app.mount("/data", StaticFiles(directory=str(DATA_DIR)), name="data")

templates = Jinja2Templates(directory=str(TEMPLATES_DIR))
```

The mounting operations create URL endpoints that serve files directly from filesystem directories. The `/static` mount enables browsers to request CSS and JavaScript files through URLs like `/static/style.css`. The `/data` mount allows users to download prediction result files through URLs like `/data/predictions.csv`. The template system enables embedding Python variables and logic within HTML files, supporting conditional rendering and data presentation.

## HTTP Methods and Endpoint Configuration

### Home Page Endpoint Implementation

The `@app.get()` decorator establishes HTTP GET endpoints that respond to browser requests for web pages or API data retrieval. GET requests represent the most common HTTP method for accessing web resources, designed for operations that retrieve information without modifying server state.

```python
@app.get('/', response_class=HTMLResponse)
def home_page(request: Request):
    """Home endpoint with file upload interface."""
    return templates.TemplateResponse("index.html", {"request": request})
```

The arguments within `get()` define the URL path that triggers the function execution, with the root path `/` representing the main landing page. The `response_class=HTMLResponse` parameter instructs FastAPI to return HTML content rather than JSON, enabling the delivery of complete web pages to browser clients.

### File Upload Endpoint Implementation

The `@app.post()` decorator handles HTTP POST requests, which are designed for operations that submit data to the server for processing. File uploads require POST requests because they involve sending data that modifies server state by triggering model inference and generating prediction results.

```python
@app.post("/upload")
async def upload_predict(request: Request, file: UploadFile = File(...)):
    """Handle CSV file uploads for arrest predictions."""
```

The `async` keyword enables asynchronous processing of file uploads, allowing the server to handle other requests while file reading operations complete. The `UploadFile` type provides a file-like interface that abstracts the complexities of multipart data parsing and temporary file management. The `File(...)` parameter with ellipsis indicates a required file upload, causing FastAPI to automatically validate that a file is present in the request before executing the function.

## File Upload Processing Pipeline

### File Validation and Type Checking

File type validation occurs before processing to provide immediate feedback for unsupported formats:

```python
# Validate file type
if not (file.filename.endswith(".csv") or file.filename.endswith(".csv.gz")):
    raise HTTPException(status_code=400, detail="File must be a CSV (.csv) or gzipped CSV (.csv.gz)")
```

The `HTTPException` with status code 400 (Bad Request) returns a user-friendly error message that appears in the web interface.

### Asynchronous File Reading and Format Detection

The asynchronous file reading implementation addresses memory management concerns that arise when processing user-uploaded files of unknown size:

```python
try:
    # Read CSV content (handle both regular and gzipped)
    contents = await file.read()
    
    if file.filename.endswith(".csv.gz"):
        df = pd.read_csv(io.BytesIO(contents), compression='gzip', parse_dates=['date'])
    else:
        df = pd.read_csv(io.StringIO(contents.decode("utf-8")), parse_dates=['date'])
```

The `await file.read()` operation yields control to other requests while file I/O completes, preventing the server from becoming unresponsive during large file processing. The dual-format support for regular and gzipped CSV files accommodates different user preferences and file size constraints. The `io.BytesIO()` wrapper enables pandas to read binary gzipped data as if it were a file object, while `io.StringIO()` provides the same interface for text-based CSV data after UTF-8 decoding.

### Feature Engineering Pipeline Integration

The web service leverages the existing machine learning pipeline to ensure consistency between training and prediction phases:

```python
# Load location mapping once at startup
location_mapping = load_location_mapping()

# Prepare features using existing pipeline
processed_df = prepare_features(df.copy(), location_mapping)
processed_df = processed_df.dropna()
```

Loading the location mapping at application startup rather than for each request improves performance by avoiding repeated file I/O operations. The `df.copy()` operation creates a defensive copy preventing modifications to the original uploaded data. The `prepare_features()` function applies the same feature engineering transformations used during model training, ensuring consistency between training and prediction phases. The `dropna()` operation removes rows with missing values that could cause prediction errors.

### Data Loader Modifications for ID Preservation

The modifications to `data_loader.py` address a critical data integrity issue that emerges when processing user-uploaded files through the web service. The original implementation could lose track of record identifiers during feature engineering and data cleaning operations, making it impossible to correlate predictions with original records.

```python
def prepare_features(df, location_mapping):
    """Extract temporal features and apply location mapping."""
    # Preserve ID column if it exists
    id_col = df['id'].copy() if 'id' in df.columns else None
    
    # Other feature engineering logic go here
    
    # Re-add ID column if it existed
    if id_col is not None:
        df['id'] = id_col

    return df
```

This preservation mechanism ensures that user-provided identifiers travel through the entire feature engineering pipeline, maintaining the connection between input records and prediction outputs. The approach creates a copy of the ID column before any transformations occur, then reattaches it after feature engineering completes, ensuring that row-level correspondence remains intact even when other columns are modified or removed.

This modification becomes particularly important in the web service context where users upload their own data files and expect to receive predictions that can be matched back to their original records. Without ID preservation, the prediction results would be essentially unusable for operational decision-making.

## Model Inference and Prediction Generation

### Model Loading and Feature Selection

```python
# Make predictions using existing functions
pipeline = load_model()
feature_cols = [col for col in processed_df.columns if col not in ['arrest', 'id']]
X = processed_df[feature_cols]
X_dict = convert_to_dict_features(X)
```

The `load_model()` function retrieves the trained machine learning pipeline from disk. The feature column selection excludes the target variable (`arrest`) and identifier column (`id`) that should not be used for prediction. The `convert_to_dict_features()` function transforms the DataFrame into the dictionary format required by the scikit-learn `DictVectorizer` component of the pipeline.

### Prediction Generation and Probability Extraction

```python
predictions = pipeline.predict(X_dict)
probabilities = pipeline.predict_proba(X_dict)[:, 1]
```

The `pipeline.predict()` method generates binary predictions (0 or 1) for each input record. The `pipeline.predict_proba()` method returns probability estimates for both classes, with `[:, 1]` extracting only the probability of the positive class (arrest).

## Result Processing and Response Generation

### Result DataFrame Construction

The result construction creates a minimal output containing only essential prediction information:

```python
# Create minimal result DataFrame with only necessary columns
result_data = {
    'arrest_prediction': predictions,
    'arrest_probability': probabilities,
    'risk_level': pd.cut(
        probabilities,
        bins=[0, 0.3, 0.7, 1.0],
        labels=['Low', 'Medium', 'High']
    )
}

# Add ID if it exists in processed data
if 'id' in processed_df.columns:
    result_data['id'] = processed_df['id'].values

result_df = pd.DataFrame(result_data)
```

The `pd.cut()` function categorizes probabilities into risk levels using predefined thresholds: Low (0-30%), Medium (30-70%), and High (70-100%). The conditional ID inclusion preserves user-provided identifiers when present, enabling correlation with original records.

### Output File Generation and Storage

```python
# Generate output filename
input_filename = file.filename.replace('.csv.gz', '').replace('.csv', '')
output_filename = f"{input_filename}_arrest_predictions.csv"
output_path = DATA_DIR / output_filename

# Save minimal results as regular CSV
result_df.to_csv(output_path, index=False)
```

The filename generation removes file extensions from the original filename and appends a descriptive suffix. The `DATA_DIR / output_filename` creates a complete file path using pathlib operations. The `to_csv()` method saves results as an uncompressed CSV file with `index=False` preventing row numbers from appearing in the output.

### Summary Statistics Generation and Business Intelligence

The summary statistics calculation transforms raw prediction outputs into actionable business intelligence that supports operational decision-making:

```python
# Calculate summary statistics
total_cases = len(result_df)
predicted_arrests = sum(predictions)
avg_probability = probabilities.mean()
high_risk_cases = sum(result_df['risk_level'] == 'High')
```

These statistics provide immediate insight into the distribution of arrest probabilities across the uploaded dataset, enabling users to quickly assess whether their data contains predominantly high-risk or low-risk incidents. The high-risk case count specifically supports resource allocation decisions by quantifying the number of incidents that may require immediate attention.

### Success Response Generation

```python
return templates.TemplateResponse("results.html", {
    "request": request,
    "download_link": f"/data/{output_filename}",
    "filename": output_filename,
    "total_cases": total_cases,
    "predicted_arrests": predicted_arrests,
    "avg_probability": f"{avg_probability:.2%}",
    "high_risk_cases": high_risk_cases,
    "success": True
})
```

The template response renders the results page with comprehensive context data. The `download_link` provides the URL for accessing the prediction file. The percentage formatting `f"{avg_probability:.2%}"` converts decimal probabilities to readable percentages. The `success: True` flag enables conditional rendering in the template.

## Error Handling and System Reliability

### Comprehensive Exception Handling

```python
except Exception as e:
    return templates.TemplateResponse("results.html", {
        "request": request,
        "error": str(e),
        "success": False
    })
```

The exception handler catches any errors during file processing or prediction generation, returning an error page instead of crashing the application. The `str(e)` conversion provides a readable error message for debugging purposes.

### Health Check Endpoint

```python
@app.get("/health")
def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "Chicago Crime Arrest Prediction API"}
```

The health check endpoint enables monitoring systems to verify that the API is operational. The JSON response provides service identification and status information useful for automated health monitoring.

## Uvicorn Server Configuration and Deployment

### Server Launch Configuration

```python
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

The conditional execution block launches the Uvicorn server when the script runs directly. The `host="0.0.0.0"` parameter configures the server to accept connections from any network interface, enabling access from other computers on the same network rather than restricting access to localhost only. The `port=8000` parameter specifies the network port where the server listens for incoming HTTP requests. Port 8000 represents a common choice for development web servers, avoiding conflicts with standard HTTP (port 80) and HTTPS (port 443) services while remaining easily memorable for development purposes.

## API Documentation and Interactive Testing

FastAPI automatically generates interactive API documentation accessible at `http://localhost:8000/docs`, providing a comprehensive interface for testing endpoints and understanding request/response formats. This documentation system, built on OpenAPI specifications, enables developers and users to explore the API functionality without writing custom client code.

The documentation interface allows direct testing of file upload functionality, parameter validation, and response formats, significantly reducing the development time required for API integration. The automatic generation ensures that documentation remains synchronized with code changes, preventing the documentation drift that commonly occurs in manually maintained API specifications.

## Local vs API Prediction Implementation Differences

The naming distinction between `predict-local.py` and `predict-api.py` reflects fundamental architectural differences in how the machine learning model is accessed and utilized. The `predict-local.py` implementation assumes direct file system access and command-line execution, requiring users to have Python environments configured with all necessary dependencies and model files available locally.

The `predict-api.py` implementation transforms the same prediction logic into a web service that accepts HTTP requests, handles file uploads through multipart form data, and returns results through web responses. This architectural shift enables remote access to the model without requiring local installation or technical expertise from end users.

The API implementation also introduces additional layers of error handling, input validation, and response formatting that are unnecessary in local execution scenarios. These additions ensure robust operation when serving multiple concurrent users with varying levels of technical expertise and potentially malformed input data.

## API Launcher Script Implementation

A wrapper script `run_api.py` is then created to address several critical deployment challenges that arise in production machine learning systems. By abstracting the complexity of path resolution and execution context, it enables non-technical users to launch the prediction API with a single command. The error handling and user feedback mechanisms reduce support burden by providing clear guidance when issues occur. The cross-platform path handling ensures consistent behavior across development, testing, and production environments without requiring environment-specific configuration.

The script also serves as a foundation for future deployment automation, providing a stable interface that can be called by process supervisors, container orchestration systems, or continuous deployment pipelines. The separation between launcher and application logic allows for independent evolution of deployment procedures and API functionality while maintaining a simple user experience.

### Script Configuration and Execution Environment

The script begins with a shebang directive and module-level documentation that establishes its purpose as a simplified entry point for the Chicago Crime Prediction API:

```python
#!/usr/bin/env python3
"""
Simple script to run the Chicago Crime Prediction API
"""
```

The shebang line `#!/usr/bin/env python3` enables direct execution in Unix-like environments by instructing the system to use the `python3` interpreter available in the user's PATH. This approach provides flexibility across different deployment environments where Python might be installed in various locations. The module docstring immediately communicates the script's singular purpose - to provide a straightforward method for launching the prediction API without requiring users to navigate complex directory structures or remember intricate command-line parameters.

### Import Strategy for Cross-Platform Compatibility

```python
import sys
import subprocess
from pathlib import Path
```

The import selection focuses on modules that ensure reliable cross-platform operation and robust process management. The `sys` module provides access to system-specific parameters and functions, particularly the Python executable path and exit codes. The `subprocess` module enables the script to spawn new processes, allowing it to execute the main API script as a separate process while maintaining control over execution context. The `pathlib.Path` import offers object-oriented filesystem path manipulation that works consistently across Windows, macOS, and Linux systems, eliminating the need for OS-specific path handling logic.

### Path Resolution and Script Location Validation

```python
def main():
    # Get the project root directory
    project_root = Path(__file__).parent
    api_script = project_root / "src" / "predict-api.py"
```

The path resolution system uses `Path(__file__).parent` to dynamically determine the directory containing the current script, establishing the project root regardless of where the script is executed from. This approach enables users to run the script from any location within the project hierarchy while maintaining correct path calculations. The path construction using the `/` operator with `pathlib.Path` objects creates platform-appropriate file paths, automatically handling differences between Windows backslashes and Unix forward slashes.

```python
    if not api_script.exists():
        print(f"Error: API script not found at {api_script}")
        sys.exit(1)
```

The existence check provides immediate feedback if the expected API script is missing or the project structure doesn't match expectations. The explicit error message with the full path helps users diagnose configuration issues, while `sys.exit(1)` terminates execution with a non-zero status code that signals failure to calling processes or continuous integration systems.

### User Interface and Execution Feedback

```python
    print("Starting Chicago Crime Prediction API...")
    print("Access the web interface at: http://localhost:8000")
    print("Press Ctrl+C to stop the server")
    print("-" * 50)
```

The user feedback messages serve multiple purposes in the deployment workflow. The initial announcement confirms that the startup process has begun, providing psychological feedback that the system is responding to user input. The web interface URL gives users immediate access information without requiring them to consult documentation. The Ctrl+C instruction preemptively addresses a common point of confusion for users unfamiliar with stopping command-line servers. The visual separator line creates clear distinction between startup messages and subsequent server output, improving log readability.

### Subprocess Execution with Proper Context Management

```python
    try:
        # Run the API script
        subprocess.run([sys.executable, str(api_script)], cwd=str(project_root))
```

The subprocess execution strategy uses `sys.executable` to ensure the API script runs with the same Python interpreter that launched the wrapper, preventing version compatibility issues that could arise from environment variable inconsistencies. The list format `[sys.executable, str(api_script)]` provides explicit command and argument separation, avoiding shell injection vulnerabilities that could occur with string-based command construction. The `cwd=str(project_root)` parameter sets the working directory to the project root, ensuring that relative path calculations within the API script resolve correctly regardless of the user's current directory when invoking the launcher.

### Comprehensive Error Handling and Graceful Termination

```python
    except KeyboardInterrupt:
        print("\nAPI server stopped.")
    except Exception as e:
        print(f"Error running API: {e}")
        sys.exit(1)
```

The exception handling structure addresses both expected and unexpected termination scenarios. The `KeyboardInterrupt` exception specifically captures Ctrl+C signals, allowing the script to provide a clean termination message rather than displaying a Python traceback. The generic `Exception` handler catches any runtime errors during API startup or execution, converting technical exceptions into user-friendly error messages while maintaining proper process exit codes for automation scenarios.

### Main Guard and Script Entry Point

```python
if __name__ == "__main__":
    main()
```

The `if __name__ == "__main__":` conditional ensures the `main()` function only executes when the script is run directly, not when imported as a module. This pattern enables potential future reuse of the script's functionality while maintaining its primary role as an executable entry point. The explicit call to `main()` provides clear code structure and separates the script's configuration from its execution logic.

## Command-Line Interface and Development Workflow

The development and deployment workflow incorporates several command-line operations that establish the necessary environment and execute the web service. The editable installation command enables development mode where code changes are immediately reflected without reinstallation.

```sh
uv pip install -e .
```

The model training command ensures that a trained model exists before attempting to serve predictions, preventing runtime errors when users upload data for analysis.

```sh
python -m chicago_crimes.training.train_model
```

The API execution commands provide flexibility for different deployment scenarios, with the simplified `run_api.py` script abstracting the complexity of path resolution and server startup for non-technical users.

```sh
python run_api.py
```

The manual execution alternative provides direct control over the server startup process, enabling debugging and development scenarios where additional configuration may be necessary.

```sh
cd src && python predict-api.py
```

This comprehensive implementation provides a robust, scalable web service that makes the Chicago crime arrest prediction model accessible to non-technical users while maintaining the performance and reliability required for operational deployment.
