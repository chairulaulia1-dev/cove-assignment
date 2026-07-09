# Commands can be overridden for environments using non-default executables.
PYTHON ?= python
DBT ?= dbt
DBT_ARGS = --profiles-dir .

.PHONY: install load-raw dbt-debug dbt-run dbt-test dbt-docs validate

install:
	$(PYTHON) -m pip install -r requirements.txt

# Deterministically replace raw tables from version-controlled snapshots.
load-raw:
	$(PYTHON) scripts/load_raw_to_bigquery.py

dbt-debug:
	$(DBT) debug $(DBT_ARGS)

dbt-run:
	$(DBT) run $(DBT_ARGS)

dbt-test:
	$(DBT) test $(DBT_ARGS)

dbt-docs:
	$(DBT) docs generate $(DBT_ARGS)

# Execute reviewer-facing BigQuery reconciliation queries.
validate:
	bq query --use_legacy_sql=false --location=$${BIGQUERY_LOCATION} < sql/validation_queries.sql
