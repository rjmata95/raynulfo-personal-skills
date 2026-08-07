---
alias: medication-nonprod
---

# medication-nonprod — gotchas

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

## 2026-08-07 — this alias is a cluster; no database matches the alias name

**Symptom:** `dbq medication-nonprod 'db.getCollectionNames()'` returns an empty list with `ok: 1` and no
error — indistinguishable from a permissions problem at first glance.

**Cause:** The alias connects to a *cluster* hosting many per-service databases. No database
named `medication-nonprod` exists, so `listCollections` legitimately succeeded against an empty namespace.

**Handling:** name the database explicitly. `dbq --collections medication-nonprod` with no database selected
lists the databases rather than silently returning nothing.

    DBQ_DB=<database> dbq --collections medication-nonprod
    dbq medication-nonprod 'db.getSiblingDB("<database>")["<collection>"].countDocuments({})'

## 2026-08-07 — hyphenated database and collection names break dot notation

**Symptom:** `db.some-collection.find()` errors or yields `NaN`.

**Cause:** `-` is subtraction in JavaScript, so `db.some-collection` parses as arithmetic.
Nearly every database in this cluster is hyphenated (`<service>-cmd`, `<service>-query`).

**Handling:** bracket syntax everywhere:

    db["some-collection"].countDocuments({ tenantId: "<tenantId>" })
    db.getSiblingDB("service-query")["some-collection"].findOne()

## 2026-08-07 — prefer the `-query` side over `-cmd`

**Symptom:** Documents in `<service>-cmd` have an unexpected shape — event envelopes or
aggregate internals rather than the entity you expected.

**Cause:** The platform is CQRS. `-cmd` is the event-sourced write model; `-query` is the read
projection that consumers actually read.

**Handling:** investigate against `-query` unless you specifically need aggregate or event
state. Treat `-cmd` shape as an implementation detail that can change without notice.
