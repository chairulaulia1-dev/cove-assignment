-- Singular dbt tests fail when they return any violating records.
select *
from {{ ref('mart_monthly_property_occupancy') }}
where occupancy_rate < 0 or occupancy_rate > 1
