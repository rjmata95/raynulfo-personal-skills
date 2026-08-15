---
alias: mysql-prod
kind: mysql
env: prod
last_verified: 2026-08-12
---

# mysql-prod — schema

BIDW production MySQL. ETL-fed reporting/analytics warehouse behind the dashboards — the
legacy-side counterpart to the NextGen Mongo clusters.

Default database: `DASHBOARD_PROD` (**797 tables**, verified 2026-08-07).

> **Structure only — never PHI.** This warehouse holds clinical detail: lab results, medical
> records, medications, observations. Record table and column names, row counts, and indexes.
> Never record row values.

## Schemas on this server

Verified 2026-08-07 via `SHOW DATABASES`. The alias defaults to `DASHBOARD_PROD`; the rest are
reachable if your grants allow.

| Schema | Role |
|---|---|
| `DASHBOARD_PROD` | Dashboard/reporting tables — the default |
| `BIDW` | Core data warehouse |
| `BI_APPS` | BI application tables |
| `BI_RITS` | RITS subject area |
| `BI_SECURE` | Restricted/secured subject area |
| `BI_SURVEY` | Survey data |
| `BIPB` | BI PB subject area |
| `STAGING_DB` | ETL staging |

```bash
dbq mysql-prod 'SHOW DATABASES'
DBQ_DB=BIDW dbq --collections mysql-prod          # SHOW TABLES in BIDW
dbq mysql-prod 'SELECT * FROM BIDW.some_table LIMIT 5'   -- or qualify inline
```

## Largest tables in `DASHBOARD_PROD`

Verified 2026-08-07. `table_rows` is an InnoDB estimate — fine for triage, not for reporting.

| Table | Rows (est) | Data | Index |
|---|---|---|---|
| `PROCESS_EXCEPTION_LOG` | 3.5 M | **353 GB** | 246 MB |
| `STAGE_PATIENT_MEDICATION_DRFIRST` | 13.4 M | 58 GB | 4.5 GB |
| `AUDIT_LOG` | 186 M | 29 GB | 13 GB |
| `LAB_RESULT_DETAIL` | 247 M | 27 GB | 17 GB |
| `LAB_RESULT_HEADER` | 1.7 M | 27 GB | 113 MB |
| `PAT_MEDICATIONS` | 76.5 M | 18 GB | 9.5 GB |
| `BUSIAPPS_TXN_RESPONSE` | 101 M | 16 GB | 32 GB |
| `PAT_MEDICAL_RECORD` | 101 M | 15 GB | 16 GB |
| `NB_VISIT_ICD_AP_DTLS` | 62.5 M | 12 GB | 4 GB |
| `DB_PROGRAM_LOG` | 97 M | 11 GB | 14 GB |

**Read that first row carefully.** `PROCESS_EXCEPTION_LOG` averages ~100 KB per row — it stores
large payloads or stack traces. `SELECT *` against it will return enormous rows. Always
project explicit columns and add `LIMIT`.

`STAGE_PATIENT_MEDICATION_DRFIRST` is DrFirst/Rcopia medication ETL staging, relevant to eRx
and polypharmacy work. Note the `_bkp56` sibling — manual backup copies exist alongside live
staging tables, so confirm which one is current before drawing conclusions.

## `BI_RITS.EPD_MEDICATION_CLINICAL_SUMMARY_RECOMMENDATION`

RITS AI-summary panel source. One row per order (`PAT_CATEGORY_ID`). Verified 2026-08-12: **615 rows, 615 distinct IDs, zero secondary indexes, no PK.**

| Column | Type | Notes |
|---|---|---|
| `PAT_CATEGORY_ID` | bigint NOT NULL | Order key. Not unique-constrained. |
| `PATIENT_ID` | bigint NOT NULL | |
| `RECOMMENDATION_SUMMARY` | text NOT NULL | |
| `EVIDENCE` | json NOT NULL | Array of `{value_name, value, value_type}`. SGLT2 `value` may be number, not string. |
| `ACTIVE` | tinyint NOT NULL | All 1 on 2026-08-12. |
| `CREATED_DATE` | timestamp NOT NULL | Original write. |
| `CREATED_BY` | text NOT NULL | `snowflake_epd_engine` |
| `UPDATED_DATE` | timestamp NOT NULL | **Full-refresh stamp** — every row shares the same value after a sync. |
| `UPDATED_BY` | text NOT NULL | |

Default database is `DASHBOARD_PROD`; always qualify `BI_RITS.…`. Snowflake `LANDING_SHARE.BI_RITS` is a lagging mysql-in copy of this table, not the same shape (see gotchas).

## Conventions

- **Always `LIMIT` while exploring.** Several tables exceed 100 M rows.
- **Project explicit columns.** `SELECT *` on the big tables is slow and floods context.
- **Aggregate server-side** — `GROUP BY` rather than pulling rows to count locally.
- **`EXPLAIN` before blaming the database.** `type: ALL` means a full scan; `key: NULL` means
  no index used.
- **Quote string comparisons.** Comparing a `VARCHAR` column to a bare number makes MySQL
  coerce and silently ignore the index.
- **ETL lag.** This warehouse trails the operational Mongo stores. A count that disagrees with
  Mongo may be timing, not a defect.
- **Read-only.** `INSERT`/`UPDATE`/`DELETE`/`DROP`/`TRUNCATE`/`ALTER` are rejected before
  connecting.

## Useful starting queries

```sql
-- Table inventory by size
SELECT table_name, table_rows,
       ROUND(data_length/1024/1024) AS data_mb,
       ROUND(index_length/1024/1024) AS idx_mb
FROM information_schema.tables
WHERE table_schema = DATABASE()
ORDER BY data_length DESC
LIMIT 20;

-- Find a table by name fragment
SELECT table_name, table_rows
FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_name LIKE '%MEDICATION%'
ORDER BY table_rows DESC;
```

```bash
dbq --schema mysql-prod.PAT_MEDICATIONS        # DESCRIBE + SHOW INDEX
```

## The encounter-medication trio

Verified 2026-08-13. These three answer most "who changed a patient's meds, and did anyone review
them" questions. See `gotchas.md` for the four rocks in here — none of them is obvious from DDL.

### `PAT_MEDICATIONS` — the patient medication list (~76.5 M rows)

The shared row store. **Not exclusively legacy-owned any more**: NextGen's
`patient-medication-data-relay` upserts into it as `NEXTGEN_SERVICE`.

| Column | Type | Notes |
|---|---|---|
| `MEDICATION_ID` | bigint PK | auto-increment — use it for recency, there is no date index |
| `PATIENT_ID` | bigint | indexed |
| `SOURCE` | varchar(10) NOT NULL, default `INTERNAL` | **the writer discriminator.** `EXTERNAL` / `EXT(MODIF)` / `EXT(DEL)` = NextGen relay; `INTERNAL` = in-house dispensary (ASMeds) |
| `CREATED_BY` / `UPDATED_BY` | varchar | `NEXTGEN_SERVICE` for relay writes, an individual username for dispensary writes |
| `CREATED_DATE` / `UPDATED_DATE` | datetime | **not indexed** |
| `ACTIVE` | tinyint(1), default 1 | discontinue sets 0 alongside `INACTIVE_USER_ID`, `INACTIVE_REASON`, `INACTIVE_DATE` |
| `ENCOUNTER_RCOPIAID` | bigint | indexed — DrFirst Rcopia encounter key |
| `MED_NAME`, `MED_NAME_ID` | varchar / int | both indexed |
| `LEGACY_MEDICATION_ID`, `MED_ID`, `PRESCRIPTION_GUID` | | cross-system identity |

Read by `usp_DrFirst_Medication_PreviewSignOff_Get` — a name that does **not** mean the data came
from DrFirst. Written by `usp_PatMedications_Upsert`. The real DrFirst ETL staging table is the
separate `STAGE_PATIENT_MEDICATION_DRFIRST`.

### `NB_MEDICATION_STATE` — per-medication adherence, **per progress note** (~93 M rows)

`(NOTE_ID, MEDICATION_ID, MED_STATE_CODE, MED_STATE, CREATED_BY, CREATION_DATE, UPDATED_BY,
UPDATION_DATE)`, PK `MED_STATE_ID`. **There is no `PATIENT_ID`** — a row cannot exist outside a note,
so every question here is encounter-scoped. `MED_STATE` holds the description string; the eight live
values are `Taking As Directed`, `Taking As Needed`, `Taking Inconsistently`, `Not Taking`, `On Hold`,
`Discontinued`, `Newly Prescribed`, `Patient Did Not Bring`. Codes resolve via
`NB_MEDICATION_STATE_LK` (`MED_STATE_CODE` → `MED_STATE_DESC`).

Indexes: `IDX_MEDICATION_ID`, `IDX_NOTE_ID`, and `MED_CREATION_index (MED_STATE, CREATION_DATE)` —
status-first, so a bare date predicate does not use it.

Still receiving ~40 K rows/day from legacy MyNotes as of 2026-08-13. Also read by the NextGen RCM
claim ETL (`visit-claims-cmd/scripts/hedis_mr.sql`) to emit HEDIS CPT-II codes, and exported through
`usp_CCDA_{PN,CCD}_PatientMedications_Get`.

### `VENDOR_CHENMED_MAPPING_LK` — vendor enrolment lookup (~33.7 K rows)

The "is this practice ePrescribe-enabled" gate. `EXTERNAL_ID` joins to a practice/office/user id
depending on `ENTITY`. See `gotchas.md` for the `ENTITY` vs `ENTITY_TYPE` split. Index
`IX_VENDOR_CHENMED_MAPPING_LK1 (EXTERNAL_ID, ACTIVE, ENTITY)` — note `ENTITY_TYPE` is *not* in it, so
the C# gate's predicate is unindexed while the SP's is.

Related: `NB_NOTE_HDR.MEDICATION_REVIEW_STATUS` and `.OTC_MEDICATION` are the note-level attestation
flags, written only via `usp_NbNoteHdr_MedicationReviewStatus_Update` / legacy MyNotes.

## Not yet documented

Column-level detail for `STAGE_PATIENT_MEDICATION_DRFIRST` and `LAB_RESULT_DETAIL` is not filled in.
Add it with `dbq --schema mysql-prod.<TABLE>` as you work with each one.
