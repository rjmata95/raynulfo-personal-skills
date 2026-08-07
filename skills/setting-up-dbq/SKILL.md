---
name: setting-up-dbq
description: Install and configure the dbq database CLI on a machine, and migrate off per-database MongoDB/MySQL MCP servers. Use when dbq is not installed or not configured, when `dbq doctor` reports problems, when a user wants to remove/replace database MCP servers, when setting up a new laptop, when onboarding a teammate to dbq, or when a user says "set up dbq", "migrate off the DB MCPs", "plug and play the database CLI", or asks how to get database access working.
---

# Setting up `dbq`

Runs **once per machine**. Gets the CLI installed, credentials configured, connectivity
verified, and the database MCP servers removed — in that order, because each step gates the
next.

## The one rule you cannot break

**You must never run `dbq init`, and never handle a credential.**

`dbq init` is TTY-gated and will reject you with exit code 2. That is by design: secrets must
never pass through a transcript. Your job at that step is to print the command and **stop**.

Also forbidden:
- Reading `~/.config/dbq/env` or `~/.config/dbq/my.cnf`.
- Reading `MDB_MCP_CONNECTION_STRING` / `MYSQL_PASSWORD` values out of `~/.claude.json`.
- Writing a credential file yourself, or scripting the harvest "just to save the user time".
- Asking the user to paste a connection string into the conversation.

`dbq doctor` gives you everything you need to drive this without seeing a secret.

## Checklist

Create a TodoWrite item per step.

1. Diagnose
2. Install missing tools
3. Hand off to the user for credentials — **hard stop**
4. Verify
5. Seed knowledge
6. Cut over the MCP servers
7. Link the skills

---

### 1. Diagnose

```bash
dbq doctor
```

If `dbq` is not on PATH yet, run it from the repo: `./bin/dbq doctor`.

Read the sections: TOOLS, CONFIG, REGISTRY, CONNECTIONS, MCP, KNOWLEDGE. The tail emits
machine-readable state you should parse rather than eyeball:

```
dbq_doctor_problems=4
dbq_doctor_verified=medication,patient
dbq_doctor_unverified=mysql-prod
```

### 2. Install missing tools

Only what TOOLS reports missing. Both are safe, non-secret operations you perform yourself.

```bash
brew install mongosh        # mongo shell
brew install mysql-client   # mysql CLI, if absent
```

Put `dbq` on PATH via a symlink, so git stays the source of truth:

```bash
ln -sfn <repo>/bin/dbq ~/.local/bin/dbq
```

Confirm `~/.local/bin` is on PATH; if not, tell the user which shell rc line to add.

### 3. Credentials — hand off and STOP

First confirm a rollback snapshot will exist. `dbq init --from-mcp` writes
`~/.config/dbq/mcp-rollback.json` before harvesting, but verify afterwards.

Then print exactly this and **wait for the user**:

> Everything mechanical is done. Credentials are yours to enter — I'm not able to see them,
> which is deliberate.
>
> Run this in your terminal:
> ```
> ! dbq init --from-mcp
> ```
> It reads your existing MongoDB/MySQL MCP settings, pre-fills every connection, and walks
> you through them one at a time. Per alias: `[k]` keep, `[e]` edit, `[t]` test live,
> `[s]` skip if you don't have access, `[r]` remove. Input is hidden as you type.
>
> Tell me when you're done and I'll verify.

Choose the mode by situation:

| Situation | Command |
|---|---|
| Has DB MCP servers to migrate from | `! dbq init --from-mcp` |
| Fresh machine, no MCP servers | `! dbq init` |
| One alias broken | `! dbq init --alias <name>` |
| Adding their own database | `! dbq init --add` |

**Do not proceed past this step on your own.** No credential means no verification, and no
verification means the cutover in step 6 is unsafe.

### 4. Verify

```bash
dbq doctor
```

Every alias the user configured should be `ok`. Interpret failures from `dbq_doctor_unverified`:

- `host not found` / `timed out` → ask whether they are on VPN, then re-run. Atlas
  private-link and `.chenmed.local` both require it.
- `authentication failed` → `! dbq init --alias <name>`.
- `connected, but user lacks permission` → a real grant issue; not fixable here. Suggest they
  skip that alias for now (`[s]`) and raise access separately.
- `skipped` → deliberate. Not a problem; exclude it from the cutover.

Loop with the user until the verified set is stable. Some aliases may never verify (no
access) — that is fine and must not block the rest.

### 5. Seed knowledge

For each **verified** alias with no `knowledge/<alias>/` directory, create one from
`knowledge/_TEMPLATE/`, then populate `_schema.md` for the collections that actually matter.
Do not try to document everything; document what someone will query.

```bash
dbq --collections <alias>
dbq --schema <alias>.<collection>
```

Paste the derived field map into `_schema.md`. **Structure only — never PHI.** Field names,
types, presence percentages, index definitions, and enum values are in scope. Real patient
identifiers, MRNs, names, and document values are not. See
`../querying-databases/references/capturing-knowledge.md`.

Start `gotchas.md` from the template with an empty log. It fills as agents hit things.

### 6. Cut over the MCP servers

**Gate: only remove a server whose alias appears in `dbq_doctor_verified`.** An alias that
never answered a live query keeps its MCP server — otherwise the user loses access to that
database entirely.

Show the plan and ask once:

> These aliases are verified working through the CLI, so their MCP servers are now redundant:
>
> - `mongodb-medication` → alias `medication` ✓
> - `mongodb-patient` → alias `patient` ✓
>   …
>
> Keeping (not verified): `mongodb-encounter` — timed out, no access confirmed.
>
> Removing these drops ~N tool schemas from every session. Rollback is one paste from
> `~/.config/dbq/mcp-rollback.json`. Remove them?

On approval, use the CLI — **never hand-edit `~/.claude.json`**, since a live session can
overwrite it:

```bash
claude mcp remove mongodb-medication -s user
claude mcp remove mongodb-patient -s user
# … one per verified alias
```

Then confirm with `dbq doctor` — the MCP section should list only what you intentionally kept.

Tell the user the tool list shrinks after a **session restart**, not immediately. That is
expected, not a failure.

### 7. Link the skills

```bash
ln -sfn <repo>/skills/querying-databases ~/.claude/skills/querying-databases
ln -sfn <repo>/skills/setting-up-dbq   ~/.claude/skills/setting-up-dbq
```

Symlinks (not copies) keep the git repo authoritative — the same pattern as the rest of
`~/.claude/skills/`.

---

## Onboarding a teammate

Same seven steps, with two differences:

- **Step 3** uses plain `! dbq init` (no MCP servers to harvest). Every alias starts unset;
  they `[e]`dit the ones they have access to and `[s]`kip the rest.
- **Step 6** is a no-op if they never had DB MCP servers.

They get your `knowledge/` directory for free. That is the payoff of keeping it in the repo:
the gotchas travel with the skill.

If they need a database nobody has registered yet, `! dbq init --add` writes it to their
local overlay. If it turns out to be broadly useful, add the row to
`config/connections.conf` (no hostnames, no secrets) and commit.

## Troubleshooting

See `references/troubleshooting.md` for install, PATH, VPN, permission, and rollback issues.
