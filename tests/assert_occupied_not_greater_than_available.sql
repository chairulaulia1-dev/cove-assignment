-- Occupancy must remain a subset of established room availability.
select *
from {{ ref('mart_monthly_property_occupancy') }}
where occupied_room_nights > available_room_nights
