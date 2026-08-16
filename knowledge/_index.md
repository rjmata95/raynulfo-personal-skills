# Database knowledge index

What each alias has documented, and how fresh it is. **Read the relevant
`<alias>/_schema.md` and `<alias>/gotchas.md` before your first query against that alias.**

> **Structure only — never PHI.** This directory is git-tracked and intended to be shared
> with other teams. Treat it as publishable: field names, types, presence percentages, index
> definitions, and enum values are in scope; patient identifiers, names, and document values
> are not. The PROD tenant ID `5740b0c5-a442-4e04-b961-2a1a0b5dc399` is explicitly allowed —
> it identifies a tenant, not a person, and belongs in query guidance because most indexes
> are tenant-prefixed.

## Coverage

| Alias | Kind | Env | Schema | Gotchas | Last verified |
|---|---|---|---|---|---|
| `encounter` | mongo | prod | **collection** | yes | 2026-08-07 |
| `mysql-prod` | mysql | prod | **table sizes** + `BI_RITS` reco + encounter-medication trio + screening `SUBJECTIVE_TRAN`/`CLINICAL_TERMINOLOGY` | yes | 2026-08-15 |
| `medication` | mongo | prod | databases | yes | 2026-08-07 |
| `patient` | mongo | prod | databases | yes | 2026-08-07 |
| `practice-mgmt` | mongo | prod | databases | yes | 2026-08-07 |
| `tenant-mgmt` | mongo | prod | databases | yes | 2026-08-07 |
| `medication-nonprod` | mongo | nonprod | databases | yes | 2026-08-07 |
| `mysql-qa` | mysql | qa | — | — | **not verified** (ERROR 2059 — see below) |

### `mysql-qa` is not yet migrated

It is the one alias whose MCP server is still in place, because the CLI cannot reach it: the
QA server authenticates via PAM/LDAP and needs `mysql_clear_password` (ERROR 2059). Fix it in
a real terminal, then the MCP server can be removed:

```bash
dbq init --alias mysql-qa      # press [a] to enable cleartext + TLS, then [t] to test
dbq doctor                     # confirm it reports ok
claude mcp remove mysql-qa -s user
```

Details in `../skills/setting-up-dbq/references/troubleshooting.md`.

Legend: `—` not started · `databases` cluster inventory mapped, no field maps yet ·
`collection` at least one collection fully documented · `table sizes` inventory + size profile

Seed a new alias by copying `_TEMPLATE/` to `<alias>/` and filling it from
`dbq --schema <alias>.<collection>`. Update the row above when you do.

## Read this before your first query

**Every Mongo alias is a CLUSTER, not a database.** Each hosts many per-service databases
following the platform's CQRS split — `medication` alone has 20. There is no database named
`medication`, `patient`, or `encounter`.

```bash
dbq --collections <alias>                          # lists databases when none is selected
DBQ_DB=<database> dbq --collections <alias>        # then lists collections
```

Getting this wrong is quiet, not loud: querying a nonexistent database returns an empty result
with `ok: 1` and no error, which reads exactly like "no data found". This cost real debugging
time on 2026-08-07 and is why `default_db` is `-` for every Mongo cluster in the registry.

## Conventions worth knowing everywhere

- **Always filter production Mongo queries by `tenantId`.** PROD tenant
  `5740b0c5-a442-4e04-b961-2a1a0b5dc399`. Indexes are tenant-prefixed; omitting it turns an
  indexed lookup into a collection scan.
- **Prefer `<service>-query` over `<service>-cmd`.** `-query` is the read projection consumers
  actually use; `-cmd` is event-sourced aggregate state and an implementation detail.
- **Hyphenated names need bracket syntax.** `db["patient-prescription"]`, not
  `db.patient-prescription` — `-` is subtraction in JavaScript. Nearly every database name here
  is hyphenated.
- **`_id` type varies by collection.** It is a string UUID in some, a genuine `ObjectId` in
  others (confirmed `ObjectId` in `encounter-types`). Check with `dbq --schema` before building
  a lookup; guessing wrong matches nothing silently.
- **Nonprod tenant IDs differ from prod.** The prod tenant ID matches nothing in
  `medication-nonprod`.
- **Environments are not at parity.** `epd-review-service` exists only in nonprod;
  `patient-allergy-relay-uat` only in the prod medication cluster.
- **Mongo is the operational store; BIDW MySQL is ETL-fed and trails it.** Counts that
  disagree may be lag rather than a defect.
- **All aliases are read-only.** Writes go through GraphQL mutations so the Phoenix eventing
  engine emits domain events — see the `data-fix-scripts` skill.

## How to add knowledge

See `../skills/querying-databases/references/capturing-knowledge.md` for the entry format,
what is worth recording, and the PHI rule in full.
