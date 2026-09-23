---
alias: <alias>
kind: <mongo|mysql|postgres>
env: <prod|nonprod|dev|qa|local>
last_verified: YYYY-MM-DD
---

# <alias> — schema

<One or two sentences: what domain this database owns, and which services write to it.>

> **Structure only — never PHI.** Field names, types, presence percentages, index
> definitions, and enum values belong here. Real patient identifiers, names, dates of birth,
> and document values do not. Use `<placeholder>` in example queries.

## Collections / tables

| Name | Purpose | Docs/rows (approx) | Documented below |
|---|---|---|---|
| `<name>` | <what one record represents> | ~<n> | yes |

---

## `<collectionName>`

<What a single document/row represents, in one sentence.>

Generated with `dbq --schema <alias>.<collectionName> 500` on YYYY-MM-DD, then curated.

| Field | Type | Presence | Notes |
|---|---|---|---|
| `_id` | string (UUID) | 100% | Not an ObjectId — do not wrap in `ObjectId()` |
| `tenantId` | string | 100% | Always filter on this; indexes are tenant-prefixed |
| `<field>` | <type> | <n>% | <what it means, gotchas, enum values> |

### Indexes

| Name | Key | Serves |
|---|---|---|
| `<name>` | `{tenantId: 1, <field>: 1}` | <which queries> |

### Relationships

- `<field>` → `<other collection or service>.<field>`
- <note any join that is not obvious from field names>

### Example queries

```javascript
// <what this answers>
db.<collectionName>.countDocuments({ tenantId: "5740b0c5-a442-4e04-b961-2a1a0b5dc399" })
```
