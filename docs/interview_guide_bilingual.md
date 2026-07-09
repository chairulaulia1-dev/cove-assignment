# Interview Guide: Property Occupancy ELT

This document is a bilingual guide for explaining the project during a technical interview. Each major topic contains an Indonesian explanation for understanding and an English version that can be used when speaking with an interviewer.

---

## 1. Executive summary

### Bahasa Indonesia

Tujuan proyek ini adalah membangun pipeline ELT dari hasil export MongoDB berbentuk JSONL menuju BigQuery dan dbt, lalu menghasilkan metrik bulanan:

> Occupancy rate = occupied room-nights / available room-nights

Saya memecah masalah menjadi tiga lapisan:

1. **Ingestion:** menyimpan data sumber ke raw BigQuery tables dengan perubahan seminimal mungkin.
2. **Transformation:** membersihkan identifier, tanggal, timestamp, dan status melalui dbt staging models.
3. **Business modeling:** membangun grain harian per kamar, menentukan availability dan occupancy, lalu mengagregasikannya per properti dan bulan.

Keputusan terpenting adalah menghitung occupancy pada grain `room_id + calendar_date`. Grain ini membuat denominator dan numerator dapat diaudit, serta mencegah overlapping tenancy dihitung lebih dari satu kali.

### English

The goal of this project is to build an ELT pipeline from MongoDB JSONL exports into BigQuery and dbt, producing the following monthly metric:

> Occupancy rate = occupied room-nights / available room-nights

I decomposed the problem into three layers:

1. **Ingestion:** preserve the source data in raw BigQuery tables with minimal transformation.
2. **Transformation:** normalize identifiers, dates, timestamps, and statuses through dbt staging models.
3. **Business modeling:** construct a daily room-level grain, determine availability and occupancy, and aggregate the results by property and month.

The most important design decision was to calculate occupancy at the `room_id + calendar_date` grain. This makes both the numerator and denominator auditable and prevents overlapping tenancies from being counted more than once.

---

## 2. A concise interview introduction

### Bahasa Indonesia

Kalau diminta menjelaskan proyek dalam satu sampai dua menit:

> Saya membangun pipeline ELT yang meng-load tiga MongoDB JSONL exports—properties, rooms, dan tenancies—ke raw BigQuery tables menggunakan Python dan explicit schemas. Raw fields dipertahankan sebagai string agar ingestion tidak rapuh terhadap format timestamp yang tidak konsisten. Setelah itu, dbt staging models mengganti nama MongoDB-style identifiers dan melakukan safe type casting. Mart terakhir menghasilkan daily room availability menggunakan generated date spine, menggabungkannya dengan active tenancy intervals, menghapus kemungkinan double counting pada overlapping tenancies, lalu mengagregasikan occupied dan available room-nights per property per month. Saya juga menambahkan relationship tests, accepted-value tests, metric-invariant tests, validation queries, documentation, dan Looker Studio visualization.

### English

> I built an ELT pipeline that loads three MongoDB JSONL exports—properties, rooms, and tenancies—into raw BigQuery tables using Python and explicit schemas. I preserve raw fields as strings so ingestion remains resilient to inconsistent timestamp formats. dbt staging models then rename MongoDB-style identifiers and safely cast dates and timestamps. The final mart generates daily room availability from a date spine, joins it to active tenancy intervals, prevents double counting from overlapping tenancies, and aggregates occupied and available room-nights by property and month. I also added relationship tests, accepted-value tests, metric-invariant tests, validation queries, documentation, and a Looker Studio visualization.

---

## 3. How I framed the problem

### Bahasa Indonesia

Sebelum menulis SQL, saya mendefinisikan lima hal:

1. **Business question:** Berapa persentase kapasitas kamar yang terisi setiap bulan untuk setiap properti?
2. **Metric grain:** Satu baris logis sebelum agregasi adalah satu kamar pada satu tanggal.
3. **Numerator:** Room-days yang memiliki setidaknya satu active tenancy.
4. **Denominator:** Room-days yang valid di dalam lease property dan sebelum soft deletion property/room.
5. **Boundary behavior:** Lease dates bersifat inclusive, sedangkan deletion date dan checkout date bersifat exclusive.

Pendefinisian grain dilakukan lebih dulu karena sebagian besar kesalahan analytical SQL berasal dari join pada grain yang tidak jelas. Sebagai contoh, join langsung antara rooms dan tenancies kemudian menghitung tanggal dapat menggandakan room-night ketika dua tenancy overlap.

### English

Before writing SQL, I explicitly defined five things:

1. **Business question:** What percentage of room capacity is occupied each month for each property?
2. **Metric grain:** One logical row before aggregation represents one room on one calendar date.
3. **Numerator:** Room-days covered by at least one active tenancy.
4. **Denominator:** Valid room-days within the property lease period and before any property or room soft deletion.
5. **Boundary behavior:** Lease dates are inclusive, while deletion and checkout dates are exclusive.

I defined the grain first because many analytical SQL errors come from joining data at an ambiguous grain. For example, joining rooms directly to tenancies and then expanding dates can duplicate a room-night when two tenancy intervals overlap.

---

## 4. Source-data analysis

### Bahasa Indonesia

Terdapat tiga entities:

- `properties`: menentukan property metadata dan lease availability window.
- `rooms`: menghubungkan physical inventory dengan property.
- `tenancies`: menentukan interval occupancy untuk setiap room.

Temuan data-quality penting:

- `deletedAt` dapat tidak ada, `null`, atau menggunakan format `YYYY-MM-DD HH:MM:SS`.
- `updatedAt` menggunakan ISO 8601 seperti `YYYY-MM-DDTHH:MM:SSZ`.
- Terdapat cancelled tenancy yang tidak boleh masuk numerator.
- Terdapat overlapping active tenancies pada room yang sama.
- Soft-deleted rooms/properties masih dapat direferensikan tenancy.
- Tidak tersedia room creation date.

Temuan tersebut memengaruhi desain pipeline. Saya tidak melakukan strict timestamp parsing pada ingestion karena satu malformed value dapat menggagalkan seluruh load. Parsing dilakukan secara aman di staging sehingga invalid values menjadi `NULL` dan dapat ditemukan melalui tests.

### English

The source contains three entities:

- `properties`: defines property metadata and the lease availability window.
- `rooms`: associates physical room inventory with a property.
- `tenancies`: defines occupancy intervals for each room.

Important data-quality observations include:

- `deletedAt` may be absent, explicitly null, or formatted as `YYYY-MM-DD HH:MM:SS`.
- `updatedAt` uses ISO 8601 values such as `YYYY-MM-DDTHH:MM:SSZ`.
- A cancelled tenancy exists and must not contribute to the numerator.
- Active tenancy intervals overlap for the same room.
- Soft-deleted properties and rooms may still be referenced by tenancies.
- No room creation date is available.

These findings influenced the pipeline design. I avoided strict timestamp parsing during ingestion because one malformed value could fail the entire load. Instead, parsing happens safely in staging, where invalid values become `NULL` and can be identified through tests.

---

## 5. Why ELT instead of ETL

### Bahasa Indonesia

Saya memilih ELT karena BigQuery sangat cocok untuk set-based transformations dan dbt memberikan version control, dependency management, testing, serta documentation untuk SQL transformations.

Python hanya bertanggung jawab atas transport dan raw persistence. Business logic tetap berada di SQL/dbt agar:

- mudah direview oleh data engineers dan analysts;
- lineage antar-model terlihat;
- transformations dapat di-test secara modular;
- raw source tetap tersedia untuk debugging dan reprocessing;
- perubahan metric dapat ditelusuri melalui Git.

### English

I chose ELT because BigQuery is well suited to set-based transformations, while dbt provides version control, dependency management, testing, and documentation for SQL transformations.

Python is responsible only for transport and raw persistence. Business logic remains in SQL and dbt so that:

- data engineers and analysts can review it easily;
- model lineage is explicit;
- transformations can be tested modularly;
- the raw source remains available for debugging and reprocessing;
- metric changes are traceable through Git.

---

## 6. Ingestion design

### Bahasa Indonesia

Python loader melakukan hal berikut:

1. Membaca configuration dari environment variables.
2. Memvalidasi bahwa semua variable dan source files tersedia.
3. Membuat raw dataset jika belum ada.
4. Meng-load setiap JSONL file menggunakan explicit schema.
5. Menggunakan `WRITE_TRUNCATE` untuk deterministic assessment reruns.
6. Menampilkan row counts dan actionable error messages.

Semua source fields di-load sebagai `STRING`. Ini disengaja:

- raw layer merepresentasikan sumber, bukan business interpretation;
- inconsistent timestamp tidak menggagalkan load;
- schema drift lebih mudah diperiksa;
- typed conversion tetap terpusat di staging.

`WRITE_TRUNCATE` sesuai untuk assessment kecil dan repeatable. Dalam production, saya akan menggunakan immutable ingestion batches, load timestamp, source filename, checksum, dan incremental or merge processing.

### English

The Python loader performs the following steps:

1. Reads configuration from environment variables.
2. Validates that all required settings and source files exist.
3. Creates the raw dataset when necessary.
4. Loads each JSONL file using an explicit schema.
5. Uses `WRITE_TRUNCATE` for deterministic assessment reruns.
6. Reports row counts and actionable error messages.

All source fields are loaded as `STRING` intentionally:

- the raw layer represents the source rather than a business interpretation;
- inconsistent timestamps do not fail ingestion;
- schema drift remains easy to inspect;
- typed conversion stays centralized in staging.

`WRITE_TRUNCATE` is appropriate for a small, repeatable assessment. In production, I would use immutable ingestion batches, load timestamps, source filenames, checksums, and incremental or merge-based processing.

---

## 7. Staging-layer design

### Bahasa Indonesia

Staging memiliki tanggung jawab terbatas:

- rename `_id`, `propertyId`, dan `roomId` menjadi nama konsisten;
- cast source dates menjadi `DATE`;
- parse timestamp secara aman;
- normalize status menggunakan `LOWER(TRIM(...))`;
- mempertahankan satu row per source entity.

Saya tidak menaruh occupancy logic di staging. Pemisahan ini menjaga staging reusable dan membuat mart menjadi satu-satunya tempat untuk business definition.

`SAFE_CAST` dan `SAFE.PARSE_TIMESTAMP` dipilih agar unexpected values menghasilkan `NULL`, bukan membuat seluruh dbt run gagal. Required fields kemudian diperiksa menggunakan dbt tests.

### English

The staging layer has a deliberately narrow responsibility:

- rename `_id`, `propertyId`, and `roomId` into consistent identifiers;
- cast source dates to `DATE`;
- parse timestamps safely;
- normalize status using `LOWER(TRIM(...))`;
- preserve one row per source entity.

I do not place occupancy logic in staging. This keeps staging reusable and makes the mart the single location for the business definition.

I use `SAFE_CAST` and `SAFE.PARSE_TIMESTAMP` so unexpected values produce `NULL` rather than failing the entire dbt run. Required fields are then enforced through dbt tests.

---

## 8. Mart logic, CTE by CTE

### 8.1 `properties`

#### Bahasa Indonesia

CTE ini menghitung `last_available_date`.

- Lease end bersifat inclusive.
- Jika property deleted pada tanggal tertentu, tanggal deletion tidak available.
- Karena itu, effective end adalah nilai minimum antara `lease_end_date` dan `deleted_date - 1 day`.

#### English

This CTE calculates `last_available_date`.

- The lease end date is inclusive.
- If a property is deleted on a given date, that deletion date is not available.
- Therefore, the effective end is the earlier of `lease_end_date` and `deleted_date - 1 day`.

### 8.2 `date_bounds`

#### Bahasa Indonesia

CTE ini menentukan minimum dan maximum relevant dates. Tujuannya agar date spine tidak menggunakan hard-coded calendar range dan tidak menghasilkan tanggal yang tidak dibutuhkan.

#### English

This CTE derives the minimum and maximum relevant dates. It avoids a hard-coded calendar range and prevents the model from generating unnecessary dates.

### 8.3 `date_spine`

#### Bahasa Indonesia

`GENERATE_DATE_ARRAY` menghasilkan satu row per calendar date. Daily spine diperlukan karena lease dan tenancy adalah interval, sedangkan metric menggunakan room-night.

#### English

`GENERATE_DATE_ARRAY` produces one row per calendar date. A daily spine is necessary because leases and tenancies are intervals while the metric is based on room-nights.

### 8.4 `available_room_days`

#### Bahasa Indonesia

Properties di-join dengan rooms dan date spine untuk membentuk denominator pada grain:

```text
property_id + room_id + calendar_date
```

Suatu room-day hanya dibuat jika:

- tanggal berada di dalam effective property availability;
- room belongs to the property;
- room belum soft-deleted pada tanggal tersebut.

#### English

Properties are joined to rooms and the date spine to establish the denominator at:

```text
property_id + room_id + calendar_date
```

A room-day exists only when:

- the date falls inside effective property availability;
- the room belongs to that property;
- the room has not been soft-deleted on that date.

### 8.5 `active_tenancies`

#### Bahasa Indonesia

Hanya tenancy dengan status `active`, valid check-in/check-out dates, dan positive interval yang dipertahankan. Cancelled dan invalid intervals tidak boleh berkontribusi pada occupancy.

#### English

Only tenancies with an `active` status, valid check-in and checkout dates, and a positive interval are retained. Cancelled and invalid intervals cannot contribute to occupancy.

### 8.6 `room_day_status`

#### Bahasa Indonesia

Setiap available room-day di-left join ke tenancy interval menggunakan:

```text
calendar_date >= check_in_date
calendar_date < check_out_date
```

Checkout dibuat exclusive karena room tidak dianggap occupied pada checkout date.

`COUNTIF(tenancy matched) > 0` menghasilkan boolean `is_occupied`. Jika dua tenancy overlap, jumlah match mungkin lebih dari satu, tetapi boolean tetap `TRUE`. Dengan demikian satu room-day hanya dihitung occupied satu kali.

#### English

Each available room-day is left-joined to tenancy intervals using:

```text
calendar_date >= check_in_date
calendar_date < check_out_date
```

Checkout is exclusive because the room is not considered occupied on the checkout date.

`COUNTIF(tenancy matched) > 0` produces the `is_occupied` boolean. If two tenancies overlap, the number of matches may exceed one, but the boolean remains `TRUE`. Therefore, one room-day is counted as occupied only once.

### 8.7 Monthly aggregation

#### Bahasa Indonesia

Final aggregation menggunakan:

- `COUNT(*)` untuk available room-nights;
- `COUNTIF(is_occupied)` untuk occupied room-nights;
- `COUNTIF(NOT is_occupied)` untuk vacant room-nights;
- `SAFE_DIVIDE` untuk occupancy rate.

`SAFE_DIVIDE` menghindari runtime error jika denominator nol. Namun, dengan desain denominator-first, mart hanya menghasilkan rows yang memiliki available room-days.

#### English

The final aggregation uses:

- `COUNT(*)` for available room-nights;
- `COUNTIF(is_occupied)` for occupied room-nights;
- `COUNTIF(NOT is_occupied)` for vacant room-nights;
- `SAFE_DIVIDE` for occupancy rate.

`SAFE_DIVIDE` prevents runtime errors when the denominator is zero. However, because the model starts from availability, the mart only produces rows that contain available room-days.

---

## 9. Assumptions and how to defend them

### Checkout is exclusive

**Bahasa Indonesia:** Pada rental systems, checkout date biasanya merupakan tanggal kamar dilepas, bukan malam tambahan yang dihuni. Exclusive checkout juga membuat back-to-back tenancies tidak overlap.

**English:** In rental systems, the checkout date normally represents the date the room is released rather than an additional occupied night. An exclusive checkout also prevents back-to-back tenancies from overlapping.

### Lease boundaries are inclusive

**Bahasa Indonesia:** Source hanya memberikan date tanpa time. Interpretasi paling konsisten adalah property tersedia pada lease start dan lease end calendar dates.

**English:** The source provides dates without timestamps. The most consistent interpretation is that the property is available on both the lease start and lease end calendar dates.

### Deletion date is exclusive

**Bahasa Indonesia:** Requirement menyatakan entity tidak available “on or after” deletion date. Maka last available day adalah satu hari sebelumnya.

**English:** The requirement states that an entity is unavailable “on or after” its deletion date. Therefore, its final available day is the previous date.

### Room availability starts with the property lease

**Bahasa Indonesia:** Source tidak memiliki room creation date. `updatedAt` tidak digunakan sebagai creation timestamp karena update time tidak membuktikan kapan room pertama kali tersedia.

**English:** The source does not contain a room creation date. I do not use `updatedAt` as a creation timestamp because an update time does not establish when the room first became available.

### Overlaps count once

**Bahasa Indonesia:** Metric mengukur room capacity, bukan jumlah contracts. Satu kamar tidak dapat menghasilkan lebih dari satu occupied room-night pada tanggal yang sama.

**English:** The metric measures room capacity rather than contract count. A single room cannot contribute more than one occupied room-night on the same date.

---

## 10. Testing strategy

### Bahasa Indonesia

Testing dibagi menjadi beberapa kategori:

1. **Entity integrity**
   - primary identifiers `not_null` dan `unique`;
   - room-to-property dan tenancy-to-room relationships.
2. **Domain validity**
   - tenancy status hanya `active` atau `cancelled`.
3. **Mart completeness**
   - required mart fields tidak null;
   - mart mencakup expected availability period.
4. **Business invariants**
   - occupancy rate berada di antara 0 dan 1;
   - occupied room-nights tidak melebihi available room-nights.
5. **Manual validation**
   - raw/staging row counts;
   - soft-deleted entities;
   - cancelled and overlapping tenancies;
   - monthly result preview.

Salah satu temuan saat menjalankan pipeline adalah dataset memiliki default partition expiration 60 hari. Akibatnya hanya dua partisi terbaru yang tersisa. Saya memperbaikinya dengan explicit model-level retention dan menambahkan completeness test agar truncation semacam itu terdeteksi.

Pelajaran pentingnya: tests yang hanya memeriksa validity pada rows yang masih ada tidak selalu dapat menemukan missing data. Karena itu completeness tests juga dibutuhkan.

### English

The testing strategy covers several categories:

1. **Entity integrity**
   - primary identifiers are `not_null` and `unique`;
   - room-to-property and tenancy-to-room relationships are valid.
2. **Domain validity**
   - tenancy status is limited to `active` or `cancelled`.
3. **Mart completeness**
   - required mart fields are not null;
   - the mart covers the expected availability period.
4. **Business invariants**
   - occupancy rate stays between zero and one;
   - occupied room-nights never exceed available room-nights.
5. **Manual validation**
   - raw and staging row counts;
   - soft-deleted entities;
   - cancelled and overlapping tenancies;
   - monthly result previews.

During execution, I discovered that the dataset had a default partition expiration of 60 days. As a result, only the two latest monthly partitions remained. I fixed this by setting explicit model-level retention and added a completeness test so similar truncation is detected.

The important lesson is that tests validating only the rows that still exist may not detect missing data. Completeness tests are also necessary.

---

## 11. Data model and materialization decisions

### Bahasa Indonesia

Staging models menggunakan views karena:

- volume sample kecil;
- transformations ringan;
- tidak perlu menyimpan duplicate intermediate data;
- source changes langsung terlihat setelah dbt run.

Mart menggunakan table karena:

- digunakan langsung oleh BI tool;
- daily expansion lebih mahal daripada simple staging query;
- response dashboard lebih predictable;
- partitioning dan clustering dapat diterapkan.

Mart dipartisi berdasarkan `month` dan di-cluster berdasarkan `property_id`. Pada dataset kecil, optimisasi ini tidak diperlukan untuk biaya, tetapi menunjukkan physical design yang sesuai dengan access pattern: filter berdasarkan time range dan property.

### English

Staging models are materialized as views because:

- the sample volume is small;
- transformations are lightweight;
- duplicate intermediate storage is unnecessary;
- source changes are reflected when dbt runs.

The mart is materialized as a table because:

- it is consumed directly by a BI tool;
- daily expansion is more expensive than the staging queries;
- dashboard response time becomes more predictable;
- partitioning and clustering can be applied.

The mart is partitioned by `month` and clustered by `property_id`. At this scale, the optimization is not required for cost, but it demonstrates a physical design aligned with the expected access pattern: filtering by time range and property.

---

## 12. Security and configuration

### Bahasa Indonesia

Tidak ada credential yang di-hard-code. Runtime settings berasal dari environment variables dan service-account JSON tidak boleh masuk Git.

`.gitignore` mengecualikan:

- `.env`;
- `profiles.yml`;
- `keys/`;
- service-account JSON;
- Python virtual environments;
- dbt logs dan compiled artifacts.

Untuk production, saya akan mempertimbangkan Workload Identity atau service-account impersonation agar tidak menggunakan long-lived JSON key.

### English

No credentials are hard-coded. Runtime settings come from environment variables, and the service-account JSON must never be committed to Git.

`.gitignore` excludes:

- `.env`;
- `profiles.yml`;
- `keys/`;
- service-account JSON files;
- Python virtual environments;
- dbt logs and compiled artifacts.

For production, I would prefer Workload Identity or service-account impersonation instead of a long-lived JSON key.

---

## 13. Looker Studio explanation

### Bahasa Indonesia

Looker Studio menggunakan final mart, bukan raw atau staging data. Chart utama adalah time series:

- dimension: `month`;
- breakdown: `property_name`;
- metric: average `occupancy_rate`;
- format: percentage;
- optional filters: city dan property.

Average digunakan sebagai aggregation guard di Looker Studio. Pada mart, grain sudah unique per property-month, sehingga average dan sum terhadap satu row memberikan behavior yang jelas. `SUM(occupancy_rate)` sebaiknya dihindari karena rate bukan additive metric.

Jika perlu membuat rolled-up occupancy lintas properti, formula yang benar bukan average sederhana dari property rates. Formula yang benar adalah:

```text
SUM(occupied_room_nights) / SUM(available_room_nights)
```

Ini adalah weighted occupancy rate.

### English

Looker Studio consumes the final mart rather than raw or staging data. The primary chart is a time series with:

- dimension: `month`;
- breakdown: `property_name`;
- metric: average `occupancy_rate`;
- format: percentage;
- optional filters: city and property.

Average is used as an aggregation safeguard in Looker Studio. The mart already has one row per property-month, so the behavior remains clear. `SUM(occupancy_rate)` should be avoided because a rate is not an additive metric.

For occupancy rolled up across properties, the correct formula is not a simple average of property rates. It is:

```text
SUM(occupied_room_nights) / SUM(available_room_nights)
```

This produces a weighted occupancy rate.

---

## 14. Trade-offs and alternatives

### Daily spine versus interval arithmetic

**Bahasa Indonesia:** Daily expansion sangat mudah diaudit dan sesuai untuk room-night metrics, tetapi row volume dapat besar. Pada skala besar, saya dapat menggunakan interval intersection dan monthly boundary arithmetic untuk menghindari full daily expansion.

**English:** Daily expansion is highly auditable and naturally fits room-night metrics, but it can generate a large number of rows. At scale, I could use interval intersection and monthly boundary arithmetic to avoid fully expanding every day.

### Full refresh versus incremental mart

**Bahasa Indonesia:** Full refresh dipilih karena source sangat kecil dan assessment harus repeatable. Production mart dapat dibuat incremental per affected month, tetapi updates pada leases, deletions, atau historical tenancies memerlukan lookback/reprocessing strategy.

**English:** I chose a full refresh because the source is small and the assessment should be repeatable. A production mart could process affected months incrementally, but updates to leases, deletions, or historical tenancies would require an explicit lookback and reprocessing strategy.

### Raw strings versus typed raw columns

**Bahasa Indonesia:** Raw strings meningkatkan ingestion resilience dan source fidelity. Kekurangannya, invalid values baru terlihat di staging. Alternatif production adalah typed landing table plus rejected-record quarantine.

**English:** Raw strings improve ingestion resilience and source fidelity. The trade-off is that invalid values are detected only in staging. A production alternative would use a typed landing table together with a rejected-record quarantine.

### dbt views versus tables

**Bahasa Indonesia:** Views mengurangi storage dan cocok untuk transformations ringan, tetapi query cost dihitung kembali. Jika source besar atau staging sering digunakan, selected staging models dapat diubah menjadi incremental tables.

**English:** Views reduce storage and suit lightweight transformations, but their query cost is recomputed. If the source grows or staging models are frequently reused, selected staging models could become incremental tables.

---

## 15. What I would improve for production

### Bahasa Indonesia

Untuk production-grade implementation, saya akan menambahkan:

1. Orchestration menggunakan managed scheduler seperti Cloud Composer, Airflow, atau dbt Cloud.
2. Immutable raw ingestion dengan `ingested_at`, batch ID, source filename, dan checksum.
3. Incremental models dengan controlled historical lookback.
4. Source freshness dan volume-anomaly checks.
5. Rejected-record quarantine untuk malformed rows.
6. CI pipeline yang menjalankan SQL linting, `dbt parse`, dan `dbt build`.
7. Infrastructure as code untuk datasets, IAM, retention, dan scheduled jobs.
8. Central secrets management atau Workload Identity.
9. Monitoring untuk failed loads, test failures, freshness, dan unexpected occupancy changes.
10. Historical entity modeling jika property/room attributes berubah over time.
11. A governed calendar dimension untuk fiscal calendars dan reporting attributes.
12. Metric definitions in a semantic layer agar BI tools menggunakan formula yang konsisten.

### English

For a production-grade implementation, I would add:

1. Orchestration through a managed scheduler such as Cloud Composer, Airflow, or dbt Cloud.
2. Immutable raw ingestion with `ingested_at`, batch ID, source filename, and checksum.
3. Incremental models with a controlled historical lookback.
4. Source freshness and volume-anomaly checks.
5. A rejected-record quarantine for malformed rows.
6. A CI pipeline running SQL linting, `dbt parse`, and `dbt build`.
7. Infrastructure as code for datasets, IAM, retention, and scheduled jobs.
8. Central secrets management or Workload Identity.
9. Monitoring for failed loads, test failures, freshness, and unexpected occupancy changes.
10. Historical entity modeling when property or room attributes change over time.
11. A governed calendar dimension for fiscal calendars and reporting attributes.
12. Semantic-layer metric definitions so BI tools use consistent formulas.

---

## 16. Likely interview questions and sample answers

### Why did you not use `updatedAt` as the room availability start date?

**English answer:**

> `updatedAt` represents the latest modification time, not necessarily the creation or activation time. Using it as the availability start could incorrectly remove valid historical room capacity. Because no room creation date was supplied, I documented the assumption that rooms are available from the property lease start. In production, I would request a creation or activation timestamp and model room availability explicitly.

### How do you prevent overlapping tenancies from inflating occupancy?

**English answer:**

> I first establish one row per available room and calendar date. I then join all matching active tenancy intervals and reduce the result to a boolean using `COUNTIF(match) > 0`. Whether one or several tenancies match, that room-date contributes exactly one occupied room-night.

### Why is checkout exclusive?

**English answer:**

> Treating checkout as exclusive follows common nightly accommodation semantics and allows one tenant to check out on the same date another checks in without producing an overlap. The occupied interval is therefore `[check_in_date, check_out_date)`.

### Why do you calculate availability before occupancy?

**English answer:**

> Availability defines the denominator and acts as the valid inventory boundary. Starting from available room-days guarantees that a tenancy outside a lease period or after soft deletion cannot create artificial capacity or occupancy.

### Why use `SAFE_DIVIDE`?

**English answer:**

> `SAFE_DIVIDE` protects the model from division-by-zero failures. The current model only emits property-months with available room-days, but the safe function makes the intended behavior explicit and keeps the calculation robust if upstream rules change.

### What happened with partition expiration?

**English answer:**

> During validation, I found that the analytics dataset had a default 60-day partition expiration. BigQuery immediately removed older monthly partitions, leaving only two rows. I diagnosed it by comparing the model query result with the materialized table and then inspecting `INFORMATION_SCHEMA` options. I overrode retention at the model level and added a completeness test. This was a useful reminder that infrastructure-level settings can affect data correctness even when the transformation SQL is valid.

### Would a simple average of property occupancy rates be correct?

**English answer:**

> Not necessarily. Properties have different room-night capacity, so a simple average would weight small and large properties equally. The correct portfolio-level rate is the sum of occupied room-nights divided by the sum of available room-nights.

### How would this model scale?

**English answer:**

> The daily spine is clear and auditable, and BigQuery can handle substantial expansion, especially with partitioning. At much larger scale, I would process only affected months incrementally and evaluate interval arithmetic to avoid generating every room-day. I would make that optimization based on measured volume, cost, and latency rather than adding complexity prematurely.

### How would you handle late-arriving or corrected tenancies?

**English answer:**

> I would preserve immutable ingestion history and identify the months affected by new or changed tenancy intervals. The incremental mart would then reprocess those partitions using a configurable lookback window. For unrestricted historical corrections, I would support targeted backfills by date range.

### What is the biggest limitation of this dataset?

**English answer:**

> The main modeling limitation is the absence of a room creation or activation date. That forces an assumption about when room inventory becomes available. The small sample also does not cover open-ended tenancies, status history, timezone boundaries, or changing room-to-property relationships, all of which I would clarify before production implementation.

---

## 17. A structured walkthrough during screen sharing

### Bahasa Indonesia

Urutan yang disarankan saat interviewer meminta walkthrough:

1. Mulai dari README dan jelaskan business metric.
2. Tunjukkan tiga raw JSONL files dan data-quality irregularities.
3. Buka Python loader dan jelaskan environment variables, explicit schemas, serta deterministic reload.
4. Buka `sources.yml` dan tunjukkan raw-to-dbt boundary.
5. Tunjukkan staging models dan safe casting.
6. Buka mart dan jelaskan setiap CTE sesuai grain.
7. Tunjukkan tests, khususnya overlap invariants dan completeness test.
8. Tampilkan BigQuery raw, staging, dan mart tables.
9. Tampilkan validation queries dan hasil zero violations.
10. Akhiri dengan Looker Studio chart dan production improvements.

Jangan mulai dari baris SQL pertama tanpa memberikan business context. Interviewer biasanya lebih tertarik pada alasan keputusan dibanding kemampuan membaca syntax.

### English

A recommended screen-sharing sequence is:

1. Start with the README and explain the business metric.
2. Show the three raw JSONL files and their data-quality irregularities.
3. Open the Python loader and explain environment variables, explicit schemas, and deterministic reloads.
4. Open `sources.yml` and show the raw-to-dbt boundary.
5. Show the staging models and safe type conversion.
6. Open the mart and explain each CTE in terms of grain.
7. Show the tests, especially overlap invariants and the completeness test.
8. Show the raw, staging, and mart tables in BigQuery.
9. Show validation queries and zero-violation results.
10. Finish with the Looker Studio chart and production improvements.

Do not start by reading SQL line by line without business context. Interviewers are generally more interested in why decisions were made than in a recital of syntax.

---

## 18. Communication framework for unknown requirements

### Bahasa Indonesia

Ketika requirement ambigu, gunakan pola:

1. **State the ambiguity:** Jelaskan informasi apa yang tidak tersedia.
2. **Choose a reasonable assumption:** Pilih behavior yang paling konsisten dengan domain.
3. **Document it:** Masukkan asumsi ke documentation dan code comments.
4. **Make it testable:** Tambahkan query atau test untuk memverifikasi dampaknya.
5. **Describe the production clarification:** Jelaskan pertanyaan yang akan diajukan kepada stakeholder.

Contoh:

> Source tidak menyediakan room creation date. Saya mengasumsikan room tersedia sejak property lease start karena `updatedAt` bukan creation timestamp. Saya dokumentasikan asumsi ini, dan dalam production saya akan meminta explicit activation history dari source owner.

### English

When a requirement is ambiguous, use this framework:

1. **State the ambiguity:** Explain which information is unavailable.
2. **Choose a reasonable assumption:** Select the behavior most consistent with the domain.
3. **Document it:** Record the assumption in documentation and code comments.
4. **Make it testable:** Add a query or test that verifies its impact.
5. **Describe the production clarification:** Explain what you would ask the stakeholder.

Example:

> The source does not provide a room creation date. I assume the room is available from the property lease start because `updatedAt` is not a creation timestamp. I documented that assumption, and in production I would request explicit activation history from the source owner.

---

## 19. Key terminology for the interview

| Term | Simple English explanation |
|---|---|
| Grain | What one row represents. |
| Room-night | One available room on one calendar date. |
| Date spine | A generated sequence containing one row per date. |
| Inclusive boundary | The boundary date is included. |
| Exclusive boundary | The boundary date is not included. |
| Soft deletion | A record remains stored but is marked as deleted. |
| Idempotent | Running the same process again produces the same intended state. |
| Referential integrity | Child identifiers correctly reference existing parent records. |
| Schema drift | The source structure or data types change over time. |
| Data lineage | The dependency path from source data to final output. |
| Additive metric | A metric that can safely be summed across dimensions. |
| Weighted rate | A rate calculated from summed numerators and denominators. |
| Late-arriving data | Data that arrives after its expected processing period. |
| Backfill | Reprocessing historical periods to incorporate corrections or missing data. |

---

## 20. Final interview closing statement

### Bahasa Indonesia

> Fokus utama saya bukan hanya menghasilkan occupancy rate, tetapi memastikan metric tersebut dapat dijelaskan, diuji, dan direproduksi. Saya memisahkan source preservation, type normalization, dan business logic agar setiap layer memiliki tanggung jawab yang jelas. Saya juga memvalidasi edge cases seperti soft deletion, cancelled tenancy, overlapping tenancy, dan partition retention. Untuk production, langkah berikutnya adalah incremental processing, orchestration, freshness monitoring, CI, dan immutable ingestion history.

### English

> My main goal was not only to produce an occupancy rate, but to make the metric explainable, testable, and reproducible. I separated source preservation, type normalization, and business logic so each layer has a clear responsibility. I also validated edge cases such as soft deletion, cancelled tenancies, overlapping intervals, and partition retention. For production, the next steps would be incremental processing, orchestration, freshness monitoring, CI, and immutable ingestion history.

---

## 21. Final preparation checklist

### Sebelum interview

- Pastikan repository tidak berisi `.env`, `profiles.yml`, atau service-account JSON.
- Jalankan `dbt run --full-refresh` dan `dbt test`.
- Simpan screenshot raw, staging, mart, dan successful test output.
- Pastikan Looker Studio report memiliki nama dan sharing access yang benar.
- Latih executive summary tanpa membaca.
- Latih penjelasan grain, numerator, denominator, dan date boundaries.
- Siapkan jawaban tentang overlap, partition expiration, dan production scaling.
- Jangan menghafal seluruh SQL; pahami alasan setiap CTE.

### Before the interview

- Confirm that `.env`, `profiles.yml`, and service-account JSON files are absent from the repository.
- Run `dbt run --full-refresh` and `dbt test`.
- Keep screenshots of raw, staging, mart, and successful test output.
- Confirm the Looker Studio report name and sharing permissions.
- Practice the executive summary without reading it.
- Practice explaining the grain, numerator, denominator, and date boundaries.
- Prepare answers about overlaps, partition expiration, and production scaling.
- Do not memorize every SQL line; understand the purpose of every CTE.
