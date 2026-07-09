-- Explicit retention overrides short dataset defaults that would remove history.
{{ config(
    cluster_by=['property_id'],
    partition_by={'field': 'month', 'data_type': 'date', 'granularity': 'month'},
    partition_expiration_days=3650,
    hours_to_expiration=87600
) }}

with properties as (
    -- Convert lease and deletion rules into one inclusive final available date.
    select
        property_id,
        property_name,
        city,
        lease_start_date,
        least(
            lease_end_date,
            coalesce(date_sub(date(deleted_at), interval 1 day), lease_end_date)
        ) as last_available_date
    from {{ ref('stg_properties') }}
    where lease_start_date is not null
      and lease_end_date is not null
),

date_bounds as (
    -- Bound the generated spine to relevant availability instead of fixed dates.
    select
        min(lease_start_date) as min_date,
        max(last_available_date) as max_date
    from properties
    where last_available_date >= lease_start_date
),

date_spine as (
    -- One calendar row per day supports an auditable room-night grain.
    select calendar_date
    from date_bounds,
    unnest(generate_date_array(min_date, max_date)) as calendar_date
),

available_room_days as (
    -- Establish the availability denominator before applying tenancy occupancy.
    select
        dates.calendar_date,
        properties.property_id,
        properties.property_name,
        properties.city,
        rooms.room_id
    from properties
    inner join {{ ref('stg_rooms') }} as rooms
        on properties.property_id = rooms.property_id
    inner join date_spine as dates
        on dates.calendar_date between properties.lease_start_date
                                   and properties.last_available_date
       and (rooms.deleted_at is null or dates.calendar_date < date(rooms.deleted_at))
),

active_tenancies as (
    -- Invalid, cancelled, and zero-length stays cannot occupy a room-night.
    select distinct
        room_id,
        check_in_date,
        check_out_date
    from {{ ref('stg_tenancies') }}
    where status = 'active'
      and check_in_date is not null
      and check_out_date is not null
      and check_out_date > check_in_date
),

room_day_status as (
    -- COUNTIF collapses overlapping tenancies to one occupied room/date.
    select
        room_days.*,
        countif(tenancies.room_id is not null) > 0 as is_occupied
    from available_room_days as room_days
    left join active_tenancies as tenancies
        on room_days.room_id = tenancies.room_id
       and room_days.calendar_date >= tenancies.check_in_date
       and room_days.calendar_date < tenancies.check_out_date
    group by
        room_days.calendar_date,
        room_days.property_id,
        room_days.property_name,
        room_days.city,
        room_days.room_id
)

select
    -- Monthly sums preserve partial lease and deletion months correctly.
    date_trunc(calendar_date, month) as month,
    property_id,
    property_name,
    city,
    count(*) as available_room_nights,
    countif(is_occupied) as occupied_room_nights,
    countif(not is_occupied) as vacant_room_nights,
    safe_divide(countif(is_occupied), count(*)) as occupancy_rate
from room_day_status
group by month, property_id, property_name, city
