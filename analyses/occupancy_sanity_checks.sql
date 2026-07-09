-- Return only broken accounting identities or invalid rate bounds.
-- A healthy result is an empty result set.
select
    month,
    property_id,
    property_name,
    available_room_nights,
    occupied_room_nights,
    vacant_room_nights,
    occupancy_rate,
    available_room_nights - occupied_room_nights - vacant_room_nights as balance
from {{ ref('mart_monthly_property_occupancy') }}
where available_room_nights != occupied_room_nights + vacant_room_nights
   or occupancy_rate not between 0 and 1
order by month, property_id
