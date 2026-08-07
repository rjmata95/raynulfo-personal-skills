# Capturing knowledge

The knowledge base is the reason this skill exists rather than being a bare CLI. A query you
run once is worth little; a rock you stop future agents tripping on is worth a lot.

## The PHI rule — read this first

**Record structure. Never record data.**

The knowledge base is git-tracked and intended to be shared with other teams. Treat it as
publishable.

| Record this | Never record this |
|---|---|
| Field names and paths | Real patient IDs, MRNs, member numbers |
| BSON/SQL types | Patient names, DOBs, addresses, phone numbers |
| Presence percentages (`sig: 82%`) | Actual `sig` text from a prescription |
| Index definitions and key order | Provider names, NPIs, DEA numbers |
| Enum values (`status: ACTIVE\|VOID\|EXPIRED`) | Copy-pasted documents or result rows |
| Row/document counts, cardinality | Free-text clinical notes |
| Relationships between collections | Any value that identifies a person |

**Explicitly allowed:** the PROD tenant ID `5740b0c5-a442-4e04-b961-2a1a0b5dc399`. It
identifies a tenant, not a person, and belongs in query guidance because most indexes are
tenant-prefixed.

When an example query needs an ID, use a placeholder: `{patientId: "<patientId>"}`.

If you are unsure whether something is PHI, leave it out and describe the shape instead:
"`identifiers[]` holds external MRNs keyed by `system`" tells the next agent everything
useful without a single real value.

## Two files per alias

### `_schema.md` — update in place

The stable map: collections, field shapes, indexes, relationships. Rewrite freely as
understanding improves. Generate the raw material with:

```bash
dbq --schema <alias>.<collection> 500
```

Then **curate** — do not paste 300 lines of raw output. Keep the fields someone will actually
query, note the ones that surprised you, drop the noise. A schema file nobody reads because
it is 2,000 lines long has failed.

Include for each documented collection:
- what one document represents, in a sentence
- the fields worth knowing, with type and presence
- indexes, with a note on which queries they serve
- how it joins to other collections/services

### `gotchas.md` — append only

The rocks. Newest at the top. Never rewrite a previous entry; if it turns out to be wrong,
append a correction that supersedes it.

Each entry:

```markdown
## YYYY-MM-DD — one-line summary

**Symptom:** what looked wrong, or what you expected and did not get.
**Cause:** what is actually going on.
**Handling:** what to do instead. A working query if there is one.
```

## What is worth an entry

Write one when any of these happens:

- A field is missing, null, or empty far more often than expected.
- A query is slow because an index does not exist, or exists with a key order that does not
  serve it.
- A collection has more than one document shape (schema drift, migrations, versioned writes).
- The same concept has different field names across collections or services.
- An enum has undocumented values, or values that appear only in old records.
- Counts differ between two sources that should agree.
- An environment behaves differently from another (nonprod lacks data, QA schema drifted).
- Something in the code's naming actively misleads you about what the data holds.

Do **not** write an entry for a one-off mistake of your own making (typo, wrong alias). Only
write what will still be true for the next agent.

## Working example

```markdown
## 2026-08-07 — `patientPrescription.pharmacyId` is null for office-dispensed meds

**Symptom:** Joining prescriptions to pharmacies dropped ~18% of rows for a practice, with
no obvious pattern by date or provider.

**Cause:** Office-dispensed medications carry no external pharmacy. `pharmacyId` is null by
design; the dispensing office is on `officeId` instead.

**Handling:** Treat null `pharmacyId` as "dispensed at office", not as missing data. Left-join
and branch on it:

    db.patientPrescription.aggregate([
      { $match: { tenantId: "5740b0c5-a442-4e04-b961-2a1a0b5dc399" } },
      { $addFields: { dispensedAtOffice: { $eq: ["$pharmacyId", null] } } }
    ])
```

Note what that entry does: it names the field, quantifies the surprise, explains the cause,
and hands over a runnable query — with no patient data anywhere in it.

## Keep the index current

`knowledge/_index.md` maps each alias to what is documented and when. Update it when you add
a new alias directory or make a substantial `_schema.md` change, so the next agent can tell
at a glance whether coverage is real or stale.
