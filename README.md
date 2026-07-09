# Property Occupancy ELT Pipeline

An end-to-end ELT implementation that loads MongoDB JSONL exports into BigQuery, transforms them with dbt, calculates monthly room-night occupancy by property, and exposes a reporting-ready mart for Looker Studio.

## Submission links

| Deliverable | Link |
|---|---|
| GitHub repository | Add repository URL before submission |
| Google Data Studio report | [Property Occupancy Performance](https://datastudio.google.com/reporting/8db7c29d-3dc0-42fd-b627-3220ee2b3263) |
| BigQuery screenshots | [`docs/screenshots/`](docs/screenshots/) |

## Table of contents

- [Business problem](#business-problem)
- [Solution summary](#solution-summary)
- [Architecture](#architecture)
- [Repository structure](#repository-structure)
- [Source-data analysis](#source-data-analysis)
- [Metric definition](#metric-definition)
- [Design decisions](#design-decisions)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Running the pipeline](#running-the-pipeline)
- [Expected outputs](#expected-outputs)
- [Testing and validation](#testing-and-validation)
- [Security](#security)
- [Limitations and future improvements](#limitations-and-future-improvements)

## Business problem

The source application is a MongoDB-backed property-management platform for a co-living business that rents individual rooms. Operational data is exported as newline-delimited JSON for three entities:

- properties;
- rooms;
- tenancies.

The business needs to understand how effectively its available room inventory is used over time. The required output is a monthly occupancy rate for each property:

```text
monthly occupancy rate =
occupied room-nights / available room-nights
```

This is a flow-based metric across all calendar dates in a month, not a month-end inventory snapshot.

## Solution summary

The implementation separates responsibilities into clear layers:

1. A Python loader preserves the JSONL exports in BigQuery raw tables.
2. dbt staging views normalize identifiers, dates, timestamps, and statuses.
3. A dbt mart builds one row per available room and calendar date.
4. Active tenancy intervals mark those room-days as occupied.
5. The daily records are aggregated into monthly property metrics.
6. dbt tests and standalone validation queries verify entity integrity, completeness, and business invariants.
7. Looker Studio reads only the governed final mart.

The central modeling decision is to calculate occupancy at the `room_id + calendar_date` grain before aggregation. This makes the numerator and denominator auditable and prevents overlapping tenancy records from double-counting room capacity.

## Architecture

```text
MongoDB JSONL exports
        |
        v
Python ingestion
  - environment-based configuration
  - explicit raw schemas
  - deterministic reloads
        |
        v
BigQuery raw dataset
  - raw_properties
  - raw_rooms
  - raw_tenancies
        |
        v
dbt staging views
  - identifier normalization
  - safe date/timestamp parsing
  - status normalization
        |
        v
Daily room availability and occupancy
  - generated date spine
  - lease/deletion boundaries
  - active tenancy interval matching
  - overlap deduplication
        |
        v
Monthly property occupancy mart
        |
        v
Looker Studio report
```

### Technology choices

| Component | Technology | Reason |
|---|---|---|
| Warehouse | BigQuery | Serverless analytical execution and native date-array support |
| Ingestion | Python and `google-cloud-bigquery` | Explicit, reviewable, and portable loading logic |
| Transformation | dbt BigQuery | SQL lineage, modular models, tests, and documentation |
| Visualization | Looker Studio | Native BigQuery integration and shareable reporting |

## Repository structure

```text
property-occupancy-elt/
├── README.md
├── .env.example
├── .gitignore
├── Makefile
├── requirements.txt
├── data/
│   └── raw/
│       ├── properties.jsonl
│       ├── rooms.jsonl
│       └── tenancies.jsonl
├── scripts/
│   └── load_raw_to_bigquery.py
├── sql/
│   ├── create_raw_tables.sql
│   └── validation_queries.sql
├── dbt_project.yml
├── profiles.yml.example
├── models/
│   ├── sources.yml
│   ├── staging/
│   │   ├── stg_properties.sql
│   │   ├── stg_rooms.sql
│   │   ├── stg_tenancies.sql
│   │   └── schema.yml
│   └── marts/
│       ├── mart_monthly_property_occupancy.sql
│       └── schema.yml
├── tests/
│   ├── assert_mart_covers_availability_period.sql
│   ├── assert_occupancy_rate_in_range.sql
│   └── assert_occupied_not_greater_than_available.sql
├── analyses/
│   └── occupancy_sanity_checks.sql
└── docs/
    ├── assumptions.md
    ├── data_quality_notes.md
    ├── interview_guide_bilingual.md
    ├── looker_studio_instructions.md
    └── screenshots/
```

Additional documentation:

- [Assumptions](docs/assumptions.md)
- [Data-quality notes](docs/data_quality_notes.md)

## Source-data analysis

The supplied export contains:

| Entity | Source rows | Purpose |
|---|---:|---|
| Properties | 3 | Property metadata and lease windows |
| Rooms | 6 | Physical inventory assigned to properties |
| Tenancies | 16 | Occupancy intervals assigned to rooms |

The source demonstrates several operational data-quality patterns:

- `deletedAt` can be absent, explicitly `null`, or space-formatted.
- `updatedAt` uses timestamps.
- One cancelled tenancy must be excluded from occupancy.
- Active tenancy intervals overlap for room `r_202`.
- Soft-deleted entities can still be referenced by tenancy records.
- No room creation or activation date is supplied.

These observations inform both the transformation logic and documented assumptions.

## Metric definition

### Grain

Before monthly aggregation, one logical record represents:

```text
one room + one calendar date
```

### Available room-night

A room contributes one available room-night when all of the following are true:

- the date is on or after the property's `lease_start_date`;
- the date is on or before the property's `lease_end_date`;
- the property has not been soft-deleted on or before that date;
- the room has not been soft-deleted on or before that date.

Property and room deletion dates are therefore exclusive availability boundaries.

### Occupied room-night

An available room-night is occupied when at least one tenancy:

- belongs to the room;
- has normalized status `active`;
- has `check_in_date <= calendar_date`;
- has `check_out_date > calendar_date`.

Checkout is exclusive. A tenancy checking out on March 15 occupies nights through March 14.

### Overlapping tenancies

Multiple active tenancies matching the same room and date produce only one occupied room-night. The model converts matches to a boolean occupancy status before monthly aggregation.

### Final columns

| Column | Description |
|---|---|
| `month` | Calendar month represented by its first date |
| `property_id` | Stable property identifier |
| `property_name` | Reporting-friendly property name |
| `city` | Property city |
| `available_room_nights` | Valid room-days in the month |
| `occupied_room_nights` | Available room-days covered by active tenancy |
| `vacant_room_nights` | Available minus occupied room-days |
| `occupancy_rate` | Occupied divided by available room-nights |

## Design decisions

### Preserve raw data as strings

The raw layer uses explicit schemas but retains source values as strings. This keeps ingestion resilient to inconsistent timestamp formats and preserves source fidelity. Typed conversion happens in dbt staging, where malformed values can be inspected and tested.

### Use safe parsing in staging

`SAFE_CAST` and `SAFE.PARSE_TIMESTAMP` convert invalid values to `NULL` rather than failing the entire pipeline. Required identifiers and dates are then enforced through dbt tests.

### Establish availability before occupancy

The model first creates valid room inventory dates and only then joins tenancy intervals. A tenancy outside the property lease or after soft deletion cannot create artificial availability or occupancy.

### Generate a dynamic date spine

`GENERATE_DATE_ARRAY` derives the daily calendar from relevant source boundaries. No reporting dates are hard-coded.

### Use full replacement for assessment ingestion

The Python loader uses `WRITE_TRUNCATE`. This produces deterministic reruns for a small static assessment dataset. A production pipeline should use immutable load batches and incremental processing.

### Materialize staging as views and the mart as a table

Staging transformations are lightweight and reusable, so views are sufficient. The mart expands intervals to daily room records and is queried by BI, so a persisted, partitioned table provides predictable performance.

### Override dataset retention

The target BigQuery environment had a 60-day default partition expiration. Without an override, historical monthly partitions were deleted immediately. The mart explicitly sets longer table and partition retention, and a dbt completeness test verifies the expected date range.

## Assumptions

- Checkout dates are exclusive.
- Lease start and end dates are inclusive.
- Property and room deletion dates are exclusive.
- Cancelled tenancies do not contribute occupancy.
- Occupancy is based on room-nights, not a point-in-time snapshot.
- A room is assumed available from the property's lease start because no room creation date is supplied.
- `updatedAt` is not treated as a creation timestamp.
- Overlapping active tenancies count once per room-date.
- Tenancies outside valid availability do not create room capacity.
- Months can represent partial availability when leases or deletions occur mid-month.

See [docs/assumptions.md](docs/assumptions.md) for the standalone assumptions record.

## Prerequisites

- Python 3.10 or later; Python 3.11+ is recommended.
- Git.
- A GCP project with billing configured.
- BigQuery API enabled.
- A service account or authenticated user with:
  - BigQuery Job User;
  - BigQuery Data Editor on the target datasets.
- A service-account JSON key for the documented local setup, or an equivalent supported authentication method.
- Google Cloud CLI with the `bq` command for manual validation.

The tested dbt environment used dbt Core 1.11 and dbt-bigquery 1.11.

## Configuration
I use Windows as my local machine environment. Since you might be use MacOS or Linux, I also put the steps both Windows and MacOS or Linux to set up the configuration in your local computer, hopefully it might be helpful.

### 1. Clone and enter the repository

```bash
git clone <repository-url>
cd property-occupancy-elt
```

### 2. Create a Python virtual environment

Windows PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

macOS or Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

### 3. Create local configuration

Windows PowerShell:

```powershell
Copy-Item .env.example .env
Copy-Item profiles.yml.example profiles.yml
```

macOS or Linux:

```bash
cp .env.example .env
cp profiles.yml.example profiles.yml
```

Populate `.env` with local values:

```dotenv
GCP_PROJECT_ID=test-project-379308
BIGQUERY_LOCATION=US
BIGQUERY_DATASET_RAW=raw_property_occupancy
BIGQUERY_DATASET_ANALYTICS=analytics_property_occupancy
GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\service-account.json
```

Do not modify `.env.example` with credentials or a personal key path.

### 4. Export environment variables for dbt

The Python loader reads `.env` automatically. dbt resolves `env_var()` from the shell environment and does not automatically load `.env`.

Windows PowerShell:

```powershell
$env:GCP_PROJECT_ID="test-project-379308"
$env:BIGQUERY_LOCATION="US"
$env:BIGQUERY_DATASET_RAW="raw_property_occupancy"
$env:BIGQUERY_DATASET_ANALYTICS="analytics_property_occupancy"
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\service-account.json"
```

macOS or Linux:

```bash
export GCP_PROJECT_ID="test-project-379308"
export BIGQUERY_LOCATION="US"
export BIGQUERY_DATASET_RAW="raw_property_occupancy"
export BIGQUERY_DATASET_ANALYTICS="analytics_property_occupancy"
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
```

### 5. Confirm dbt connectivity

```bash
dbt debug --profiles-dir .
```

## Running the pipeline

### Step 1: Load raw JSONL files

```bash
python scripts/load_raw_to_bigquery.py
```

### Step 2: Build dbt models

For a normal build:

```bash
dbt run --profiles-dir .
```

For a clean assessment rebuild:

```bash
dbt run --profiles-dir . --full-refresh
```

dbt creates:

- staging views in `analytics_property_occupancy_staging`;
- the final table in `analytics_property_occupancy_marts`.

The suffixes result from dbt's default custom-schema behavior:

```text
target schema + custom model schema
```

### Step 3: Execute tests

```bash
dbt test --profiles-dir .
```

Alternatively, build and test in dependency order:

```bash
dbt build --profiles-dir . --full-refresh
```

### Step 4: Generate dbt documentation

```bash
dbt docs generate --profiles-dir .
dbt docs serve --profiles-dir .
```

## Expected outputs

### BigQuery relations

```text
test-project-379308.raw_property_occupancy.raw_properties
test-project-379308.raw_property_occupancy.raw_rooms
test-project-379308.raw_property_occupancy.raw_tenancies

test-project-379308.analytics_property_occupancy_staging.stg_properties
test-project-379308.analytics_property_occupancy_staging.stg_rooms
test-project-379308.analytics_property_occupancy_staging.stg_tenancies

test-project-379308.analytics_property_occupancy_marts.mart_monthly_property_occupancy
```

Confirm the final result:

```powershell
dbt show `
  --profiles-dir . `
  --inline "select count(*) as row_count from {{ ref('mart_monthly_property_occupancy') }}"
```

Preview monthly results:

```powershell
dbt show `
  --profiles-dir . `
  --inline "select * from {{ ref('mart_monthly_property_occupancy') }} order by month, property_id" `
  --limit 100
```

## Testing and validation

### dbt tests

The project checks:

- staging identifiers are not null and unique;
- rooms reference valid properties;
- tenancies reference valid rooms;
- tenancy statuses belong to the accepted domain;
- required mart fields are not null;
- occupancy rates remain between zero and one;
- occupied room-nights never exceed available room-nights;
- the materialized mart covers the expected availability period.

The last test is particularly important because valid rows alone do not prove that historical rows are complete.

### Manual validation queries

[`sql/validation_queries.sql`](sql/validation_queries.sql) contains queries for:

- raw and staging row-count reconciliation;
- populated property and room deletion timestamps;
- cancelled tenancies;
- potentially overlapping active tenancies;
- monthly mart previews;
- occupied room-nights exceeding availability;
- occupancy rates outside the zero-to-one range.

Run the file in the BigQuery console, or with `bq`:

```bash
bq query \
  --use_legacy_sql=false \
  --location=US \
  < sql/validation_queries.sql
```

The invariant-violation queries should return zero rows. The overlap query is expected to identify the supplied overlap for room `r_202`; this is a source-quality observation, not a mart failure.

### Accounting identity

Every mart record should satisfy:

```text
available_room_nights =
occupied_room_nights + vacant_room_nights
```

The dbt analysis [`analyses/occupancy_sanity_checks.sql`](analyses/occupancy_sanity_checks.sql) returns only violations. A healthy result is empty

## Security

- No private credential is hard-coded.
- `.env`, `profiles.yml`, `keys/`, and service-account JSON files are ignored.
- Runtime settings are supplied through environment variables.
- `.env.example` and `profiles.yml.example` contain placeholders only.
- Screenshots should be reviewed before commit to ensure they do not expose project members, credentials, or unrelated data.

## Limitations and future improvements

This implementation prioritizes clarity and auditability for the supplied assessment. Production improvements would include:

1. Immutable raw ingestion with batch IDs, source filenames, checksums, and ingestion timestamps.
2. Incremental processing and targeted historical backfills.
3. Managed orchestration using Airflow, Cloud Composer, or dbt Cloud.
4. Source freshness checks and volume-anomaly detection.
5. Rejected-record quarantine for malformed source data.
6. CI that runs SQL linting, `dbt parse`, and `dbt build`.
7. Infrastructure as code for datasets, IAM, retention, and scheduled jobs.
8. Workload Identity or service-account impersonation.
9. Monitoring and alerting for load, test, freshness, and metric anomalies.
10. Room activation history instead of assuming availability from property lease start.
11. Slowly changing dimensions for historical property and room attributes.
12. A governed calendar dimension and semantic metric layer.
13. Interval-based or partition-incremental occupancy processing if daily expansion becomes costly.

## Closing note

The project is designed so that the occupancy calculation is not a black box. Raw source records remain available, staging transformations are explicit, the daily room-night grain is inspectable, business boundaries are documented, and the final metric is protected by both integrity and completeness tests.
