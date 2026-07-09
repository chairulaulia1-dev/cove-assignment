"""Load the assessment's newline-delimited JSON exports into BigQuery."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from google.api_core.exceptions import GoogleAPIError
from google.cloud import bigquery

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data" / "raw"

# Load source values as strings to preserve the export faithfully. Tolerant type
# parsing belongs in dbt, where rejected values are easier to inspect.
TABLE_SCHEMAS = {
    "raw_properties": [
        bigquery.SchemaField("_id", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("name", "STRING"),
        bigquery.SchemaField("city", "STRING"),
        bigquery.SchemaField("lease_start_date", "STRING"),
        bigquery.SchemaField("lease_end_date", "STRING"),
        bigquery.SchemaField("updatedAt", "STRING"),
        bigquery.SchemaField("deletedAt", "STRING"),
    ],
    "raw_rooms": [
        bigquery.SchemaField("_id", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("propertyId", "STRING"),
        bigquery.SchemaField("room_number", "STRING"),
        bigquery.SchemaField("type", "STRING"),
        bigquery.SchemaField("updatedAt", "STRING"),
        bigquery.SchemaField("deletedAt", "STRING"),
    ],
    "raw_tenancies": [
        bigquery.SchemaField("_id", "STRING", mode="REQUIRED"),
        bigquery.SchemaField("roomId", "STRING"),
        bigquery.SchemaField("tenant_id", "STRING"),
        bigquery.SchemaField("checkInDate", "STRING"),
        bigquery.SchemaField("checkOutDate", "STRING"),
        bigquery.SchemaField("status", "STRING"),
        bigquery.SchemaField("updatedAt", "STRING"),
    ],
}

TABLE_FILES = {
    "raw_properties": DATA_DIR / "properties.jsonl",
    "raw_rooms": DATA_DIR / "rooms.jsonl",
    "raw_tenancies": DATA_DIR / "tenancies.jsonl",
}


def required_env(name: str) -> str:
    """Return a required setting or raise an actionable configuration error."""

    value = os.getenv(name)
    if not value:
        raise ValueError(
            f"Missing required environment variable {name}. "
            "Copy .env.example to .env and set all values."
        )
    return value


def main() -> int:
    """Create the raw dataset and idempotently replace all source tables."""

    load_dotenv(ROOT / ".env")
    try:
        project = required_env("GCP_PROJECT_ID")
        location = required_env("BIGQUERY_LOCATION")
        raw_dataset = required_env("BIGQUERY_DATASET_RAW")
        required_env("BIGQUERY_DATASET_ANALYTICS")
        credentials_path = Path(required_env("GOOGLE_APPLICATION_CREDENTIALS"))
        if not credentials_path.is_file():
            raise FileNotFoundError(
                f"GOOGLE_APPLICATION_CREDENTIALS does not point to a file: "
                f"{credentials_path}"
            )

        missing_files = [str(path) for path in TABLE_FILES.values() if not path.is_file()]
        if missing_files:
            raise FileNotFoundError(f"Missing source file(s): {', '.join(missing_files)}")

        # The client honors the GOOGLE_APPLICATION_CREDENTIALS environment value.
        client = bigquery.Client(project=project, location=location)
        dataset_id = f"{project}.{raw_dataset}"
        dataset = bigquery.Dataset(dataset_id)
        dataset.location = location
        client.create_dataset(dataset, exists_ok=True)
        print(f"Raw dataset ready: {dataset_id} ({location})")

        for table_name, source_path in TABLE_FILES.items():
            table_id = f"{dataset_id}.{table_name}"
            # Full replacement makes assessment reruns deterministic. Production
            # ingestion would normally use immutable batches or incremental loads.
            config = bigquery.LoadJobConfig(
                source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
                schema=TABLE_SCHEMAS[table_name],
                write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
                ignore_unknown_values=False,
            )
            with source_path.open("rb") as source:
                job = client.load_table_from_file(
                    source, table_id, job_config=config, location=location
                )
                job.result()
            table = client.get_table(table_id)
            print(f"Loaded {table.num_rows} rows: {source_path.name} -> {table_id}")
        return 0
    except (ValueError, FileNotFoundError) as exc:
        print(f"Configuration error: {exc}", file=sys.stderr)
    except GoogleAPIError as exc:
        print(
            "BigQuery operation failed. Check credentials, IAM permissions, project "
            f"ID, dataset location, and API enablement. Details: {exc}",
            file=sys.stderr,
        )
    except Exception as exc:  # Surface unexpected failures with actionable context.
        print(f"Unexpected ingestion failure: {type(exc).__name__}: {exc}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
