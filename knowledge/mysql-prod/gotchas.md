---
alias: mysql-prod
---

# mysql-prod — gotchas

Append-only. Newest entry at the top. Never rewrite a previous entry — if one turns out to be
wrong, append a correction that supersedes it and say so.

> **Structure only — never PHI.** Describe shapes and causes, not row values.

Entry format:

```markdown
## YYYY-MM-DD — one-line summary

**Symptom:** what looked wrong, or what you expected and did not get.
**Cause:** what is actually going on.
**Handling:** what to do instead. Include a working query if there is one.
```

---

## 2026-08-13 — `NB_MEDICATION_STATE.CREATION_DATE` is the note's VISIT_DATE, not the write time

**Symptom:** `MAX(CREATION_DATE)` values are all exactly midnight (`2026-08-13 00:00:00`), and a
"when was this last written" answer disagreed with a `VISIT_DATE`-based one by two months.

**Cause:** the writer sets it from the note, not the clock —
`mynotes-api:CTech.MyNotes.Infrastructure/Implementations/MedicationsRepository.cs:65,70`:
`SET @visitDate := (SELECT VISIT_DATE FROM NB_NOTE_HDR WHERE NOTE_ID = @noteId)` … `VALUES(…,@visitDate)`.
`VISIT_DATE` is a `date`, so it widens to midnight. There is **no true insert timestamp** on this table.

**Handling:** treat `CREATION_DATE` as an encounter date. For "when did this actually get written",
use `AUDIT_LOG` (the same batch writes `TABLE_NAME='NB_MEDICATION_STATE'` with `TIMESTAMP=NOW()`),
or aggregate over the monotonic PK `MED_STATE_ID`. Also beware **orphaned rows**: some
`NB_MEDICATION_STATE.NOTE_ID` no longer join to `NB_NOTE_HDR` (deleted training notes), so an inner
join silently drops them and a `LEFT JOIN` is what reveals them. When a date boundary looks odd,
check `CREATED_BY` for `MD_Training*` accounts before believing it.

---

## 2026-08-13 — only 39 of 187 active practices use MyNotes at all; join via `OFFICE.PRACTICE_ID`

**Symptom:** wanted to compare ePrescribe-enrolled vs non-enrolled clinician behavior and assumed
non-enrolled was the majority path (148 of 187 practices). It has **zero** traffic.

**Cause:** `NB_MEDICATION_STATE` rows classified by whether the note's practice is in
`VENDOR_CHENMED_MAPPING_LK` (`ENTITY_TYPE='PRACTICE' AND ACTIVE=1`) come **100% from the 39 enrolled
practices, every year from 2018 to 2026** — the non-enrolled 148 are the dormant legacy affiliate/IPA
network (individual physician names, outside groups). Only 22 of the 39 were active in a given week.
The 7 newest DSMC markets (ids 10192-10198: Clarksville, Dayton, Daytona, Fayetteville, Flint,
Indianapolis, Toledo) are also non-enrolled and write nothing — they launched on NextGen, never on
legacy MyNotes. That is why enrolment froze on 2022-10-04.

**Handling:** `NB_NOTE_HDR` has `OFFICE_ID` but no practice; join `OFFICE.PRACTICE_ID`. **`USERS` has
no practice column at all**, so you cannot reproduce the real gate from SQL — the gate is
`user.PracticeId` from the session (`mynotes-api:…/UsersRepository.cs:127`). State the office-practice
join as a proxy. Note `ENTITY` and `ENTITY_TYPE` are two independent columns that happen to agree on
all rows today; the C# gate reads `ENTITY_TYPE`, the stored proc reads `ENTITY`.

    SELECT CASE WHEN v.EXTERNAL_ID IS NOT NULL THEN 'enrolled' ELSE 'not' END side, COUNT(*)
    FROM NB_NOTE_HDR h JOIN OFFICE o ON o.OFFICE_ID=h.OFFICE_ID
    LEFT JOIN (SELECT DISTINCT EXTERNAL_ID FROM VENDOR_CHENMED_MAPPING_LK
               WHERE ENTITY_TYPE='PRACTICE' AND ACTIVE=1 AND EXTERNAL_ID IS NOT NULL) v
           ON v.EXTERNAL_ID=o.PRACTICE_ID
    JOIN NB_MEDICATION_STATE s ON s.NOTE_ID=h.NOTE_ID
    WHERE h.VISIT_DATE >= '2026-08-06' GROUP BY 1;

---

## 2026-08-13 — `PAT_CHECKOUT_CARE_INTERVENTION` checklist flags are `bit(1)`; CAST them or you get binary

**Symptom:** `SELECT MEDICATION_REVIEWED … GROUP BY` returned unreadable binary blobs.

**Cause:** the checklist columns are `bit(1)`, not `tinyint`. Same for most `NB_NOTE_HDR` flags
(`SIGNED`, `CANCELLED`, `MEDICATION_REVIEW_STATUS`, `OTC_MEDICATION`).

**Handling:** `CAST(col AS UNSIGNED)` in the select list, and compare with `= b'1'` / `= b'0'` in the
predicate. ~14.5M rows, only a PK and an FK index on `PAT_CHECKOUT_INFO_ID`, so a full GROUP BY scan
runs but takes a while — no date column, join `PAT_CHECKOUT_INFO` if you need time-bounding. Useful
finding for anyone auditing it: **every non-null row has `MEDICATION_REVIEWED = ALLERGY_REVIEWED = 1`**
(14,130,335 rows), plus 370,803 rows with both NULL, and **not one row where they differ** — the UI
hard-blocks save unless both are checked.

---

## 2026-08-13 — `NB_MEDICATION_STATE.CREATION_DATE` is the visit date, not the write time

**Symptom:** a "rows written per day" time series looks plausible but does not line up with
application traffic, and back-dated encounters appear to write into the past.

**Cause:** the insert stored procedure sets `CREATION_DATE` from `NB_NOTE_HDR.VISIT_DATE`, not
`NOW()`. It is a **clinical** date, not an audit timestamp. There is no true write-time column.

**Handling:** never call it "written on". For same-day documentation the two nearly coincide, so it is
fine for volume estimates — say "visit-dated", not "written". If you need real write ordering, use the
monotonic PK `MED_STATE_ID`. Consequence for archaeology: a status that stops appearing tells you when
*visits* stopped carrying it, and a gradual month-over-month decay can reflect a client-side
regression rolling out rather than a deploy.

Worth knowing about the enum while you are here: **`Discontinued` has not been written by a real
clinician since April 2020** (126,555 rows total, last real 2020-06-19 by visit date; the few later
rows are training accounts on orphaned `NOTE_ID`s). The other seven values are all still written
daily. `NB_MEDICATION_STATE_LK` is also **missing id `5`** (a row was deleted) and stores
`'Taking as needed'` where the application's JS array says `'Taking As Needed'` — benign only because
MySQL collation is case-insensitive, and a trap if you ever compare these strings outside MySQL.

---

## 2026-08-13 — no date index on `PAT_MEDICATIONS` / `NB_MEDICATION_STATE`; aggregate over the PK instead

**Symptom:** `SELECT … FROM PAT_MEDICATIONS WHERE CREATED_DATE >= '2025-08-01' GROUP BY …` did not
return in 120s. `PAT_MEDICATIONS` is ~76 M rows / 18 GB.

**Cause:** neither table indexes its creation date usefully. `PAT_MEDICATIONS` indexes
`PATIENT_ID`, `MED_NAME`, `MED_NAME_ID`, `ENCOUNTER_RCOPIAID` — not `CREATED_DATE`.
`NB_MEDICATION_STATE` (~93 M rows) has `MED_CREATION_index` on **`(MED_STATE, CREATION_DATE)`** —
leading column is the status string, so a bare `CREATION_DATE` predicate cannot use it.

**Handling:** both tables have monotonic auto-increment PKs, so "recent activity" questions are
answerable by aggregating over a PK-descending subquery — seconds instead of minutes. Sample size is
your date window; widen it until the oldest date in the result predates what you care about.

    SELECT SOURCE, CREATED_BY, DATE(CREATED_DATE) d, COUNT(*) n
    FROM (SELECT SOURCE, CREATED_BY, CREATED_DATE
          FROM PAT_MEDICATIONS ORDER BY MEDICATION_ID DESC LIMIT 20000) t
    GROUP BY SOURCE, CREATED_BY, d ORDER BY d DESC, n DESC;

State this as a *sample* in any finding — it is not a complete date-range count.

---

## 2026-08-13 — `usp_DrFirst_Medication_PreviewSignOff_Get` reads no DrFirst table; `PAT_MEDICATIONS` is written by NextGen

**Symptom:** the SP name, and legacy MyNotes code comments, say the encounter medication list is
DrFirst-sourced. Reading the data suggests otherwise, and the two readings look contradictory.

**Cause:** the name is vestigial (EPRE-1178, 2019) and records who fed the table then. The SP reads
`PAT_MEDICATIONS`, `NB_MEDICATION_STATE(_LK)`, `NB_NOTE_HDR`, `PATIENT`,
`VENDOR_CHENMED_MAPPING_LK` — no DrFirst staging table. `PAT_MEDICATIONS` is now written by the
NextGen `patient-medication-data-relay` via `usp_PatMedications_Upsert` as service account
`NEXTGEN_SERVICE`. `STAGE_PATIENT_MEDICATION_DRFIRST` (13.4 M rows) is the *actual* DrFirst ETL
staging table and is a different thing.

**Handling:** read `PAT_MEDICATIONS.SOURCE` + `CREATED_BY` to tell writers apart —
`EXTERNAL` / `EXT(MODIF)` / `EXT(DEL)` under `NEXTGEN_SERVICE` are NextGen relay writes;
`INTERNAL` under an individual username is the in-house dispensary (ASMeds) path. Both meanings of
"internal medication" collide in the codebase; this column disambiguates them. Never infer
provenance from an object's name in this schema.

---

## 2026-08-13 — `VENDOR_CHENMED_MAPPING_LK` has both `ENTITY` and `ENTITY_TYPE`; they agree for PRACTICE but callers disagree

**Symptom:** two callers gate the same "is this practice ePrescribe-enabled" decision on **different
columns** — legacy C# on `ENTITY_TYPE = 'PRACTICE'`, `usp_DrFirst_Medication_PreviewSignOff_Get` on
`ENTITY = 'PRACTICE'`. Both columns exist and are independent `varchar(50)`s.

**Cause:** historical drift. `usp_VENDOR_CHENMED_MAPPING_LK_Insert` treats them as independent
inputs, so nothing enforces agreement.

**Handling:** verified 2026-08-13 across all 42,529 rows — every row with `ENTITY='PRACTICE'` also
has `ENTITY_TYPE='PRACTICE'` (39 active), and no row holds one without the other, so the gates agree
today. Treat it as a latent footgun for future inserts, not a live defect. Useful shape: `ENTITY` ∈
`{USERS, OFFICE, PRACTICE}` pairs with `ENTITY_TYPE` ∈ `{STAFF, PROVIDER, LOCATION, PRACTICE}`;
`VENDOR` is `'DRFIRST'` on 100% of rows and is the only vendor present. Practice enrollment is
frozen — newest `PRACTICE` row created 2022-10-04.

    SELECT ENTITY, ENTITY_TYPE, VENDOR, ACTIVE, COUNT(*) n
    FROM VENDOR_CHENMED_MAPPING_LK GROUP BY 1,2,3,4 ORDER BY n DESC;

---

## 2026-08-13 — creation/update column names differ between `PAT_MEDICATIONS` and `NB_MEDICATION_STATE`

**Symptom:** `ERROR 1054 Unknown column 'CREATED_DATE'` when reusing a `PAT_MEDICATIONS` query
shape against `NB_MEDICATION_STATE`.

**Cause:** same concept, different names. `PAT_MEDICATIONS` uses
`CREATED_BY/CREATED_DATE/UPDATED_BY/UPDATED_DATE`; `NB_MEDICATION_STATE` uses
`CREATED_BY/CREATION_DATE/UPDATED_BY/UPDATION_DATE`. The `NB_*` progress-note tables generally
prefer `CREATION_DATE`/`UPDATION_DATE`.

**Handling:** run `dbq --schema mysql-prod.<TABLE>` before porting a query between a `PAT_*` and an
`NB_*` table. Also note `NB_MEDICATION_STATE` has `NOTE_ID` and **no `PATIENT_ID`** — a row cannot
exist outside a progress note, so every question about it is encounter-scoped. `MED_STATE` stores the
human-readable description string (`'Taking As Directed'`, `'Patient Did Not Bring'`, …), not the
code; `MED_STATE_CODE` holds the code and resolves via `NB_MEDICATION_STATE_LK`.

---

## 2026-08-12 — `BI_RITS.EPD_MEDICATION_CLINICAL_SUMMARY_RECOMMENDATION` has no PK; Snowflake landing lags the live table

**Symptom:** `LANDING_SHARE.BI_RITS.EPD_MEDICATION_CLINICAL_SUMMARY_RECOMMENDATION` row count disagrees with MySQL prod (603 vs 615 on 2026-08-12 17:45). A naive `SELECT *` from the share also fails — it is not the 9-column reco shape.

**Cause:** Live BIDW is MySQL `BI_RITS.EPD_MEDICATION_CLINICAL_SUMMARY_RECOMMENDATION` (9 columns, **no primary key, no index**, `EVIDENCE` JSON, `ACTIVE` tinyint). A celery `mysql_to_snowflake` job full-refreshes it into `LANDING_SHARE` as a file-ingest table (`ROWDATA` + `LINEAGE`), cron `0 5 * * *`, `swap_method=delete`. Same-day writes by the upstream Snowflake engine are in MySQL immediately and in landing only after the next 05:00 ingest. `UPDATED_DATE` on every MySQL row is the full-refresh stamp, not the original Snowflake update.

**Handling:** treat MySQL as source of truth for "what RITS sees now"; treat landing as this morning's snapshot. Qualify the table (`BI_RITS.…`) — the alias default database is `DASHBOARD_PROD`. Count before copying:

    SELECT COUNT(*) n, COUNT(DISTINCT PAT_CATEGORY_ID) distinct_pk,
           MAX(CREATED_DATE) max_created, MAX(UPDATED_DATE) max_updated
    FROM BI_RITS.EPD_MEDICATION_CLINICAL_SUMMARY_RECOMMENDATION;

Landing copy into Snowflake must project `ROWDATA:` fields, not `SELECT *`. If MySQL has IDs landing lacks, check those orders' `STATUS` in Snowflake `PATIENT_ORDERS_V` before assuming the snapshot is a safe seed.

## 2026-08-07 — `PROCESS_EXCEPTION_LOG` is ~100 KB per row (353 GB on 3.5 M rows)

**Symptom:** A modest-looking `SELECT * FROM PROCESS_EXCEPTION_LOG LIMIT 100` returns an
enormous result and can appear to hang.

**Cause:** The table stores large payloads or stack traces per row. It is 353 GB of data on
only 3.5 M rows — roughly 100 KB per row, by far the highest ratio in `DASHBOARD_PROD`.

**Handling:** never `SELECT *` here. Project the columns you need and keep `LIMIT` small.
Check size before exploring any unfamiliar table:

    SELECT table_rows, ROUND(data_length/1024/1024) AS data_mb,
           ROUND(data_length/GREATEST(table_rows,1)/1024) AS avg_kb_per_row
    FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'PROCESS_EXCEPTION_LOG';

## 2026-08-07 — manual `_bkp` copies sit alongside live staging tables

**Symptom:** Two similar tables (`STAGE_PATIENT_MEDICATION_DRFIRST` at 13.4 M rows and
`STAGE_PATIENT_MEDICATION_DRFIRST_bkp56` at 3.3 M) both look plausible.

**Cause:** Manual backup copies were taken during past work and never removed. They are
frozen snapshots, not live data.

**Handling:** confirm which table the ETL currently writes before drawing conclusions. Treat
any `_bkp*` suffix as stale. Check recency rather than assuming:

    SELECT table_name, table_rows, update_time
    FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name LIKE 'STAGE_PATIENT_MEDICATION_DRFIRST%';

## 2026-08-07 — the QA server's default database is also named `DASHBOARD_PROD`

**Symptom:** Row counts from `mysql-qa` look wrong for production, or vice versa — the
database name in the prompt gives no clue which environment you are in.

**Cause:** Both the prod (BIDW) and QA (DASH) servers expose a schema called
`DASHBOARD_PROD`. The name does not indicate the environment; the **alias** does.

**Handling:** trust the alias, not the schema name. `dbq --list` shows `env` per alias.
Confirm mid-session with:

    dbq mysql-prod 'SELECT @@hostname'
