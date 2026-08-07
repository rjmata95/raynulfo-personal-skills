# Scratch and retention

## Where it lives

```
~/.dbq/scratch/
├── 2026-08-07/
│   ├── queries.log          # every query dbq ran today
│   ├── trace-rx.js
│   └── office-rollup.sql
├── 2026-08-06/
└── …
```

```bash
dbq scratch          # prints today's directory, creating it if needed
dbq scratch --list   # show the retained window
```

Use it in one line:

```bash
cat > "$(dbq scratch)/probe.js" <<'EOF'
printjson(db.patientPrescription.getIndexes().map(i => i.name));
EOF

dbq --file medication "$(dbq scratch)/probe.js"
```

## Retention: 7 days

Directories older than 7 days are deleted on any `dbq` invocation. No launchd job, no cron,
nothing to fail silently — the tool prunes as a side effect of being used.

**Why not rely on `/tmp`:** macOS on this machine has no
`/etc/periodic/daily/110.clean-tmps` and no `periodic-daily` launchd job, so `/tmp` never
self-cleans. Verified, not assumed. Retention has to be explicit, which is why it lives in
the wrapper.

Override if you need to:

```bash
DBQ_RETENTION_DAYS=14 dbq --list      # per-invocation
export DBQ_RETENTION_DAYS=14          # per-shell
```

Pruning is by directory mtime. Re-running a query today does not preserve last week's folder.

## `queries.log`

Every query `dbq` runs is appended to the current day's log:

```
[2026-08-07T12:39:07] alias=medication
db.patientPrescription.countDocuments({tenantId:"5740b0c5-..."})
---
```

Two uses:

1. **Recovery.** "What did I run an hour ago that produced that number?" — `grep` the log.
2. **Audit.** A record of what was queried, per day, per alias.

**The connection string is deliberately never written here.** Only the query text and alias.
If you find a credential in this log, that is a bug — report it.

## What belongs in scratch

Anything you would be happy to lose in a week:

- One-off exploration queries
- Intermediate result dumps while chasing something down
- Throwaway aggregation pipelines you are iterating on
- Scripts written to answer a single question

## What does not

If it will matter in a month, promote it out of scratch:

| Kind of thing | Where it goes |
|---|---|
| A query you will re-run | A script in the relevant repo |
| A shape or gotcha you learned | `knowledge/<alias>/` |
| A reusable data-fix or report | `data-fix-scripts` conventions, in its own project |
| A finding about a project | The project's notes |
| Output someone else needs | Somewhere shared — not a local scratch dir |

The test: if losing it next Tuesday would annoy you, it is in the wrong place.

## Not for large exports

Scratch is for query text and small outputs. Dumping a multi-hundred-MB export here will sit
in your home directory for a week and then vanish — the worst of both worlds. For anything
at that scale use the `data-fix-scripts` skill, which has NDJSON streaming, checkpointing,
and proper output conventions.
