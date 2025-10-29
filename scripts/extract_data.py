#!/usr/bin/env python

import os
import time
import configparser
from datetime import datetime, timezone

import pandas as pd
from dotenv import load_dotenv
from sodapy import Socrata

# Load environment variables and configuration
load_dotenv()
config = configparser.ConfigParser()
config.read("config.conf")

# Initialize Socrata client with configuration
client = Socrata(
    config["api"]["socrata_domain"],
    os.getenv("SOCRATA_TOKEN"),
    username=config["api"]["socrata_username"],
    password=os.getenv("SOCRATA_PASSWORD"),
)

# Ensure data directory exists
os.makedirs("data", exist_ok=True)

# Current UTC time truncated to milliseconds for test end date
now = datetime.now(timezone.utc)
end_date_str = now.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]

# Where clauses for each batch (using 'date' column as per dataset schema)
where_train = 'date >= "2022-01-01T00:00:00" AND date < "2024-01-01T00:00:00"'
where_val = 'date >= "2024-01-01T00:00:00" AND date < "2025-01-01T00:00:00"'
where_test = f'date >= "2025-01-01T00:00:00" AND date <= "{end_date_str}"'

# Dictionary to map where clauses to file names
batches = [
    (where_train, "train_2022_2023.csv"),
    (where_val, "val_2024.csv"),
    (where_test, "test_2025.csv"),
]

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
                config["api"]["dataset_id"], where=where, limit=limit, offset=offset
            )

            # Append this page to the full list
            all_results.extend(page_results)

            print(
                f"Fetched {len(page_results)} rows (total so far: {len(all_results)})"
            )

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

    # Convert to DataFrame and save
    df = pd.DataFrame.from_records(all_results)
    filepath = os.path.join("data", filename)
    print(f"Saving {len(df)} rows to {filepath}.gz")
    df.to_csv(filepath + ".gz", index=False, compression="gzip")
    print(f"Saved {len(df)} rows to {filepath}.gz")

    # Sleep 5 seconds before next batch (skip after last)
    if i < len(batches) - 1:
        print("Sleeping 5 seconds before next batch...")
        time.sleep(5)

print("Data extraction complete.")
