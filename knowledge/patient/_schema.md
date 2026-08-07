---
alias: patient
kind: mongo
env: prod
last_verified: 2026-08-07
---

# patient — schema

Patient domain cluster: demographics, preferences, badges, insurance eligibility, EDI files,
phone messages, and the Credo document service.

> **Structure only — never PHI.** This cluster holds the most sensitive data in the platform.
> Record field names, types, presence percentages, and index definitions. **Never** record
> patient identifiers, names, dates of birth, addresses, phone numbers, or document values.
> Use `<patientId>` placeholders in example queries.

## This alias is a cluster, not a database

There is no database named `patient`. Name the database explicitly:

```bash
dbq --collections patient                              # lists databases
DBQ_DB=patient-demographic-query dbq --collections patient
```

## Databases

Verified 2026-08-07 via `listDatabases` — 15 databases.

| Database | Role |
|---|---|
| `patient-demographic-cmd` | Demographics, write side (event-sourced) |
| `patient-demographic-query` | Demographics read projection — **prefer for investigation** |
| `patient-demographic-drs` | Demographics DRS store |
| `patient-demographic-drs-uat` | **UAT data in the prod cluster** — see gotchas |
| `patient-preferences-cmd` / `-query` | Patient preferences |
| `patient-badges` | Patient badges (see `legacy-clinical-apps/top40-badge-lineage.md`) |
| `insurance-eligibility-check-cmd` | Eligibility checks |
| `edi-270-file-cmd` | EDI 270 (eligibility request) files |
| `edi-271-file-cmd` | EDI 271 (eligibility response) files |
| `patient-medicare-id-legacy-resolver` | Legacy Medicare ID resolution |
| `phone-message-cmd` | Phone messages |
| `phone-message-legacy-resolver` | Legacy phone message resolution |
| `credo-document-service` | Credo document storage |
| `patient-tg1-prod` | Cluster-level/tenant-group store |

**CQRS split.** Prefer `<service>-query` for investigation; `-cmd` holds event-sourced
aggregate state.

## Conventions

- **Always filter by `tenantId`.** PROD tenant: `5740b0c5-a442-4e04-b961-2a1a0b5dc399`.
- **Project narrowly.** Never `find()` whole documents here — it drags PHI into the transcript
  for no reason. Select only the fields you need.
- **Hyphenated names need bracket syntax** — `db["some-collection"]`.
- **Read-only.** Writes go through GraphQL via the `data-fix-scripts` skill.

## Not yet documented

Collection-level field maps are not filled in. Derive one with:

```bash
DBQ_DB=patient-demographic-query dbq --collections patient
DBQ_DB=patient-demographic-query dbq --schema patient.<collection> 500
```

**When documenting this cluster, record the field map only** — no sample values. A field named
`ssn` at 94% presence is useful knowledge; an actual SSN is a breach.
