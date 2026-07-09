-- Preserve one row per property while normalizing names and data types.
with source as (
    select * from {{ source('raw_property_occupancy', 'raw_properties') }}
)

select
    cast(_id as string) as property_id,
    cast(name as string) as property_name,
    cast(city as string) as city,
    safe_cast(lease_start_date as date) as lease_start_date,
    safe_cast(lease_end_date as date) as lease_end_date,
    -- SAFE parsing tolerates both ISO 8601 and space-separated timestamps.
    coalesce(
        safe_cast(updatedAt as timestamp),
        safe.parse_timestamp('%F %T', updatedAt)
    ) as updated_at,
    coalesce(
        safe_cast(deletedAt as timestamp),
        safe.parse_timestamp('%F %T', deletedAt)
    ) as deleted_at
from source
