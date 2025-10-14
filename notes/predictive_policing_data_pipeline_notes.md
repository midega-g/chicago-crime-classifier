# Predictive Policing Data Pipeline: From Raw Crime Data to Arrest Prediction Models

## Project Foundation and Environment Setup

The development of a binary arrest prediction classifier for the Chicago Police Department begins with establishing a robust development environment using modern Python tooling. The project utilizes UV, a fast Python package manager, initialized through `uv init` to create the foundational project structure. The initial cleanup involves removing the default `main.py` file since this project follows a more structured approach with dedicated scripts and notebooks for different phases of the data science workflow.

The project architecture separates concerns through a well-organized directory structure created using `mkdir -p scripts data`, where the scripts folder houses the data extraction logic and exploratory analysis notebooks, while the data folder stores the processed datasets in compressed formats. Essential configuration files are established through `touch scripts/extract_data.py scripts/explore_data.ipynb .env config.conf Dockerfile`, providing the foundation for data processing, analysis, configuration management, and containerized deployment.

The dependency management strategy reflects the dual nature of production and development requirements. Core production dependencies are installed via `uv add scikit-learn fastapi uvicorn`, establishing the machine learning framework (scikit-learn), web API capabilities (FastAPI), and ASGI server (Uvicorn) for model deployment. Development dependencies are managed separately through `uv add --dev ipykernel pandas sodapy duckdb`, providing Jupyter notebook support, data manipulation capabilities, Socrata API integration, and high-performance analytical database functionality.

## Data Acquisition Strategy and Temporal Partitioning

The data extraction process implements a sophisticated temporal partitioning strategy that aligns with machine learning best practices for time-series data. Training data spans from 2022 to 2023, capturing two full years of crime incidents to establish robust patterns while maintaining recency. Validation data covers the entire 2024 period, providing a complete year for hyperparameter tuning and model selection without temporal leakage. Test data encompasses 2025 incidents up to the current date, ensuring the model's performance evaluation reflects real-world deployment conditions.

This temporal split strategy prevents data leakage that could artificially inflate model performance metrics, a critical consideration when dealing with time-dependent phenomena like crime patterns. The approach ensures that the model learns from historical patterns (2022-2023), validates against recent trends (2024), and demonstrates predictive capability on truly unseen future data (2025).

## Compression Strategy and Storage Optimization

The decision to utilize gzip compression instead of standard CSV format reflects both practical and performance considerations inherent in large-scale data science projects. Crime datasets from major metropolitan areas like Chicago contain millions of records, with the historical dataset spanning over two decades and approaching 8.4 million incidents. Uncompressed CSV files for such datasets can exceed several gigabytes, creating challenges for version control, data transfer, and storage costs.

Gzip compression typically achieves 80-90% size reduction for text-based data like crime reports, transforming multi-gigabyte files into manageable hundreds of megabytes. This compression ratio significantly improves data pipeline performance during file transfers, reduces cloud storage costs, and enables faster loading times when the data is decompressed directly into memory using pandas' native compression support. The compression strategy also facilitates version control inclusion of sample datasets and improves collaboration efficiency when sharing data artifacts across team members.

## Data Extraction Implementation and API Integration

The `extract_data.py` script is designed for robust, large-scale data acquisition from the City of Chicago's public safety data portal. The implementation begins with critical setup and configuration. It imports necessary libraries, with `sodapy` being essential for interacting with the Socrata Open Data API (SODA). The script then prioritizes security and flexibility by using a dual-configuration system: the `python-dotenv` library loads sensitive credentials like the `SOCRATA_TOKEN` and `SOCRATA_PASSWORD` from a `.env` file, keeping them out of the codebase, while the `configparser` library reads non-sensitive settings, such as the `socrata_domain` and `dataset_id`, from a `config.conf` file. This separation allows the same code to be easily deployed across different environments (development, staging, production) without modification.

```python
#!/usr/bin/env python

import pandas as pd
from datetime import datetime, timezone
from sodapy import Socrata
import time
import os
import configparser
from dotenv import load_dotenv

# Load environment variables and configuration
load_dotenv()
config = configparser.ConfigParser()
config.read('config.conf')
```

With the configuration loaded, the script initializes the Socrata client. This client object is the primary interface for all subsequent API calls, and it is instantiated with the domain, app token, and user credentials required for authenticated access.

```py
# Initialize Socrata client with configuration
client = Socrata(
    config['api']['socrata_domain'],
    os.getenv('SOCRATA_TOKEN'),
    username=config['api']['socrata_username'],
    password=os.getenv('SOCRATA_PASSWORD')
)
```

The core of the script's logic is a sophisticated pagination and batching system designed to efficiently and respectfully handle a dataset that is too large to download in a single request. The data is fetched in three distinct temporal batches to manage load, each defined by a specific date range in the `batches` list. For each batch, the script enters a pagination loop.

* It uses a `limit` of 100,000 records per page and an `offset` to track its position in the full dataset.
* Inside the loop, the `client.get()` method is called with a SoQL `where` clause (e.g., `"date between '2023-01-01T00:00:00' and '2023-12-31T23:59:59'"`) to filter data directly on the server, which is highly efficient when it comes to reducing bandwidth and processing overhead. This filter retrieves only the records for that specific year.
* The `where` clauses leverage ISO 8601 datetime formatting to ensure consistent temporal boundaries across different time zones and daylight saving transitions.
* The results for each page are appended to an accumulating list, `all_results`.
* The loop continues until a page returns fewer records than the `limit`, signaling the end of the available data for that batch.

```python
# Pagination parameters
limit = 100_000  # Rows per page

# Execute queries in sequence with pagination and 5-second sleep between pages
for i, (where, filename) in enumerate(batches):
    print(f"Fetching batch {i+1}/3: {filename}")
    offset = 0
    all_results = []  # Accumulate all pages here

    while True:
        try:
            # Fetch one page using 'where' parameter for SoQL filter
            page_results = client.get(
                config['api']['dataset_id'],
                where=where,
                limit=limit,
                offset=offset
            )

            # Append this page to the full list
            all_results.extend(page_results)

            print(f"Fetched {len(page_results)} rows (total so far: {len(all_results)})")

            # If fewer rows than limit, we've reached the end
            if len(page_results) < limit:
                break

            # Next page after a 5-second rest to respect rate limits
            time.sleep(5)
            offset += limit
        except Exception as e:
            print(f"Error fetching data: {e}.")
            time.sleep(10)
            break  # Or continue, but break to avoid infinite loop
```

Respecting the API's rate limits is crucial for reliability. After fetching each page of 100,000 records, the script pauses for 5 seconds using `time.sleep(5)` before requesting the next page. This mandatory delay prevents overwhelming the server and avoids being throttled or blocked. Furthermore, the code includes a try-except block to gracefully handle potential connection timeouts or API errors; if an error occurs, it is printed to the console, and the script waits for a longer 10-second period before breaking out of the loop for that specific batch, ensuring it doesn't get stuck in an infinite error cycle.

Finally, for each successfully fetched batch, the accumulated list of results (which are in JSON-like dictionary format) is converted into a Pandas DataFrame. This structured data is then persisted to the filesystem as a compressed Parquet file, a binary format that is efficient for storage and fast for subsequent reads. The filename is dynamically generated to include the batch identifier, creating organized outputs like `train_2022_2023.csv.gz`.

## Configuration Management and Security Practices

The project implements a dual-layer configuration strategy that balances security, flexibility, and maintainability. The .env file manages sensitive credentials that should never be committed to version control, including the Socrata API token and password. These credentials enable authenticated access to the Chicago Data Portal, providing higher rate limits and access to restricted datasets.

```txt
# Socrata API secrets
SOCRATA_TOKEN=<your_api_token>
SOCRATA_PASSWORD=<your_password>
```

The config.conf file handles non-sensitive configuration parameters that can be safely version-controlled and shared across team members. This includes the Socrata domain [data.cityofchicago.org](https://data.cityofchicago.org/), the dataset identifier (`ijzp-q8t2` for the Crimes 2001 to Present dataset), and the username for API authentication.

```txt
[api]
socrata_domain = data.cityofchicago.org
socrata_username = <your_email>
dataset_id = ijzp-q8t2
```

This configuration separation follows security best practices by ensuring that sensitive credentials remain environment-specific while maintaining reproducible configuration for the data pipeline. The approach facilitates deployment across different environments (development, staging, production) without code modifications.

## Development Environment Activation and Workflow

The project workflow emphasizes reproducible development practices through virtual environment management. The command `source .venv/bin/activate` activates the UV-managed virtual environment, ensuring dependency isolation and consistent package versions across different development machines. This activation step is crucial before executing any project scripts or notebooks, as it ensures access to the correct versions of pandas, scikit-learn, and other dependencies specified in the pyproject.toml configuration.

The development workflow typically begins with environment activation, followed by data extraction using the `scripts/extract_data.py` module, exploratory data analysis through the Jupyter notebook interface, and iterative model development using the established train/validation/test split strategy. This structured approach ensures reproducible results and facilitates collaboration among data science team members working on different aspects of the predictive policing initiative.
