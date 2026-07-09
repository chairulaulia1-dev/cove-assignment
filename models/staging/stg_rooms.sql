-- Normalize MongoDB identifiers and retain soft-deletion metadata.
with source as (
    select * from {{ source('raw_property_occupancy', 'raw_rooms') }}
)

select
    cast(_id as string) as room_id,
    cast(propertyId as string) as property_id,
    cast(room_number as string) as room_number,
    cast(type as string) as room_type,
    -- The fallback handles exports formatted as YYYY-MM-DD HH:MM:SS.
    coalesce(
        safe_cast(updatedAt as timestamp),
        safe.parse_timestamp('%F %T', updatedAt)
    ) as updated_at,
    coalesce(
        safe_cast(deletedAt as timestamp),
        safe.parse_timestamp('%F %T', deletedAt)
    ) as deleted_at
from source
