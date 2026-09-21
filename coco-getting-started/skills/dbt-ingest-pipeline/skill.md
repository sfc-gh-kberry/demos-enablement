# dbt-ingest-pipeline

## Description
Generate a complete dbt staging pipeline for a new raw data source. Given a raw table in Snowflake, this skill profiles the data, identifies transformation needs, and generates production-ready dbt artifacts.

## When to Use
Invoke this skill when:
- A new vendor/source table lands in the RAW schema
- You need to standardize a raw feed into the staging layer
- You want dbt models with schema tests and source freshness checks

## Workflow

### Step 1: Profile the Source
First, examine the raw table to understand its structure and data quality:
- Run DESCRIBE TABLE on the source
- Profile each column: data types, null rates, distinct values, sample data
- Identify transformation needs: date parsing, numeric cleaning, text normalization, deduplication

### Step 2: Define the Target Schema
The staging model should output these standardized columns (adapt based on source):
- `transaction_id` (VARCHAR) — unique identifier, prefixed with source name
- `transaction_date` (DATE) — parsed to ISO date
- `merchant_name` (VARCHAR) — Title Case, trimmed
- `amount` (NUMBER(12,2)) — in dollars, 2 decimal places
- `category` (VARCHAR) — mapped to standard categories: GROCERY, GAS, DINING, RETAIL, TRAVEL, ENTERTAINMENT
- `card_last_four` (VARCHAR(4))
- `status` (VARCHAR) — standardized to: APPROVED, DECLINED, PENDING
- `source_system` (VARCHAR) — name of the vendor/processor
- `loaded_at` (TIMESTAMP_NTZ) — current_timestamp at load time

### Step 3: Generate dbt Artifacts

Generate these files:

#### `models/staging/stg_{source_name}_transactions.sql`
```sql
with source as (
    select * from {{ source('{source_name}', '{raw_table_name}') }}
),

cleaned as (
    select
        -- Map each column with appropriate transformations
        -- Use TRY_TO_DATE for date parsing
        -- Use TRY_TO_NUMBER for numeric conversion  
        -- Use INITCAP(TRIM(...)) for name normalization
        -- Use CASE statements for category/status mapping
        current_timestamp() as loaded_at
    from source
)

select * from cleaned
```

#### `models/staging/schema.yml`
```yaml
version: 2

models:
  - name: stg_{source_name}_transactions
    description: "Staged and standardized transactions from {source_name}"
    columns:
      - name: transaction_id
        tests:
          - unique
          - not_null
      - name: transaction_date
        tests:
          - not_null
      - name: amount
        tests:
          - not_null
          - dbt_utils.accepted_range:
              min_value: 0
              max_value: 100000
      - name: status
        tests:
          - accepted_values:
              values: ['APPROVED', 'DECLINED', 'PENDING']
```

#### `models/staging/sources.yml`
```yaml
version: 2

sources:
  - name: {source_name}
    database: COCO_DE_LAB
    schema: RAW
    tables:
      - name: {raw_table_name}
        freshness:
          warn_after: {count: 24, period: hour}
          error_after: {count: 48, period: hour}
        loaded_at_field: _metadata_last_modified
```

### Step 4: Validate
After generating artifacts:
- Compile the model to verify SQL is valid
- Check that all source columns are mapped or explicitly excluded
- Verify test coverage on key columns

## Important Notes
- Always use TRY_* functions (TRY_TO_DATE, TRY_TO_NUMBER) to handle dirty data gracefully
- Add a `_excluded_columns` comment for any source columns intentionally not carried forward
- Category mapping should use a CASE statement with an 'OTHER' fallback
- If the source has no natural unique key, generate one using MD5 hash of key columns
