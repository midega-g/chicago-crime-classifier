# Test Data Files

This folder contains various test files for validating the Chicago Crimes upload system.

## Valid Files

- **valid_sample.csv** - Complete CSV with all required columns and proper data
- **valid_sample.csv.gz** - Properly compressed version of the valid CSV

## Invalid Files

### Missing Columns

- **missing_columns.csv** - CSV missing required columns (location_description, district, ward, community_area, fbi_code)

### Format Issues

- **malformed_csv.csv** - CSV with inconsistent column counts between rows
- **empty_file.csv** - Completely empty file
- **header_only.csv** - CSV with headers but no data rows

### Compression Issues

- **corrupted_gzip.csv.gz** - Truncated/corrupted gzip file that will fail CRC check

## Required Columns

The system expects these columns:

- date
- primary_type
- location_description
- arrest
- domestic
- district
- ward
- community_area
- fbi_code

## Testing

Use these files to test the validation system:

1. Upload valid files - should pass validation and process successfully
2. Upload invalid files - should show specific error messages before upload
