---
alias: encounter
kind: mongo
env: prod
last_verified: 2026-08-07
---

# encounter — schema

Encounter domain cluster. The smallest of the six Mongo clusters: encounter type
reference data and the screening service.

> **Structure only — never PHI.** Field names, types, presence percentages, index
> definitions, and enum values belong here. Real patient identifiers, names, and document
> values do not.

## This alias is a cluster, not a database

`dbq` connects to the cluster; you must name the database. There is no database called
`encounter`.

```bash
dbq --collections encounter                       # lists databases
DBQ_DB=encounter-type-query dbq --collections encounter
```

## Databases

Verified 2026-08-07 via `listDatabases`.

| Database | Role |
|---|---|
| `encounter-type-cmd` | Write side (CQRS command model) |
| `encounter-type-query` | Read side — query this for reporting/investigation |
| `screening-service` | Screening service store |

**CQRS split.** Most services here follow `<service>-cmd` (writes, event-sourced) and
`<service>-query` (read projections). **Prefer `-query` for investigation** — it is the
projection consumers actually read. `-cmd` holds the aggregate/event state and its shape is
an implementation detail of the service.

---

## `encounter-types` (in `encounter-type-query`)

One document per encounter type, per tenant. Reference data — small and stable.

Verified 2026-08-07: **429 documents**, 50 sampled via `dbq --schema`.

| Field | Type | Presence | Notes |
|---|---|---|---|
| `_id` | **ObjectId** | 100% | Genuinely an ObjectId here — see gotchas |
| `tenantId` | string | 100% | Always filter on this |
| `encounterTypeId` | string | 100% | Business identifier, distinct from `_id` |
| `name` | string | 100% | Display name |
| `purpose` | string | 100% | |
| `driverEncounter` | string | 100% | |
| `encounterTypeIntegration` | string | 100% | |
| `associatedProviderTypes` | array | 100% | Provider types this applies to |
| `isActive` | boolean | 100% | |
| `isDeleted` | boolean | 100% | Soft delete — filter it out |
| `createdAt` | date | 100% | |

Every sampled field was present in 100% of documents, which is unusual and worth knowing:
this collection is well-populated reference data, not sparse event output.

### Indexes

| Name | Key | Serves |
|---|---|---|
| `_id_` | `{_id: 1}` | Primary |
| `uniqueness` | `{tenantId: 1, encounterTypeId: 1}` | The natural key — best lookup path |
| `tenantId` | `{tenantId: 1}` | Tenant scans |
| `encounterTypeId` | `{encounterTypeId: 1}` | Lookup without tenant |
| `name` | `{name: 1}` | Name lookup |
| `associatedProviderTypes` | `{associatedProviderTypes: 1}` | Multikey |
| `createdAt` / `updatedAt` | single field | Time ranges |
| `isDeleted` / `isActive` | single field | Status filters |

`updatedAt` is indexed but did not appear in the 50-document sample — so it is written by
some code paths and not others. Do not assume it exists on every document.

### Example queries

```javascript
// Active, non-deleted types for a tenant — uses the uniqueness index prefix
DBQ_DB=encounter-type-query
db["encounter-types"].find(
  { tenantId: "5740b0c5-a442-4e04-b961-2a1a0b5dc399", isActive: true, isDeleted: false },
  { encounterTypeId: 1, name: 1, purpose: 1 }
)
```

Note the bracket syntax: `encounter-types` contains a hyphen, so `db.encounter-types` would
parse as subtraction. Use `db["encounter-types"]`.
