---
alias: practice-mgmt
kind: mongo
env: prod
last_verified: 2026-08-07
---

# practice-mgmt — schema

Practice management cluster: appointments, providers, schedules, block types, offices, and the
Salesforce scheduling stream. The largest cluster by database count.

> **Structure only — never PHI.** Provider names, NPIs, and DEA numbers are identifying data —
> record field names and types, not values.

## This alias is a cluster, not a database

There is no database named `practice-mgmt`. Name the database explicitly:

```bash
dbq --collections practice-mgmt                        # lists databases
DBQ_DB=appointment-query dbq --collections practice-mgmt
```

## Databases

Verified 2026-08-07 via `listDatabases` — 20 databases.

| Database | Role |
|---|---|
| `appointment-cmd` | Appointments, write side (event-sourced) |
| `appointment-query` | Appointments read projection — **prefer for investigation** |
| `appointment-data-relay` | Appointment integration staging |
| `appointment-type-cmd` / `-query` | Appointment types |
| `provider-cmd` / `-query` | Providers |
| `provider-data-relay` | Provider integration staging |
| `provider-type-cmd` / `-query` | Provider types |
| `provider-schedule-query` | Provider schedule read projection |
| `schedule-template-cmd` | Schedule templates |
| `adhoc-scheduling-cmd` | Ad-hoc scheduling |
| `block-type-cmd` / `-query` | Schedule block types |
| `practice-management-cmd` / `-query` | Practice/office master data |
| `document-ingestion-service` | Document ingestion |
| `salesforce-scheduling-stream` | Salesforce scheduling integration stream |
| `practice-mgmt-tg1-prod` | Cluster-level/tenant-group store |

**CQRS split.** Prefer `<service>-query`; `-cmd` holds event-sourced aggregate state.
`-data-relay` is integration staging, useful when tracing what an external system received.

## Conventions

- **Always filter by `tenantId`.** PROD tenant: `5740b0c5-a442-4e04-b961-2a1a0b5dc399`.
- **Hyphenated names need bracket syntax** — `db["some-collection"]`.
- Office and provider identifiers cross-reference the BIDW warehouse (`mysql-prod`) —
  see `../mysql-prod/_schema.md`.
- **Read-only.** Writes go through GraphQL via the `data-fix-scripts` skill.

## Not yet documented

Collection-level field maps are not filled in. Derive one with:

```bash
DBQ_DB=appointment-query dbq --collections practice-mgmt
DBQ_DB=appointment-query dbq --schema practice-mgmt.<collection> 500
```
