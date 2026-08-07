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
