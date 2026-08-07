---
alias: medication
kind: mongo
env: prod
last_verified: 2026-08-07
---

# medication — schema

Medication domain cluster: prescriptions, medication lists, pharmacies, allergies, internal
med orders, and the Rcopia/AllScripts integration stores. The busiest cluster for eRx work.

> **Structure only — never PHI.** Field names, types, presence percentages, index
> definitions, and enum values belong here. Real patient identifiers, prescription `sig`
> text, and document values do not.

## This alias is a cluster, not a database

There is no database named `medication`. Name the database explicitly:

```bash
dbq --collections medication                                # lists databases
DBQ_DB=patient-prescription-query dbq --collections medication
```

## Databases

Verified 2026-08-07 via `listDatabases` — 20 databases.

| Database | Role |
|---|---|
| `patient-prescription-cmd` | Prescriptions, write side (event-sourced aggregate) |
| `patient-prescription-query` | Prescriptions, read projection — **prefer for investigation** |
| `patient-medication-list-cmd` | Patient medication list, write side |
| `patient-medication-query` | Patient medication read projection |
| `patient-medication-data-relay` | Relay/integration staging for medications |
| `pharmacy-cmd` | Pharmacy master data, write side |
| `pharmacy-query` | Pharmacy read projection |
| `patient-pharmacy-list-cmd` | Patient↔pharmacy association, write side |
| `patient-pharmacy-query` | Patient pharmacy read projection |
| `patient-allergy-cmd` | Allergies, write side |
| `patient-allergy-query` | Allergy read projection |
| `patient-allergy-data-relay` | Allergy relay staging |
| `patient-allergy-relay-uat` | **UAT data in the prod cluster** — see gotchas |
| `internal-med-orders-data-relay` | Internal med orders relay |
| `asmeds-integration-cmd` / `-query` | AS/Meds integration |
| `rcopia-integration-cmd` / `-query` | Rcopia (DrFirst) integration |
| `medication-query` | Medication reference/read model |
| `medication-tg1-prod` | Cluster-level/tenant-group store |

**CQRS split.** `<service>-cmd` is the event-sourced write side; `<service>-query` is the read
projection. **Prefer `-query` for investigation** — it is what consumers actually read, and
its shape is stable. `-cmd` holds aggregate state and is an implementation detail.

**`-data-relay`** databases are integration staging, not domain truth. Use them when tracing
why an external system did or did not receive something.

## Conventions

- **Always filter by `tenantId`.** PROD tenant: `5740b0c5-a442-4e04-b961-2a1a0b5dc399`.
  Indexes are tenant-prefixed; omitting it turns an indexed lookup into a collection scan on
  collections that can be very large.
- **Hyphenated names need bracket syntax** — `db["some-collection"]`, since `-` is
  subtraction in JavaScript. This applies to nearly every database name here too.
- **Writes go through GraphQL**, never here. This cluster is read-only in `dbq`; the
  `data-fix-scripts` skill owns mutations via GraphQL so Phoenix emits proper domain events.

## Not yet documented

Collection-level field maps are not filled in yet. Derive one and add it here:

```bash
DBQ_DB=patient-prescription-query dbq --collections medication
DBQ_DB=patient-prescription-query dbq --schema medication.<collection> 500
```

Curate the output — keep the fields someone will query, note the surprises, drop the noise.
See `../../skills/querying-databases/references/capturing-knowledge.md`.
