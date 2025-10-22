import pandas as pd

import os

# Determine the correct path based on current working directory
if os.path.exists('data/test_2025.csv.gz'):
    data_dir = 'data'
else:
    data_dir = '../data'

# Read the original test data
test_data = f'{data_dir}/test_2025.csv.gz'

# Read a larger sample first to ensure no overlap
all_sample = pd.read_csv(test_data, compression='gzip', nrows=1100)
print(f"Total rows read: {len(all_sample)}")

# Take first 100 rows for CSV
sample_100 = all_sample.head(100)

# Take next 1000 rows (completely different from first 100) for compressed CSV
sample_1000 = all_sample.iloc[100:1100]

# Save 100 random rows as CSV (uncompressed)
sample_100_csv = f'{data_dir}/test_2025_first_100_rows.csv'
sample_100.to_csv(sample_100_csv, index=False)
print(f"Saved first 100 rows to: {sample_100_csv}")

# Save 1000 different rows as compressed CSV
sample_1000_gz = f'{data_dir}/test_2025_next_1000_rows.csv.gz'
sample_1000.to_csv(sample_1000_gz, compression='gzip', index=False)
print(f"Saved next 1000 different rows to: {sample_1000_gz}")

# Print verification
print("\nVerification:")
print(f"- First file rows: {len(sample_100)}")
print(f"- Second file rows: {len(sample_1000)}")
print(f"- Overlap: {len(set(sample_100.index) & set(sample_1000.index))} (should be 0)")
print(f"- Total unique rows: {len(sample_100) + len(sample_1000)}")