# Assumptions

- `checkOutDate` is exclusive; the checkout calendar date is not occupied.
- Only tenancies with normalized status `active` contribute occupancy. Cancelled tenancies are excluded.
- Occupancy is measured using room-nights, not a month-end snapshot.
- A property's lease start and end dates are inclusive and define its valid availability window.
- A property or room is unavailable on and after its soft-deletion date.
- Rooms have no creation date in the export. A room is therefore assumed available from its property's lease start until the earlier applicable lease or deletion boundary.
- Multiple overlapping active tenancies for the same room and date count as one occupied room-night.
- Tenancy dates outside room/property availability do not create availability and are ignored for the metric.
- Invalid or missing dates are converted to `NULL` in staging. Records lacking required availability dates do not enter the mart and should be investigated through tests and validation.
- Monthly rows include partial months when a lease begins, ends, or an entity is deleted mid-month.

