# raynulfo-personal-skills

Personal Claude Code skills. Skills graduate from here to shared team repos once they have
proven themselves.

## `dbq` — one CLI for every database

Replaces per-database MCP servers with a thin CLI, two skills, and a git-tracked knowledge
base.

**The problem it solves.** Eight database MCP servers (6 MongoDB + 2 MySQL) meant ~128 tool
schemas resident in every session whether or not a database was involved, eight `npx`
subprocesses at startup, and connection strings with embedded passwords sitting in plaintext
in `~/.claude.json` — a file agents read routinely for unrelated reasons. Nothing accumulated:
every agent rediscovered collection shapes and stubbed the same rocks.

**What replaces it.**

| Piece | Role |
|---|---|
| `bin/dbq` | Thin wrapper. Maps an alias to a connection, execs real `mongosh` / `mysql`. |
| `bin/dbq-doctor` | Read-only diagnosis. Agent-safe, prints no secrets. |
| `bin/dbq-init` | Interactive credential editor. **TTY-only — humans only.** |
| `skills/querying-databases/` | How to query; read/write the knowledge base. Used constantly. |
| `skills/setting-up-dbq/` | Install, configure, verify, cut over MCP. Used once per machine. |
| `knowledge/` | Schemas and gotchas per database. Travels with the skill. |
| `config/connections.conf` | Shared alias registry. **No hostnames, no secrets.** |

## Quick start

```bash
git clone <this repo> ~/projects/skills/raynulfo-personal-skills
cd ~/projects/skills/raynulfo-personal-skills

ln -sfn "$PWD/bin/dbq" ~/.local/bin/dbq
ln -sfn "$PWD/skills/querying-databases" ~/.claude/skills/querying-databases
ln -sfn "$PWD/skills/setting-up-dbq"     ~/.claude/skills/setting-up-dbq

dbq doctor                # what's missing
dbq init --from-mcp       # migrate existing MCP credentials  (run this yourself)
dbq doctor                # verify
```

Or just tell Claude "set up dbq" — the `setting-up-dbq` skill drives the whole sequence and
stops at the one step it is not allowed to perform.

## Usage

```bash
dbq --list                                    # aliases, credential state, knowledge coverage
dbq medication 'db.patientPrescription.countDocuments({tenantId:"..."})'
dbq mysql-prod 'SELECT office_id, name FROM office LIMIT 5'
dbq --schema patient.patient 500              # field/type map + indexes
dbq --collections encounter                   # list collections
dbq --dump-cmd medication                     # raw command, credentials NOT expanded
dbq scratch                                   # today's throwaway directory
dbq init --add                                # add your own database + alias
```

## Design decisions

**Credentials never enter `argv`.** Mongo URIs pass through the environment; MySQL passwords
through a `--defaults-file` option group. Neither appears in `ps`, shell history, or a
transcript. Only query text is logged.

**`dbq init` is TTY-gated.** It exits 2 when stdin is not a terminal, so an agent, subagent,
background job, or cron run physically cannot use it. This makes "secrets never touch the
transcript" structural rather than a convention. Agents print the command; the human runs it.

**Read-only is enforced at the tool boundary.** `ro` aliases reject mutating queries before
connecting. Writes go through GraphQL mutations so the Phoenix eventing engine emits proper
domain events — see the `data-fix-scripts` skill, which owns mutation discovery, `--dry-run`,
audit logs, and retries. `dbq` is its read-side sibling.

**The repo holds no hostnames and no secrets.** `config/connections.conf` records only that an
alias exists and what kind it is. Everything environment-specific lives in `~/.config/dbq/`.
That is what makes this repo safe to promote to another team: they supply their own
credentials and inherit the skills and gotchas.

**Two-layer registry.** `config/connections.conf` (tracked) then
`~/.config/dbq/connections.local.conf` (never tracked), which overrides by alias name. Users
add their own connections — or repoint a shared one — without editing a git-tracked file.

**Scratch retention is explicit.** macOS has no `/etc/periodic/daily/110.clean-tmps` and no
`periodic-daily` launchd job, so `/tmp` does not self-clean. `dbq` prunes
`~/.dbq/scratch/YYYY-MM-DD/` older than 7 days on every invocation — no daemon to fail
silently.

**bash 3.2 compatible.** macOS ships bash 3.2.57 (2007) as `/bin/bash`. No associative
arrays, no `mapfile`, no `[[ -v ]]`, and no `timeout` binary. See the header of
`bin/_dbq-lib.sh` before modernising anything.

## `snq` — ServiceNow from the CLI, without an IT ticket

Read/create/update/comment/resolve ServiceNow incidents from the shell, authenticating by
reusing a browser-captured Okta SSO session.

**The problem it solves.** `chenmed.service-now.com` sits behind Okta SAML, and its REST API
advertises only `WWW-Authenticate: Basic` or an OAuth bearer token. A federated SSO account can
produce neither without an admin registering an OAuth client in the Application Registry — an IT
request with real lead time. Unlike Snowflake, ServiceNow has no `authenticator=externalbrowser`
equivalent baked into the protocol.

**What replaces it.** Log in once through a real browser (real Okta, real MFA), capture the
session, reuse it from the CLI until it expires.

| Piece | Role |
|---|---|
| `bin/snq` | The CLI. Incident verbs over the Table API via `curl`. |
| `bin/snq-auth` | Browser SSO capture. **TTY-only — humans only.** |
| `bin/snq-doctor` | Read-only diagnosis. Agent-safe, prints no secrets. |
| `bin/_snq-lib.sh` | Shared config/HTTP/session handling. |
| `skills/servicenow-tickets/` | How to read and write tickets. Used constantly. |
| `skills/setting-up-snq/` | Install, link, verify. Used once per machine. |
| `config/instance.conf` | Instance hostname. **No secrets.** |

```bash
ln -sfn "$PWD/bin/snq" ~/.local/bin/snq
npm install -g playwright && npx playwright install chromium

snq doctor                 # what's missing
snq auth                   # browser + Okta  (run this yourself)
snq whoami                 # verify

snq inc list --state active --priority 1
snq inc get INC0012345
snq inc create --desc "Readiness probe regression" --priority 3
snq inc comment INC0012345 "Rolled back to 3.3.12."
snq inc resolve INC0012345 --note "Config patch deployed."
```

**What you're accepting.** A live production session token rests at `~/.config/snq/session`
(chmod 600, outside git). It expires on its own — ~30 min idle, ~8 h absolute — so the blast
radius is bounded, but while valid it is a real credential for a system holding PHI. The
persistent browser profile at `~/.config/snq/browser-profile` keeps Okta's cookie so re-auth is
usually a silent window blink rather than a full login.

The session carries exactly the permissions the human has — no shared service account, no ACL
bypass, and the audit trail shows the real user. A 403 on a write means the account lacks `itil`;
that one genuinely does need IT.

## Machine-local files

| Path | Mode | Contents |
|---|---|---|
| `~/.config/snq/session` | 600 | ServiceNow session cookie + CSRF token |
| `~/.config/snq/browser-profile/` | 700 | Persistent Chromium profile (Okta cookie) |
| `~/.config/dbq/env` | 600 | Mongo URIs, one per alias |
| `~/.config/dbq/my.cnf` | 600 | MySQL option groups |
| `~/.config/dbq/connections.local.conf` | 644 | Personal aliases and overrides |
| `~/.config/dbq/skipped` | 600 | Aliases deliberately left unset |
| `~/.config/dbq/mcp-rollback.json` | 600 | Removed MCP configs, for rollback |
| `~/.dbq/scratch/YYYY-MM-DD/` | 755 | `queries.log` + throwaway scripts |

None are tracked here. `.gitignore` blocks them as a backstop.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `DBQ_CONFIG_DIR` | `~/.config/dbq` | Config location (useful for testing) |
| `DBQ_SCRATCH_ROOT` | `~/.dbq/scratch` | Scratch location |
| `DBQ_RETENTION_DAYS` | `7` | Scratch retention window |
| `DBQ_DB` | alias default | Override the database for one query |
| `DBQ_PING_TIMEOUT` | `20` | Connectivity test budget, seconds |
| `DBQ_ALLOW_WRITE` | unset | Permit a mutation on an `rw` alias. Cannot override `ro`. |
| `DBQ_CLAUDE_JSON` | `~/.claude.json` | MCP config path (testing) |
| `SNQ_CONFIG_DIR` | `~/.config/snq` | Session/profile location (useful for testing) |
| `SNQ_INSTANCE` | `config/instance.conf` | Target a different ServiceNow instance |
| `SNQ_TIMEOUT` | `45` | curl timeout, seconds |

See `.env.example` for the shape of every credential file — values documented, never real.

## Promoting a skill

When something here earns wider use: move the directory to the shared repo
(`Chenmed-SDLC/skills/`), keep the symlink pattern, and take `knowledge/` with it — the
gotchas are most of the value. Strip anything machine- or person-specific first; the design
above means there should not be any.

## Spec

`docs/specs/2026-08-07-dbq-design.md` records the problem, the alternatives considered, the
verified environment facts behind each decision, and the risks with mitigations.
