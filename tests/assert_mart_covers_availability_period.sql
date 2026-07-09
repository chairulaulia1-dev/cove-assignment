-- Detect accidental history loss, including BigQuery partition expiration.
with expected_bounds as (
    -- Apply the same effective property boundary used by the mart.
    select
        date_trunc(min(lease_start_date), month) as expected_min_month,
        date_trunc(
            max(
                least(
                    lease_end_date,
                    coalesce(
                        date_sub(date(deleted_at), interval 1 day),
                        lease_end_date
                    )
                )
            ),
            month
        ) as expected_max_month
    from {{ ref('stg_properties') }}
    where lease_start_date is not null
      and lease_end_date is not null
),

actual_bounds as (
    -- Boundary comparison cheaply catches truncated materializations.
    select
        min(month) as actual_min_month,
        max(month) as actual_max_month
    from {{ ref('mart_monthly_property_occupancy') }}
)

select *
from expected_bounds
cross join actual_bounds
where actual_min_month != expected_min_month
   or actual_max_month != expected_max_month
