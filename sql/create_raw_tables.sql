-- Manual fallback DDL. Replace the project and dataset identifiers if needed.
CREATE SCHEMA IF NOT EXISTS `test-project-379308.raw_property_occupancy`
OPTIONS (location = 'US');

CREATE OR REPLACE TABLE `test-project-379308.raw_property_occupancy.raw_properties` (
  _id STRING NOT NULL,
  name STRING,
  city STRING,
  lease_start_date STRING,
  lease_end_date STRING,
  updatedAt STRING,
  deletedAt STRING
);

CREATE OR REPLACE TABLE `test-project-379308.raw_property_occupancy.raw_rooms` (
  _id STRING NOT NULL,
  propertyId STRING,
  room_number STRING,
  type STRING,
  updatedAt STRING,
  deletedAt STRING
);

CREATE OR REPLACE TABLE `test-project-379308.raw_property_occupancy.raw_tenancies` (
  _id STRING NOT NULL,
  roomId STRING,
  tenant_id STRING,
  checkInDate STRING,
  checkOutDate STRING,
  status STRING,
  updatedAt STRING
);

-- Example CLI loads after running the DDL:
-- bq load --source_format=NEWLINE_DELIMITED_JSON --replace
--   test-project-379308:raw_property_occupancy.raw_properties
--   data/raw/properties.jsonl
-- Repeat for rooms and tenancies. The Python loader is preferred because it
-- supplies explicit schemas and consistent error handling.

