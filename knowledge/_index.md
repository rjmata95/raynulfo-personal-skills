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
| `medication` | mongo | prod | — | — | — |
| `patient` | mongo | prod | — | — | — |
| `encounter` | mongo | prod | — | — | — |
| `practice-mgmt` | mongo | prod | — | — | — |
| `tenant-mgmt` | mongo | prod | — | — | — |
| `medication-nonprod` | mongo | nonprod | — | — | — |
| `mysql-prod` | mysql | prod | — | — | — |
| `mysql-qa` | mysql | qa | — | — | — |

Legend: `—` not started · `partial` some collections · `yes` the collections that matter

Seed a new alias by copying `_TEMPLATE/` to `<alias>/` and filling it from
`dbq --schema <alias>.<collection>`. Update the row above when you do.

## Conventions worth knowing everywhere

- **Always filter production Mongo queries by `tenantId`.** Indexes are tenant-prefixed;
  omitting it turns an indexed lookup into a collection scan.
- **`_id` is usually a string UUID, not an `ObjectId`.** Wrapping in `ObjectId()` silently
  matches nothing. Confirm per collection with `dbq --schema`.
- **Mongo is the operational store; BIDW MySQL is ETL-fed and trails it.** Counts that
  disagree may be lag rather than a defect.
- **All eight aliases are read-only.** Writes go through GraphQL mutations so the Phoenix
  eventing engine emits domain events — see the `data-fix-scripts` skill.

## How to add knowledge

See `../skills/querying-databases/references/capturing-knowledge.md` for the entry format,
what is worth recording, and the PHI rule in full.
