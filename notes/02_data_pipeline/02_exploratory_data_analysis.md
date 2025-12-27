# Exploratory Data Analysis and Feature Engineering for Crime Arrest Prediction

## Understanding the Chicago Crime Dataset Structure

The Chicago crime dataset represents a comprehensive collection of reported incidents from the Chicago Police Department, with each row representing a single reported crime incident. The dataset contains 22 columns capturing various aspects of criminal incidents, from basic identifiers to detailed geographic and temporal information. Understanding the structure and characteristics of this data is crucial for developing an effective binary classification model to predict arrest outcomes.

The dataset includes unique identifiers such as ID and Case Number, temporal information through the Date field, geographic details ranging from broad community areas to specific block-level locations, crime classification through IUCR codes and Primary Type descriptions, and outcome indicators including the critical Arrest field that serves as our target variable. Geographic information spans multiple levels of granularity, from the finest Beat level (smallest police geographic area) up through Districts (22 total) and Community Areas (77 total), providing hierarchical spatial context for each incident. The table below shows these features and the unique values column is derived from data between 2022 and 2024 that was used to train the model.

| Column Name | Description | Data Type | Unique Values |
|-------------|-------------|-----------|---------------|
| ID | Unique identifier for the record | Number | 503,052 |
| Case Number | Chicago Police Department RD Number | Text | 502,983 |
| Date | Date when incident occurred | Floating Timestamp | 236,566 |
| Block | Partially redacted address | Text | 31,973 |
| IUCR | Illinois Uniform Crime Reporting code | Text | 334 |
| Primary Type | Primary description of IUCR code | Text | 31 |
| Description | Secondary description of IUCR code | Text | 312 |
| Location Description | Description of incident location | Text | 143 |
| Arrest | Indicates whether arrest was made | Checkbox | 2 |
| Domestic | Indicates domestic-related incident | Checkbox | 2 |
| Beat | Police beat where incident occurred | Text | 275 |
| District | Police district where incident occurred | Text | 23 |
| Ward | City Council district | Number | 50 |
| Community Area | Community area (77 total in Chicago) | Text | 77 |
| FBI Code | Crime classification per FBI NIBRS | Text | 26 |

## Strategic Column Selection and Cardinality Management

The initial exploration reveals significant challenges with high-cardinality features that could negatively impact binary classification performance. Using `nrows=0` in pandas allows efficient column inspection without loading the entire dataset into memory, enabling quick assessment of data structure and column types before committing computational resources to full data loading. This approach is particularly valuable when working with large datasets where initial exploration needs to be memory-efficient.

```python
temp_df = pd.read_csv(TRAIN_DATA_PATH, compression='gzip', nrows=0)
all_cols = temp_df.columns.tolist()

remove_cols = ['id', 'updated_on', 'block', 'iucr', 'beat', 'description', 'latitude', 'longitude', 'location', 'year', 'y_coordinate', 'x_coordinate', 'case_number', 'id']
include_cols = [inc_col for inc_col in all_cols if inc_col not in remove_cols]
```

High-cardinality features present multiple challenges for machine learning models, particularly in binary classification scenarios. Features with excessive unique values can lead to overfitting, increased computational complexity, and poor generalization performance. The original dataset contains several problematic high-cardinality columns: ID and Case Number with near-unique values per record, Block with 31,973 unique values, and coordinate fields with hundreds of thousands of unique combinations.

The strategic removal of these columns follows specific logical principles. The Block field, despite containing geographic information, represents an overly granular level that introduces noise rather than signal due to privacy masking that shifts actual locations within the same block. The IUCR code and Description columns are removed because they are directly linked to Primary Type, creating redundant information that could lead to multicollinearity issues. Beat information is excluded in favor of District-level data because beats represent the finest geographic granularity (275 unique values) while districts (23 unique values) provide sufficient spatial context without excessive fragmentation.

## Temporal Feature Engineering and Pattern Extraction

The Date column, containing 236,566 unique values, requires sophisticated feature engineering rather than categorical encoding to extract meaningful temporal patterns that influence arrest likelihood. Direct categorical encoding of such high-cardinality temporal data would create an unwieldy feature space that provides little predictive value while significantly increasing model complexity.

```python
# Extract temporal features
df['hour'] = df['date'].dt.hour  # 0-23
df['day_of_week'] = df['date'].dt.weekday  # 0=Monday to 6=Sunday
df['month'] = df['date'].dt.month  # 1-12
df['quarter'] = df['date'].dt.quarter  # 1-4

# Binary flags
df['is_night'] = ((df['hour'] >= 18) | (df['hour'] < 6)).astype(int)  # 1 if True, 0 else
df['is_weekend'] = (df['day_of_week'] >= 5).astype(int)
```

The temporal feature engineering strategy extracts cyclical and behavioral patterns that correlate with arrest probability. Hour of day captures daily crime patterns and police patrol schedules, with certain hours showing higher arrest rates due to increased police presence or different crime types. Day of week identifies weekly patterns, distinguishing between weekday and weekend crime characteristics that may influence police response and arrest likelihood. Monthly and quarterly features capture seasonal crime trends and resource allocation patterns that affect arrest outcomes.

The binary flags for night time (18:00-06:00) and weekend periods create interpretable features that align with known criminological patterns. Night-time incidents often involve different crime types and police response protocols compared to daytime incidents, while weekend crimes may have different characteristics regarding domestic incidents, public disturbances, and available police resources.

## Location Description Mapping and Categorical Reduction

The Location Description field presents a manageable cardinality challenge with 143 unique values, but still requires strategic grouping to improve model performance and interpretability. Rather than treating each specific location as a separate category, the approach involves mapping similar locations into broader, more meaningful groups that capture the essential environmental context affecting arrest probability.

```python
# countries and their regions
with open ('./location_description.json', 'r') as file:
    map_loc_desc = json.load(file)

df['location_group'] = df['location_description'].map(map_loc_desc).fillna("Unknown/Other")
df.drop(columns=['date', 'location_description'], inplace=True)
```

The location mapping strategy groups the 143 unique location descriptions into approximately 12-15 broader categories such as Residential, Commercial Retail, Food/Entertainment, Street/Public Open, Vehicle/Transport Private, Public Transit, Educational, Healthcare, Financial/Services, Industrial/Construction, Government/Institutional, Airport/Aviation, Religious/Cultural, Sports/Recreation, and Abandoned/Utility locations. This grouping reduces feature dimensionality while preserving the essential environmental context that influences police response patterns and arrest likelihood.

Each location group represents environments with similar characteristics regarding police accessibility, witness availability, crime types, and response protocols. For example, residential locations may have different arrest patterns compared to public transit locations due to factors such as surveillance availability, escape routes, and typical police response times. The mapping preserves these meaningful distinctions while eliminating noise from overly specific location descriptions.

## Data Quality Assessment and Missing Value Treatment

The dataset demonstrates high completeness with minimal missing values, but requires careful handling of the few gaps that exist. The Ward field shows 13 missing values out of 503,052 records, while Community Area has 39 missing values. These missing values likely represent incidents in areas with unclear jurisdictional boundaries or data entry errors during the reporting process.

```python
df.info()
# Shows:
# ward            503039 non-null  float64 (13 missing)
# community_area  503013 non-null  float64 (39 missing)

df = df.dropna()
```

The decision to drop rows with missing values rather than impute them reflects the minimal impact on the overall dataset size (less than 0.01% of records) and the importance of maintaining data integrity for geographic features. Imputation of geographic identifiers like Ward or Community Area could introduce systematic bias in spatial analysis, particularly given that these missing values may not be randomly distributed across the city.

## Target Variable Analysis and Class Imbalance Recognition

The binary target variable (Arrest) exhibits significant class imbalance, with arrests occurring in approximately 5-10% of reported incidents. This imbalance reflects the operational reality of urban policing, where resource constraints, case complexity, and investigative requirements result in arrests for only a subset of reported crimes. Understanding this imbalance is crucial for model development, as it affects both training strategies and evaluation metrics.

The class imbalance necessitates careful consideration of sampling strategies, evaluation metrics beyond simple accuracy, and potentially specialized algorithms designed to handle imbalanced datasets. The low arrest rate also provides context for the business value of the predictive model, as even modest improvements in identifying high-probability arrest cases could significantly impact police resource allocation and operational efficiency.

## Final Feature Set and Dimensionality Reduction

The feature engineering process transforms the original 22-column dataset into a focused set of predictive features that balance information content with model tractability. The final feature set includes Primary Type (31 categories), the binary Arrest target, Domestic indicator, District (23 categories), Ward and Community Area for geographic context, FBI Code (26 categories), and the engineered temporal features including hour, day of week, month, quarter, and binary night/weekend flags.

This reduction from high-cardinality raw features to a manageable set of engineered features addresses the curse of dimensionality while preserving the essential information needed for arrest prediction. The approach demonstrates the principle that effective feature engineering often involves strategic information loss—removing noise and redundancy while retaining signal—rather than attempting to preserve every available data point.

## Sample Data Management and Development Workflow

The creation of sample datasets serves multiple purposes in the machine learning development lifecycle. Beyond computational efficiency, these samples enable consistent testing environments, facilitate collaborative development where team members can work with identical subsets, and provide standardized benchmarks for comparing different modeling approaches. The sample files become reference datasets that ensure reproducible results across different development sessions and environments.

During the development phase, working with the complete dataset can be computationally expensive and time-consuming for iterative testing and model validation. The `extract_sample_data.py` script addresses this challenge by creating representative subsets of the test data that maintain the statistical properties of the full dataset while enabling rapid experimentation and validation workflows.

```python
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
```

The script implements a strategic sampling approach that creates two distinct, non-overlapping subsets from the test data. The first subset contains 100 rows saved as an uncompressed CSV file, providing a lightweight dataset for rapid prototyping and initial testing. The second subset contains 1,000 rows saved as a compressed CSV file, offering a more substantial sample for thorough validation while remaining computationally manageable.

The path detection mechanism ensures the script functions correctly regardless of the execution context, automatically determining whether it's being run from the project root directory or the scripts subdirectory. This flexibility prevents common path-related errors that occur when scripts are executed from different working directories, making the development workflow more robust and user-friendly.

```python
# Take first 100 rows for CSV
sample_100 = all_sample.head(100)

# Take next 1000 rows (completely different from first 100) for compressed CSV
sample_1000 = all_sample.iloc[100:1100]
```

The non-overlapping sampling strategy ensures that the two subsets represent different portions of the data, preventing data leakage between development and validation phases. This approach maintains the integrity of the testing process while providing datasets of appropriate sizes for different development needs. The smaller subset enables rapid iteration during feature engineering and model prototyping, while the larger subset provides sufficient data for more comprehensive validation and performance assessment.
