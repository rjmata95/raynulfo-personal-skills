---
alias: encounter
---

# encounter — gotchas

Append-only. Newest entry at the top. Never rewrite a previous entry — if one turns out to be
wrong, append a correction that supersedes it and say so.

> **Structure only — never PHI.** Describe shapes and causes, not patient data.

Entry format:

```markdown
## YYYY-MM-DD — one-line summary

**Symptom:** what looked wrong, or what you expected and did not get.
**Cause:** what is actually going on.
**Handling:** what to do instead. Include a working query if there is one.
```

---

## 2026-08-07 — hyphenated collection names break dot notation

**Symptom:** `db.encounter-types.countDocuments({})` returns a JavaScript error or `NaN`
rather than a count.

**Cause:** `db.encounter-types` parses as `db.encounter` minus `types` — hyphens are
subtraction in JavaScript. This affects most collections in this cluster, and every
`<service>-cmd` / `<service>-query` database name.

**Handling:** use bracket syntax for any hyphenated name:

    db["encounter-types"].countDocuments({ tenantId: "5740b0c5-a442-4e04-b961-2a1a0b5dc399" })

## 2026-08-07 — `_id` is an ObjectId here, not a string UUID

**Symptom:** Expected string UUID `_id` values based on general platform guidance; sampling
`encounter-types` showed `ObjectId` in 100% of 50 documents.

**Cause:** The `_id` type is per-collection, not platform-wide. Some collections use string
UUIDs, this one uses genuine ObjectIds, and the business identifier is a separate field
(`encounterTypeId`).

**Handling:** check the `_id` type with `dbq --schema <alias>.<collection>` before
constructing a lookup. For this collection, query by the natural key instead — it is indexed
as `uniqueness` and is what other services reference:

    db["encounter-types"].findOne({ tenantId: "<tenantId>", encounterTypeId: "<id>" })

## 2026-08-07 — an alias is a cluster; there is no database matching the alias name

**Symptom:** `dbq encounter 'db.getCollectionNames()'` returned an empty list with `ok: 1`
and no error — looking exactly like a permissions problem.

**Cause:** The alias connects to a *cluster* hosting many per-service databases
(`encounter-type-cmd`, `encounter-type-query`, `screening-service`). No database named
`encounter` exists, so `listCollections` legitimately succeeded against an empty namespace.

**Handling:** name the database explicitly. `dbq --collections <alias>` with no database
selected now lists the databases instead of silently returning nothing.

    DBQ_DB=encounter-type-query dbq --collections encounter
    dbq encounter 'db.getSiblingDB("encounter-type-query")["encounter-types"].countDocuments({})'

This was the original cause of `default_db` being wrong in the shipped registry; it is now
`-` for every Mongo cluster so a missing database cannot be mistaken for an empty result.
