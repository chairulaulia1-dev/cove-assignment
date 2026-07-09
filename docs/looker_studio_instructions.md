# Looker Studio dashboard guide

This document explains how to build a reviewer-friendly Looker Studio dashboard on top of the final dbt mart:

```text
test-project-379308.analytics_property_occupancy_marts.mart_monthly_property_occupancy
```

The goal is not only to display the required occupancy chart, but also to make the metric easy to understand, validate, and discuss during a technical interview.

## Dashboard objective

The dashboard should answer three business questions:

1. How does monthly occupancy rate change over time?
2. Which properties perform better or worse?
3. Are the occupancy numbers supported by available, occupied, and vacant room-night counts?

The recommended design uses the final mart directly. Avoid connecting Looker Studio to raw or staging tables, because the final mart already contains the governed business metric.

## Recommended dashboard layout

Use one main report page with the following sections:

```text
Header
  - Dashboard title
  - Short metric definition
  - Date/property/city controls

KPI row
  - Average occupancy rate
  - Total available room-nights
  - Total occupied room-nights
  - Total vacant room-nights

Main analysis
  - Occupancy rate trend by property
  - Occupancy composition by month

Property comparison
  - Property performance table
  - Optional city/property filter controls

Data-quality / interpretation note
  - Checkout is exclusive
  - Cancelled tenancies are excluded
  - Overlapping active tenancies count once per room-date
```

## Recommended title and header

Recommended dashboard title:

```text
Monthly Property Occupancy Dashboard
```

This title is clear, professional, and directly aligned with the assessment requirement. It tells the reviewer the metric, the time grain, and the business entity being analyzed.

Alternative titles:

| Title | When to use |
|---|---|
| `Monthly Property Occupancy Dashboard` | Best default for the assessment submission |
| `Property Occupancy Performance - Monthly Room-Night View` | Stronger for interview storytelling because it highlights the room-night methodology |
| `Co-Living Property Occupancy Analysis` | Good if you want a more business-facing title |
| `Room-Night Occupancy by Property` | Good if you want to emphasize the metric logic |

Recommended final choice:

```text
Property Occupancy Performance - Monthly Room-Night View
```

This is slightly more insightful than a generic dashboard title because it signals that the analysis is based on room-nights, not a simple room snapshot.

### Header content

The dashboard header should help the reviewer understand the report within a few seconds. Suggested header layout:

```text
Property Occupancy Performance - Monthly Room-Night View
Room-night based occupancy by property, built from BigQuery and dbt.

Metric: occupied room-nights / available room-nights
Source: analytics_property_occupancy_marts.mart_monthly_property_occupancy
Filters: Month | City | Property
```

Recommended header elements:

| Header element | Example text | Purpose |
|---|---|---|
| Main title | `Property Occupancy Performance - Monthly Room-Night View` | Explains the dashboard topic clearly |
| Subtitle | `Room-night based occupancy by property, built from BigQuery and dbt.` | Shows the metric grain and technical stack |
| Metric definition | `Occupancy = occupied room-nights / available room-nights` | Prevents ambiguity about the calculation |
| Data source note | `Source: BigQuery mart_monthly_property_occupancy` | Makes lineage clear to the reviewer |
| Scope note | `Cancelled tenancies excluded; checkout date treated as exclusive.` | Highlights important business rules |
| Filter row | Month, City, Property controls | Encourages interactive exploration |

Recommended visual placement:

1. Place the title and subtitle at the top-left.
2. Place the date range, city, and property controls at the top-right or directly below the title.
3. Put the metric definition in a small text box under the subtitle.
4. Keep the header compact so the KPI cards remain visible without scrolling.

Suggested header copy:

```text
Property Occupancy Performance - Monthly Room-Night View

This dashboard tracks monthly occupancy using room-nights, where occupancy equals occupied room-nights divided by available room-nights. Availability respects property lease periods and soft-deletion dates. Cancelled tenancies are excluded, and checkout dates are treated as exclusive.
```

Shorter version if space is limited:

```text
Monthly room-night occupancy by property.
Occupancy = occupied room-nights / available room-nights.
Cancelled tenancies excluded; checkout date is exclusive.
```

## Step 1: Connect Looker Studio to BigQuery

1. Open Looker Studio.
2. Create a new report.
3. Choose **Add data**.
4. Select the **BigQuery** connector.
5. Select:
   - Project: `test-project-379308`
   - Dataset: `analytics_property_occupancy_marts`
   - Table: `mart_monthly_property_occupancy`
6. Add the table to the report.

After the data source is added, verify field types:

| Field | Expected type | Notes |
|---|---|---|
| `month` | Date | Use as the main time dimension |
| `property_id` | Text | Stable property key |
| `property_name` | Text | Human-readable property name |
| `city` | Text | Useful filter dimension |
| `available_room_nights` | Number | Sum aggregation |
| `occupied_room_nights` | Number | Sum aggregation |
| `vacant_room_nights` | Number | Sum aggregation |
| `occupancy_rate` | Number / Percent | Use carefully; see calculated field below |

## Step 2: Add calculated fields

For the cleanest dashboard behavior, create a report-level calculated field for weighted occupancy rate:

```text
Weighted Occupancy Rate =
SUM(occupied_room_nights) / SUM(available_room_nights)
```

Format this field as **Percent**.

Why this matters:

- The mart already calculates `occupancy_rate` per property-month.
- In charts that aggregate across several properties or months, averaging `occupancy_rate` can be misleading.
- The weighted field recalculates occupancy from the underlying numerator and denominator.

Use this rule:

| Use case | Recommended metric |
|---|---|
| Property-month table | `occupancy_rate` |
| KPI cards across selected filters | `Weighted Occupancy Rate` |
| Trend across multiple properties | `Weighted Occupancy Rate` or property breakdown |
| Total portfolio view | `Weighted Occupancy Rate` |

Optional calculated fields:

```text
Vacancy Rate =
SUM(vacant_room_nights) / SUM(available_room_nights)
```

```text
Occupancy Label =
CASE
  WHEN SUM(occupied_room_nights) / SUM(available_room_nights) >= 0.90 THEN "High occupancy"
  WHEN SUM(occupied_room_nights) / SUM(available_room_nights) >= 0.70 THEN "Healthy occupancy"
  WHEN SUM(occupied_room_nights) / SUM(available_room_nights) >= 0.40 THEN "Moderate occupancy"
  ELSE "Low occupancy"
END
```

## Step 3: Add filter controls

Add controls at the top of the dashboard:

| Control | Field | Purpose |
|---|---|---|
| Date range control | `month` | Allows reviewers to focus on specific periods |
| Drop-down list | `city` | Compares markets or filters one city |
| Drop-down list | `property_name` | Focuses on one property |

Recommended default:

- Include all months.
- Include all cities and properties.

This helps the reviewer see the full result first, then drill down.

## Step 4: Add KPI scorecards

Create four scorecards:

| KPI | Metric | Format |
|---|---|---|
| Average Occupancy | `Weighted Occupancy Rate` | Percent |
| Available Room-Nights | `available_room_nights` | Number, sum |
| Occupied Room-Nights | `occupied_room_nights` | Number, sum |
| Vacant Room-Nights | `vacant_room_nights` | Number, sum |

Suggested note under the KPI row:

```text
Occupancy is calculated as occupied room-nights divided by available room-nights.
Available room-nights respect property lease windows and soft-deletion dates.
```

This note is useful because it tells the reviewer that the metric is interval-based, not a simple room count.

## Step 5: Main chart - occupancy trend by property

Add a time-series chart:

| Setting | Value |
|---|---|
| Chart type | Time series |
| Dimension | `month` |
| Breakdown dimension | `property_name` |
| Metric | `occupancy_rate` or `Weighted Occupancy Rate` |
| Sort | `month`, ascending |
| Format | Percent |

Recommended style:

- Show points on the line.
- Use percent axis from `0%` to `100%` if available.
- Keep the legend visible.
- Use a clear title: **Monthly Occupancy Rate by Property**.

Interpretation angle:

- This chart shows seasonality and property-level performance trends.
- Sharp drops can indicate vacancies, lease/deletion boundaries, or limited available inventory.
- Sharp increases can indicate successful occupancy of previously vacant room-nights.

## Step 6: Supporting chart - room-night composition

Add a stacked bar chart to show the numerator and denominator relationship:

| Setting | Value |
|---|---|
| Chart type | Stacked bar chart |
| Dimension | `month` |
| Breakdown dimension | Use separate metrics |
| Metrics | `occupied_room_nights`, `vacant_room_nights` |
| Optional filter | property or city |

Recommended title:

```text
Occupied vs Vacant Room-Nights
```

Why this chart is insightful:

- It explains why the occupancy rate moves.
- A property can have a high occupancy rate with low inventory if few room-nights are available.
- It makes partial-month lease or deletion effects easier to spot.

## Step 7: Property performance table

Add a table with conditional formatting:

| Column | Aggregation / format |
|---|---|
| `property_name` | Dimension |
| `city` | Dimension |
| `available_room_nights` | Sum |
| `occupied_room_nights` | Sum |
| `vacant_room_nights` | Sum |
| `Weighted Occupancy Rate` | Percent |

Sort by `Weighted Occupancy Rate` descending or by `available_room_nights` descending.

Recommended enhancements:

- Add heatmap formatting to occupancy rate.
- Add bar formatting to available room-nights.
- Keep table pagination small enough to fit the report page.

This table gives reviewers a compact property ranking and helps validate that the visual trend matches the underlying counts.

## Step 8: Optional chart - occupancy by city

If the reviewer wants a portfolio-level summary, add a bar chart:

| Setting | Value |
|---|---|
| Chart type | Bar chart |
| Dimension | `city` |
| Metric | `Weighted Occupancy Rate` |
| Secondary metrics | `available_room_nights`, `occupied_room_nights` |

Recommended title:

```text
Weighted Occupancy Rate by City
```

This chart is optional because the sample dataset is small, but it demonstrates that the mart supports broader business slicing.

## Step 9: Add dashboard notes

Add a small text box at the bottom of the report:

```text
Metric notes:
- Occupancy rate = occupied room-nights / available room-nights.
- Checkout date is exclusive.
- Cancelled tenancies are excluded.
- Property and room soft-deletion dates are treated as exclusive availability boundaries.
- Overlapping active tenancies count as one occupied room-night per room-date.
```

These notes make the dashboard self-explanatory and show that the metric has been intentionally modeled.

## Step 10: Validation before sharing

Before submitting the dashboard, confirm:

- The report is connected to `mart_monthly_property_occupancy`, not raw tables.
- `month` is recognized as a date.
- Occupancy is formatted as a percent.
- The main time-series chart uses chronological sorting.
- KPI occupancy uses `SUM(occupied_room_nights) / SUM(available_room_nights)`, not a simple average of percentages.
- Filters work for both `city` and `property_name`.
- The dashboard does not expose service-account credentials, private files, or unrelated GCP resources.
- The values match BigQuery preview queries from `sql/validation_queries.sql`.

## Recommended final screenshot checklist

Capture screenshots for the submission package:

1. BigQuery raw tables.
2. BigQuery staging models.
3. BigQuery final mart table.
4. dbt test result or terminal output.
5. Looker Studio dashboard in view mode.

Store screenshots in:

```text
docs/screenshots/
```

Review screenshots before committing to ensure they do not expose credentials or unrelated personal/project information.

## Sharing the report

1. Click **Share** in Looker Studio.
2. Choose the appropriate reviewer access:
   - direct email access, or
   - link sharing if allowed by the assessment.
3. Confirm the reviewer can view the report without edit permissions.
4. Copy the shared report URL.
5. Replace the Looker Studio placeholder in `README.md` before final submission.

## Interview talking points

If asked to explain the dashboard, use this framing:

> The dashboard is intentionally built from the final dbt mart rather than raw data. The core metric is room-night based occupancy, so it accounts for partial months, lease windows, soft deletions, and checkout exclusivity. I added KPI cards for the portfolio summary, a property-level trend chart for month-over-month movement, and supporting room-night counts so reviewers can see both the rate and the underlying numerator and denominator.

If asked why weighted occupancy is used:

> A simple average of property-level occupancy rates can be misleading because properties can have different numbers of available room-nights. The weighted rate recalculates occupancy as total occupied room-nights divided by total available room-nights across the selected filter context.
