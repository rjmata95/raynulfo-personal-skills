---
name: querying-databases
description: Query MongoDB and MySQL through the `dbq` CLI instead of per-database MCP servers. Use whenever you need to read from a database — investigate data, check a collection shape, count records, verify a fix, trace an ID across services, or answer "what does this table look like". Also use when a user names a database domain (medication, patient, encounter, practice-mgmt, tenant-mgmt) or asks about prescriptions, pharmacies, offices, providers, tenants, or dashboard/BIDW reporting data. Covers reads only — writes go through GraphQL via the data-fix-scripts skill.
---

# Querying databases with `dbq`

One CLI for every database. Replaces the per-database MCP servers that used to cost ~128
tool schemas of context in every session.

## The two rules

**1. Read `knowledge/<alias>/` before your first query against an alias.**
Someone already mapped that collection and hit its gotchas. Reading first is cheaper than
rediscovering.

**2. Append what you learn.**
Found a field shape, a surprising null, a missing index, a naming quirk? Write it down.
This is the whole point — future agents stop tripping on the same rocks. See
`references/capturing-knowledge.md`.

Skipping rule 2 is how this decays into just another CLI.

## Orientation

```bash
dbq --list                        # aliases, credential state, knowledge coverage
```

If an alias shows `missing`, tell the user to run `dbq init` — **do not try to configure
credentials yourself** (see "Never touch credentials" below).

## Mongo aliases are CLUSTERS, not databases

Read this before your first Mongo query. Each Mongo alias connects to a **cluster** hosting
many per-service databases (`medication` has 20). **There is no database named `medication`,
`patient`, or `encounter`.**

Getting this wrong fails quietly: querying a nonexistent database returns an empty result with
`ok: 1` and no error, which looks exactly like "no data found".

```bash
dbq --collections medication                              # lists DATABASES
DBQ_DB=patient-prescription-query dbq --collections medication   # then COLLECTIONS
```

Databases follow the platform's CQRS split — `<service>-cmd` (event-sourced writes) and
`<service>-query` (read projections). **Prefer `-query` for investigation.** `-data-relay`
databases are integration staging, useful when tracing what an external system received.

MySQL aliases *do* have a working default database (`DASHBOARD_PROD`), so this only applies to
Mongo.

## Querying

`dbq` passes real `mongosh` / `mysql` syntax straight through. There is no dbq dialect.

```bash
# Mongo — name the database, then the collection
DBQ_DB=patient-prescription-query dbq medication \
  'db["patient-prescription"].countDocuments({tenantId:"5740b0c5-a442-4e04-b961-2a1a0b5dc399"})'

# …or switch databases inline
dbq medication 'db.getSiblingDB("pharmacy-query")["pharmacy"].findOne({}, {name:1})'

# MySQL — argument is SQL, default database already selected
dbq mysql-prod 'SELECT office_id, name FROM office LIMIT 5'

# Run a saved script (see Scratch below)
dbq --file medication ~/.dbq/scratch/2026-08-07/trace-rx.js
```

**Use bracket syntax for hyphenated names.** `db["patient-prescription"]`, never
`db.patient-prescription` — `-` is subtraction in JavaScript, so dot notation yields an error
or `NaN`. Nearly every database name on these clusters is hyphenated.

**Always include `tenantId` in production Mongo queries.** The PROD tenant is
`5740b0c5-a442-4e04-b961-2a1a0b5dc399`. Most indexes are tenant-prefixed, so omitting it
turns an indexed lookup into a collection scan. This is the single most common performance
mistake in this codebase.

Nonprod tenant IDs differ — the prod tenant matches nothing in `medication-nonprod`.

## Exploring shape

```bash
dbq --collections medication                                    # databases (no db selected)
DBQ_DB=encounter-type-query dbq --collections encounter         # collections in that db
DBQ_DB=encounter-type-query dbq --schema encounter.encounter-types      # field map + indexes
DBQ_DB=patient-demographic-query dbq --schema patient.<collection> 1000 # sample more
dbq --schema mysql-prod.PAT_MEDICATIONS                         # DESCRIBE + SHOW INDEX
```

**Check the `_id` type before building a lookup.** It is a string UUID in some collections and
a genuine `ObjectId` in others (confirmed `ObjectId` in `encounter-types`). Wrapping in
`ObjectId()` against a string `_id` matches nothing silently.

`--schema` derives the map by sampling real documents and reports presence percentages —
so a field at `12%` tells you it is optional in practice, whatever the code claims. It also
prints indexes, which is what you need before writing any non-trivial query.

For **GraphQL** schema introspection use the `data-fix-scripts` skill's
`introspect-schema.js` instead. `dbq --schema` is the database-side counterpart.

## Reads only

Read-only aliases reject mutating queries before connecting — `insertOne`, `updateMany`,
`drop`, `DELETE`, `DROP`, `TRUNCATE`, and friends. This is a tool-level guard, not advice.

**All writes go through GraphQL mutations** so the Phoenix eventing engine emits proper
domain events. Direct DB writes bypass event emission, aggregate validation, audit trails,
and read-model projections. When a task needs a write, switch to the `data-fix-scripts`
skill — it owns mutation discovery, `--dry-run`, audit logs, and retry generation.

If a query is legitimately blocked and you believe the guard is wrong, report it to the user
rather than hunting for a bypass.

## Scratch and retention

Anything throwaway goes in today's scratch directory:

```bash
dbq scratch            # prints ~/.dbq/scratch/YYYY-MM-DD, creating it if needed
dbq scratch --list     # show the retained window
```

- Every query `dbq` runs is appended to `queries.log` there — a free audit trail. Read it to
  recover "what did I run an hour ago".
- Directories older than **7 days** are pruned automatically on any `dbq` invocation.
  macOS does not self-clean `/tmp` (no `110.clean-tmps`, no `periodic-daily` job), so this
  prune is the retention mechanism.
- Anything worth keeping longer than a week does not belong in scratch. Promote it: a real
  script goes to the relevant repo, a finding goes to `knowledge/`.

Details in `references/scratch.md`.

## Never touch credentials

`dbq init` is **TTY-gated and will refuse to run for you.** That is deliberate: secrets must
never pass through a transcript.

When credentials are missing or wrong, print the command and stop:

> Run this in your terminal to set up the `patient` connection:
> ```
> dbq init --alias patient
> ```

Do not read `~/.config/dbq/env`, `~/.config/dbq/my.cnf`, or the `MDB_MCP_CONNECTION_STRING`
values in `~/.claude.json`. Do not reconstruct a connection string to pass to `mongosh`
yourself. `dbq doctor` tells you everything you need about connection health without
exposing a single secret.

## When something fails

Run `dbq doctor` first — it diagnoses tools, credentials, permissions, and live
connectivity, and prints masked, actionable hints.

| Symptom | Likely cause |
|---|---|
| `host not found — VPN connected?` | Off VPN. `.chenmed.local` and Atlas private-link need it. |
| `timed out` | VPN or firewall. |
| `authentication failed` | Stale credential → user runs `dbq init --alias <name>`. |
| `connected, but user lacks permission` | Read grant missing on that DB; not a dbq problem. |
| `no credential for '<alias>'` | Never configured → `dbq init`. |
| `mongosh is not installed` | `brew install mongosh`. |

`dbq --dump-cmd <alias>` prints the underlying command (credentials **not** expanded) if you
need to hand the user something to run directly.

## Adding a connection

Users can add their own databases and aliases — this is not limited to the shipped eight:

```
dbq init --add
```

It prompts for alias, kind, environment, mode, and default database, then the credential,
then offers a live test. New aliases land in `~/.config/dbq/connections.local.conf`, which
overrides the tracked registry by alias name — so a personal or team-specific connection
never requires editing a git-tracked file.

## References

- `references/mongosh.md` — mongosh patterns, output shaping, aggregation tips
- `references/mysql.md` — MySQL/BIDW patterns and batch output handling
- `references/scratch.md` — scratch workflow and retention
- `references/capturing-knowledge.md` — **how to write knowledge entries, and the PHI rule**
