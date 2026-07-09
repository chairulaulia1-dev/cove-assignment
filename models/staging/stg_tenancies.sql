-- Normalize tenancy dates and statuses without applying occupancy rules yet.
with source as (
    select * from {{ source('raw_property_occupancy', 'raw_tenancies') }}
)

select
    cast(_id as string) as tenancy_id,
    cast(roomId as string) as room_id,
    cast(tenant_id as string) as tenant_id,
    safe_cast(checkInDate as date) as check_in_date,
    safe_cast(checkOutDate as date) as check_out_date,
    -- Case and surrounding whitespace should not change business semantics.
    lower(trim(cast(status as string))) as status,
    coalesce(
        safe_cast(updatedAt as timestamp),
        safe.parse_timestamp('%F %T', updatedAt)
    ) as updated_at
from source
