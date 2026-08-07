---
alias: mysql-prod
kind: mysql
env: prod
last_verified: 2026-08-07
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

## Not yet documented

Column-level detail for the tables that matter most (`PAT_MEDICATIONS`,
`STAGE_PATIENT_MEDICATION_DRFIRST`, `LAB_RESULT_DETAIL`) is not filled in. Add it with
`dbq --schema mysql-prod.<TABLE>` as you work with each one.
