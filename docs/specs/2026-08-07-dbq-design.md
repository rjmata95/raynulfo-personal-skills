# dbq — replacing per-database MCP servers with a CLI + skills

**Date:** 2026-08-07
**Status:** Approved
**Repo:** `raynulfo-personal-skills`

## Problem

Eight database MCP servers are configured globally in `~/.claude.json`:

- 6 × `mongodb-mcp-server@latest --readOnly` — medication, patient, tenant-mgmt,
  practice-mgmt, encounter, medication-nonprod
- 2 × `mysql-mcp-server` — mysql-qa, mysql-prod

Costs of this arrangement:

1. **Context weight.** ~128 tool schemas resident in every session, whether or not the
   session touches a database. Mongo alone contributes 21 tools × 6 servers.
2. **Startup cost.** Eight `npx` subprocesses spawn per session.
3. **Credential exposure.** Connection strings with embedded passwords sit in plaintext in
   `~/.claude.json` — a file agents read routinely for unrelated reasons.
4. **No knowledge accumulation.** Every agent rediscovers collection shapes, field
   conventions, and environment quirks from scratch. The same rocks get stubbed repeatedly.
5. **No query trail.** Nothing records what was run.

## Goals

- Replace all eight MCP servers with one CLI wrapper plus skill documentation.
- Keep credentials out of both `~/.claude.json` and agent transcripts.
- Accumulate schema knowledge and gotchas in a git-tracked, promotable knowledge base.
- Retain throwaway queries for at most seven days.
- Let any user add their own connections and aliases without editing tracked files.
- Make first-time setup plug-and-play on a fresh machine.

## Non-goals

- Replacing `data-fix-scripts`. That skill owns *writes* (via GraphQL) and heavyweight
  batch jobs. `dbq` owns *reads* and investigation. They are siblings; `dbq` defers to
  `data-fix-scripts` for anything that mutates data or needs checkpointing.
- Inventing a query dialect. Agents write real `mongosh` and `mysql` syntax.
- Replacing non-database MCP servers (jira, github, bitbucket, newrelic, …). Out of scope.

## Architecture

### Repo layout

```
raynulfo-personal-skills/
├── README.md
├── .gitignore
├── bin/dbq                          # wrapper + doctor + init
├── config/connections.conf          # shared alias registry — no hosts, no secrets
├── skills/
│   ├── querying-databases/          # used every session
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── mongosh.md
│   │       ├── mysql.md
│   │       ├── scratch.md
│   │       └── capturing-knowledge.md
│   └── setting-up-dbq/              # used once per machine
│       ├── SKILL.md
│       └── references/troubleshooting.md
├── knowledge/
│   ├── _index.md
│   ├── _TEMPLATE/{_schema.md,gotchas.md}
│   └── <alias>/{_schema.md,gotchas.md}
└── docs/specs/2026-08-07-dbq-design.md
```

**The repo contains no hostnames and no credentials.** The tracked registry records only
that an alias exists and what kind it is. Hosts and secrets live exclusively under
`~/.config/dbq/`. This is what makes the repo safe to promote to other teams: they supply
their own credentials and inherit the skills and gotchas.

### Machine-local state

| Path | Mode | Contents |
|---|---|---|
| `~/.config/dbq/env` | 600 | `DBQ_<ALIAS>_URI` per mongo alias |
| `~/.config/dbq/my.cnf` | 600 | `[client-<alias>]` groups for MySQL |
| `~/.config/dbq/connections.local.conf` | 644 | personal aliases + overrides |
| `~/.config/dbq/mcp-rollback.json` | 600 | removed MCP configs, verbatim |
| `~/.dbq/scratch/YYYY-MM-DD/` | 755 | `queries.log` + throwaway scripts |

### Two-layer registry

`config/connections.conf` (tracked) is the shared registry. Pipe-delimited:

```
alias|kind|env|mode|default_db|description
```

`~/.config/dbq/connections.local.conf` (never tracked) is loaded second and **overrides by
alias name**. A teammate can repoint `medication` at their own cluster, or add entirely new
aliases, without touching the tracked file. The eight original aliases are ordinary rows —
nothing is special-cased.

### Credential handling

Two improvements over the MCP arrangement, both free:

- **MySQL** uses a native option file via `--defaults-file` + `--defaults-group-suffix`.
  The password never enters `argv`, so it cannot leak through `ps` or shell history.
- **Mongo** passes the URI through the *environment* (`__DBQ_URI`) and connects with
  `mongosh --nodb --eval 'db = connect(process.env.__DBQ_URI); …'`. The connection string
  never appears in `argv`, `ps`, transcripts, or the query log. Only query text is logged.

### Interface

```
dbq <alias> '<query>'            run a query (real mongosh/mysql syntax)
dbq --file <alias> <path>        run a saved scratch script
dbq --schema <alias>.<coll>      derive field/type map by sampling
dbq --collections <alias>        list collections / tables
dbq --list                       aliases + env + mode + knowledge status
dbq --dump-cmd <alias>           print the command, run it yourself (escape hatch)
dbq doctor                       read-only diagnosis; agent-safe
dbq init [--from-mcp] [--add]    interactive credential editor; TTY-only
```

`--schema` replaces the `collection-schema` MCP tool and is the DB-side sibling of
`data-fix-scripts/introspect-schema.js` (which covers GraphQL).

Mongo output defaults to `--json=relaxed`; MySQL to batch/TSV. Both are parseable without
the agent writing formatting glue.

### Read-only enforcement

Aliases marked `ro` reject queries matching mutation patterns (`insertOne`, `updateMany`,
`deleteMany`, `drop`, `INSERT`, `UPDATE`, `DELETE`, `DROP`, `TRUNCATE`, `ALTER`, …) before
connecting. This moves the existing `data-fix-scripts` rule — "MongoDB and MySQL are
read-only query sources" — from the honor system to the tool boundary.

Overridable per-invocation only via `DBQ_ALLOW_WRITE=1` on an `rw` alias. An `ro` alias
cannot be overridden at all.

### Scratch and retention

Verified on this machine: there is **no `/etc/periodic/daily/110.clean-tmps` and no
`periodic-daily` launchd job**, so `/tmp` does not self-clean. Retention must be explicit.

```
~/.dbq/scratch/YYYY-MM-DD/
├── queries.log       # every query dbq ran that day, timestamped
└── *.js / *.sql      # throwaway scripts
```

Pruned by the wrapper itself on each invocation: directories older than seven days are
removed. No launchd job, no daemon, nothing to fail silently. `queries.log` doubles as the
audit trail.

### Knowledge base

`knowledge/<alias>/_schema.md` — collections/tables, field shapes, indexes, enum values.
`knowledge/<alias>/gotchas.md` — append-only; the rocks agents hit.

The `querying-databases` skill makes this bidirectional and non-optional: **read
`knowledge/<alias>/` before the first query of a session; append after any discovered shape
or stumble.**

**Hard rule: structure only, never PHI.** Field names, types, cardinality, index
definitions, and enum values are in scope. Real patient identifiers, MRNs, names, and
document values are not. The PROD tenant ID `5740b0c5-a442-4e04-b961-2a1a0b5dc399` is
explicitly permitted — it identifies a tenant, not a person, and belongs in query guidance
for index efficiency.

## Setup skill

`setting-up-dbq` runs once per machine. It splits mechanical work from judgment:

- `dbq doctor` — read-only, idempotent, prints a pass/fail table. **Agents run this freely.**
- `dbq init` — interactive credential editor. **Only a human runs this.**

### TTY enforcement

`dbq init` refuses to run when stdin is not a TTY:

```
dbq init requires an interactive terminal.
Secrets must never pass through an agent transcript.
Run it yourself:  dbq init
```

This makes "secrets never touch the transcript" structural rather than conventional. An
agent, background job, or subagent that attempts it is rejected.

**Corrected after first real use:** the original design claimed a Claude Code user could run
this in-session with the `!` prefix. That is wrong — `!` pipes stdin rather than allocating a
TTY, so `dbq init` correctly refuses and the prompt loop cannot run. The agent must send the
user to a separate terminal window (Terminal, iTerm, or an IDE terminal tab). The gate itself
needed no change; only the instruction was wrong.

This is a real cost of the design, accepted deliberately: setup cannot be driven entirely
from within a Claude Code conversation. The alternative — letting an agent supply credentials
on a TTY-less stdin — is exactly what the gate exists to prevent.

### `dbq init` modes

- `--from-mcp` — harvest existing DB MCP servers from `~/.claude.json`, pre-fill every URI,
  walk through confirmation. **The migration path.**
- (no flag) — start from the registry with placeholders. **The fresh-machine path.**
- `--add` — add a brand-new connection and alias interactively.

Per-alias screen, then one keypress:

```
[3/8]  patient          mongo · prod · read-only
       URI  mongodb+srv://raynulfom:****@patient-tg1-prod-pl-1.xcrut.mongodb.net
       harvested from MCP · not yet tested

  [k] keep  [e] edit  [t] test  [s] skip  [r] remove  [?] help
```

- Secrets masked on display; never echoed on input (`read -s`).
- `[e]` validates locally (scheme, credential presence, host shape), then offers `[t]est`
  against the live server (`db.runCommand({ping:1})` / `SELECT 1`).
- `[s]kip` records the alias as *deliberately unset* so `doctor` reports `skipped` rather
  than nagging as `MISSING`. `[r]emove` deletes the credential.
- Writes atomically: temp file → `chmod 600` → `mv`. An interrupted run cannot leave a
  half-written or world-readable credential file.
- Routes by alias kind — mongo → `env`, mysql → `my.cnf`. The user does not choose files.

### Setup sequence

1. `dbq doctor` — establish what is missing.
2. Install gaps (`brew install mongosh`). Agent-performed; nothing secret.
3. Snapshot `mcp-rollback.json` **before any change**.
4. Agent prints `dbq init --from-mcp` and **stops**. It cannot proceed itself.
5. `dbq doctor` — verify aliases green.
6. Seed `knowledge/<alias>/_schema.md` for green aliases.
7. **Cutover.** Only aliases that answered a live query are eligible for MCP removal. Agent
   shows the removal list, asks once, then runs `claude mcp remove … -s user`. Any alias not
   green keeps its MCP server and is reported by name.
8. Symlink both skills into `~/.claude/skills/`.

Every step is idempotent and re-runnable — the migration survives a VPN drop partway
through.

### Cutover safety

- Removal uses `claude mcp remove`, not hand-editing `~/.claude.json`. Editing that file
  under a live session risks the session overwriting it.
- Rollback is one paste from `mcp-rollback.json`.
- Tool lists only shrink after a session restart; this is expected, not a failure.

## Verified environment facts

Established by inspection on 2026-08-07, not assumed:

| Fact | Finding |
|---|---|
| `mysql` CLI | 9.6.0 (Homebrew) — present |
| `mongosh` | absent; Homebrew has 2.9.2 — install required |
| `/tmp` auto-clean | **no** `110.clean-tmps`, **no** `periodic-daily` job |
| `claude mcp` | `add-json` / `remove` present — migration is scriptable |
| Project-level `.mcp.json` | none holds DB credentials |
| `op` (1Password) | not installed — `~/.config/dbq/env` is the right target |
| Atlas host DNS | all 6 SRV records resolve |
| Atlas ports | private-link endpoints on **non-standard ports 1037–1045** |
| MySQL host DNS | both `.chenmed.local` hosts resolve (VPN active) |
| Writable PATH dir | `~/.local/bin` — exists, writable, on PATH |

The non-standard Atlas ports matter: `mongosh` handles them via SRV, but any raw
`--host:27017` fallback would fail. The wrapper must always use the SRV URI.

## Risks

| Risk | Mitigation |
|---|---|
| VPN-only host unreachable at cutover | Alias must answer a live query before its MCP is removed; unreachable aliases keep theirs |
| Credentials still plaintext at rest | Narrower than today — out of the file agents read constantly, `chmod 600`, never in `argv`. 1Password is a documented future upgrade |
| Agent runs `dbq init` and leaks secrets | TTY check makes it structurally impossible |
| Knowledge base accumulates PHI | Explicit rule in skill + index; structure-only guidance with examples of both sides |
| Agents keep reaching for MCP tools from habit | The tools are gone after restart; skill is the only documented path |
| Interrupted `init` corrupts credentials | Atomic write: temp → chmod → mv |

## Decisions

| Decision | Rationale |
|---|---|
| `~/.config/dbq/env`, chmod 600 | Portable, works headless/cron, no unlock prompts |
| Thin bash wrapper over full Node CLI | Agents use real CLI syntax; nothing new to document or maintain |
| Remove all 8 MCP servers | Biggest context win; forces the CLI path to be exercised |
| Knowledge base in skills repo | Gotchas travel when the skill is promoted — the point of promotion |
| Scratch at `~/.dbq/scratch` | Project-agnostic; keeps throwaway SQL out of `~/.claude` |
| One query skill, not two | Avoids building a speculative capture skill before the pattern proves out |
| Explicit 7-day prune | `/tmp` self-clean verified absent on this machine |
| Two-layer registry | Users add connections without touching tracked files |
