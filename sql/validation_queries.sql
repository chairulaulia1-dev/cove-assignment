-- Run each section in the BigQuery console, or run the whole script with `make validate`.

-- Raw and staging row counts.
SELECT 'raw_properties' AS relation_name, COUNT(*) AS row_count
FROM `test-project-379308.raw_property_occupancy.raw_properties`
UNION ALL
SELECT 'raw_rooms', COUNT(*)
FROM `test-project-379308.raw_property_occupancy.raw_rooms`
UNION ALL
SELECT 'raw_tenancies', COUNT(*)
FROM `test-project-379308.raw_property_occupancy.raw_tenancies`
UNION ALL
SELECT 'stg_properties', COUNT(*)
FROM `test-project-379308.analytics_property_occupancy_staging.stg_properties`
UNION ALL
SELECT 'stg_rooms', COUNT(*)
FROM `test-project-379308.analytics_property_occupancy_staging.stg_rooms`
UNION ALL
SELECT 'stg_tenancies', COUNT(*)
FROM `test-project-379308.analytics_property_occupancy_staging.stg_tenancies`;

-- Soft-deleted properties and rooms.
SELECT 'property' AS entity_type, property_id AS entity_id, deleted_at
FROM `test-project-379308.analytics_property_occupancy_staging.stg_properties`
WHERE deleted_at IS NOT NULL
UNION ALL
SELECT 'room', room_id, deleted_at
FROM `test-project-379308.analytics_property_occupancy_staging.stg_rooms`
WHERE deleted_at IS NOT NULL;

-- Cancelled tenancies excluded from occupancy.
SELECT *
FROM `test-project-379308.analytics_property_occupancy_staging.stg_tenancies`
WHERE status = 'cancelled'
ORDER BY check_in_date;

-- Active tenancy pairs with overlapping date ranges for the same room.
SELECT
  a.room_id,
  a.tenancy_id AS tenancy_id_a,
  b.tenancy_id AS tenancy_id_b,
  GREATEST(a.check_in_date, b.check_in_date) AS overlap_start,
  LEAST(a.check_out_date, b.check_out_date) AS overlap_end_exclusive
FROM `test-project-379308.analytics_property_occupancy_staging.stg_tenancies` a
JOIN `test-project-379308.analytics_property_occupancy_staging.stg_tenancies` b
  ON a.room_id = b.room_id
 AND a.tenancy_id < b.tenancy_id
 AND a.status = 'active'
 AND b.status = 'active'
 AND a.check_in_date < b.check_out_date
 AND b.check_in_date < a.check_out_date
ORDER BY a.room_id, overlap_start;

-- Monthly output preview.
SELECT *
FROM `test-project-379308.analytics_property_occupancy_marts.mart_monthly_property_occupancy`
ORDER BY month, property_name;

-- Invariant violations: both queries should return zero rows.
SELECT *
FROM `test-project-379308.analytics_property_occupancy_marts.mart_monthly_property_occupancy`
WHERE occupied_room_nights > available_room_nights;

SELECT *
FROM `test-project-379308.analytics_property_occupancy_marts.mart_monthly_property_occupancy`
WHERE occupancy_rate NOT BETWEEN 0 AND 1;

