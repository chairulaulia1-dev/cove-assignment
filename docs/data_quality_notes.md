# Data quality notes

The supplied MongoDB JSONL export is small, but it demonstrates patterns that matter at production scale:

- Optional fields and schema drift are expected. `deletedAt` is absent in some records and explicitly `null` in others.
- Timestamp formats differ: `updatedAt` uses ISO 8601 while populated `deletedAt` values use a space-separated format. Staging uses safe parsing to avoid aborting a run.
- Soft-deleted properties and rooms can still be referenced by tenancies. Availability boundaries take precedence over tenancy dates.
- The sample includes a cancelled tenancy, which is retained in staging but excluded from occupancy.
- Active tenancy ranges overlap for room `r_202`. The mart aggregates at one row per room/date before monthly aggregation, preventing double counting.
- The export contains no room creation timestamp. Availability from the property lease start is an explicit assumption.

Recommended production controls include freshness checks, source schema monitoring, referential-integrity alerts, rejected-record reporting, and reconciliation against operational totals.

