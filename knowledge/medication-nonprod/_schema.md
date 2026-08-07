---
alias: medication-nonprod
kind: mongo
env: nonprod
last_verified: 2026-08-07
---

# medication-nonprod — schema

The medication cluster in **NONPROD**. Same service topology as `medication`, different data.

> **Structure only — never PHI.** Nonprod may contain copied or synthetic patient data; treat
> it with the same care as prod.

## Use this one for experiments

This is the safest cluster to explore against: same shapes as the prod medication cluster,
without querying production. Prefer it when you are learning a collection's structure and do
not need real data.

Note it is still registered `ro` — writes go through GraphQL regardless of environment.

## Databases

Verified 2026-08-07 via `listDatabases` — 20 databases, mirroring prod:

`asmeds-integration-cmd`, `asmeds-integration-query`, `epd-review-service`,
`internal-med-orders-data-relay`, `medication-query`, `medication-tg1-nonprod`,
`patient-allergy-cmd`, `patient-allergy-data-relay`, `patient-allergy-query`,
`patient-medication-data-relay`, `patient-medication-list-cmd`, `patient-medication-query`,
`patient-pharmacy-list-cmd`, `patient-pharmacy-query`, `patient-prescription-cmd`,
`patient-prescription-query`, `pharmacy-cmd`, `pharmacy-query`, `rcopia-integration-cmd`,
`rcopia-integration-query`

### Differences from prod

| Present here | Present in prod |
|---|---|
| `epd-review-service` | — |
| — | `patient-allergy-relay-uat` |
| `medication-tg1-nonprod` | `medication-tg1-prod` |

`epd-review-service` exists only in nonprod, so EPD review work cannot be traced in the prod
cluster. Do not assume database parity between environments.

## Conventions

- **Tenant IDs differ from prod.** The prod tenant `5740b0c5-…` will not match anything here.
  Look up the nonprod tenant before filtering, or you will get empty results that look like
  missing data.
- **Hyphenated names need bracket syntax** — `db["some-collection"]`.
- Prefer `<service>-query` over `-cmd`.

## Not yet documented

Collection-level field maps are not filled in. Because shapes mirror prod, documenting a
collection here is a safe way to build knowledge that also applies to `medication`:

```bash
DBQ_DB=patient-prescription-query dbq --collections medication-nonprod
DBQ_DB=patient-prescription-query dbq --schema medication-nonprod.<collection> 500
```

If you confirm a shape is identical in both, note that in the prod file too.
