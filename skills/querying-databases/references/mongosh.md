# mongosh patterns through `dbq`

`dbq <alias> '<expr>'` evaluates `<expr>` in `mongosh` with `db` already connected to the
alias's default database. Everything below is plain mongosh — no dbq-specific syntax.

## Always scope by tenant

```javascript
db.patientPrescription.countDocuments({ tenantId: "5740b0c5-a442-4e04-b961-2a1a0b5dc399" })
```

Most indexes are tenant-prefixed. Omitting `tenantId` turns an indexed lookup into a
collection scan against production. This is the most common performance mistake in this
codebase — do it once on a large collection and you will notice.

## Output is JSON

`dbq` runs mongosh with `--json=relaxed`, so output is parseable:

```bash
dbq patient 'db.patient.findOne({_id:"<id>"}, {firstName:1})' | jq .
```

`print()` writes raw lines instead, which is better for lists and progress:

```bash
dbq medication 'db.getCollectionNames().forEach(function (c) { print(c); })'
```

## Projections keep output small

Never return whole documents when you need three fields. It floods context and drags PHI into
the transcript for no reason.

```javascript
db.patientPrescription.find(
  { tenantId: "5740b0c5-a442-4e04-b961-2a1a0b5dc399", status: "ACTIVE" },
  { _id: 1, patientId: 1, pharmacyId: 1, writtenDate: 1 }
).limit(20)
```

## Counting and grouping

```javascript
// Count by status — cheap way to learn an enum's real values
db.patientPrescription.aggregate([
  { $match: { tenantId: "5740b0c5-a442-4e04-b961-2a1a0b5dc399" } },
  { $group: { _id: "$status", n: { $sum: 1 } } },
  { $sort: { n: -1 } }
])
```

`countDocuments()` is accurate but scans; `estimatedDocumentCount()` is instant but
collection-wide (ignores filters and tenant scoping). Use the estimate only for "is this
collection big".

## Check the index before writing the query

```javascript
db.patientPrescription.getIndexes()
```

Or `dbq --schema <alias>.<collection>`, which prints indexes alongside the field map.

Key **order** matters: an index on `{tenantId: 1, status: 1}` serves a query filtering both,
and one filtering `tenantId` alone, but not one filtering `status` alone.

## Explain when something is slow

```javascript
db.patientPrescription.find({ tenantId: "...", status: "ACTIVE" })
  .explain("executionStats").executionStats
```

Look at `totalDocsExamined` versus `nReturned`. A large gap means the index is not doing the
work. `COLLSCAN` in the winning plan means no index applied at all.

## Long or reusable queries go in a file

Quoting nested JS on one line gets unpleasant fast. Write it to scratch instead:

```bash
cat > "$(dbq scratch)/trace-rx.js" <<'EOF'
const TENANT = "5740b0c5-a442-4e04-b961-2a1a0b5dc399";
const rx = db.patientPrescription.findOne({ tenantId: TENANT, _id: "<id>" });
printjson({ found: !!rx, status: rx && rx.status, hasPharmacy: !!(rx && rx.pharmacyId) });
EOF

dbq --file medication "$(dbq scratch)/trace-rx.js"
```

Scratch is pruned after 7 days. Anything worth keeping belongs in a repo or in `knowledge/`.

## Cross-database in one connection

```bash
DBQ_DB=admin dbq medication 'db.runCommand({connectionStatus: 1})'
```

Or `db.getSiblingDB()` inside the expression:

```javascript
db.getSiblingDB("medication").patientPrescription.countDocuments({ tenantId: "..." })
```

## Gotchas

- **`ObjectId` vs string `_id`.** Collections in this platform commonly use string UUIDs, not
  `ObjectId`. Querying `ObjectId("...")` against a string `_id` silently matches nothing.
  Check `dbq --schema` for the `_id` type first.
- **Dates.** Stored as BSON dates; compare with `new Date("2026-01-01")`, not a string.
- **`null` vs missing.** `{field: null}` matches both explicit null and absent. Use
  `{field: {$type: "null"}}` for explicitly-null, `{field: {$exists: false}}` for absent.
- **`--json=relaxed` and large numbers.** Longs render as `{"$numberLong": "..."}`. Expect it
  when piping to `jq`.
- **Atlas private-link ports.** Endpoints resolve to non-standard ports (observed 1037–1045)
  via SRV. `dbq` always passes the SRV URI so this is handled — but never construct a
  `--host host:27017` invocation by hand; it will fail.
