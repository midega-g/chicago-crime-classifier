import io
from pathlib import Path
import pandas as pd
import uvicorn
from fastapi import File, FastAPI, Request, UploadFile, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles

from chicago_crimes.data_loader import load_location_mapping, prepare_features
from chicago_crimes.feature_engineer import convert_to_dict_features
from chicago_crimes.model_trainer import load_model

app = FastAPI(title="Chicago Crime Arrest Prediction API", version="1.0.0")

# Get directories relative to this file
CURRENT_DIR = Path(__file__).parent
WEB_DIR = CURRENT_DIR / "web"
STATIC_DIR = WEB_DIR / "static"
TEMPLATES_DIR = WEB_DIR / "templates"
DATA_DIR = CURRENT_DIR.parent / "data"

# Create data directory if it doesn't exist
DATA_DIR.mkdir(exist_ok=True)

# Mount static directories
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
app.mount("/data", StaticFiles(directory=str(DATA_DIR)), name="data")

templates = Jinja2Templates(directory=str(TEMPLATES_DIR))

# Load location mapping once at startup
location_mapping = load_location_mapping()

# Remove the predict_arrests function since we're doing it inline


@app.get('/', response_class=HTMLResponse)
def home_page(request: Request):
    """Home endpoint with file upload interface."""
    return templates.TemplateResponse("index.html", {"request": request})


@app.post("/upload")
async def upload_predict(request: Request, file: UploadFile = File(...)):
    """Handle CSV file uploads for arrest predictions."""

    # Validate file type
    if not file.filename or not (file.filename.endswith(".csv") or file.filename.endswith(".csv.gz")):
        raise HTTPException(
            status_code=400, detail="File must be a CSV (.csv) or gzipped CSV (.csv.gz)")

    try:
        # Read CSV content (handle both regular and gzipped)
        contents = await file.read()

        if file.filename.endswith(".csv.gz"):
            df = pd.read_csv(io.BytesIO(contents),
                             compression='gzip', parse_dates=['date'])
        else:
            df = pd.read_csv(io.StringIO(
                contents.decode("utf-8")), parse_dates=['date'])

        # Prepare features using existing pipeline
        processed_df = prepare_features(df.copy(), location_mapping)
        processed_df = processed_df.dropna()

        # Make predictions using existing functions
        pipeline = load_model()
        feature_cols = [
            col for col in processed_df.columns if col not in ['arrest', 'id']]
        X = processed_df[feature_cols]
        X_dict = convert_to_dict_features(X)

        predictions = pipeline.predict(X_dict)
        probabilities = pipeline.predict_proba(X_dict)[:, 1]

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

        # Generate output filename
        input_filename = file.filename.replace(
            '.csv.gz', '').replace('.csv', '')
        output_filename = f"{input_filename}_arrest_predictions.csv"
        output_path = DATA_DIR / output_filename

        # Save minimal results as regular CSV
        result_df.to_csv(output_path, index=False)

        # Calculate summary statistics
        total_cases = len(result_df)
        predicted_arrests = sum(predictions)
        avg_probability = probabilities.mean()
        high_risk_cases = sum(result_df['risk_level'] == 'High')

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

    except (pd.errors.EmptyDataError, pd.errors.ParserError, ValueError, KeyError, FileNotFoundError) as e:
        return templates.TemplateResponse("results.html", {
            "request": request,
            "error": str(e),
            "success": False
        })


@app.get("/health")
def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "Chicago Crime Arrest Prediction API"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
