# `dbq` setup troubleshooting

Run `dbq doctor` first. It reports tools, config, permissions, live connectivity, MCP state,
and knowledge coverage, and masks every credential.

## Install and PATH

**`dbq: command not found`**

```bash
ln -sfn <repo>/bin/dbq ~/.local/bin/dbq
command -v dbq
```

If still missing, `~/.local/bin` is not on PATH. Add to `~/.zshrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Use a **symlink, not a copy** — git must stay the source of truth, matching the rest of
`~/.claude/skills/`.

**`mongosh is not installed`** → `brew install mongosh`
**`mysql is not installed`** → `brew install mysql-client` (may need its bin dir on PATH)

**Syntax errors from bash**

The scripts target **bash 3.2**, which is what macOS ships as `/bin/bash`. If you edited them
and introduced associative arrays (`declare -A`), `mapfile`, or `[[ -v ]]`, they will break on
a stock Mac. Check with:

```bash
/bin/bash -n bin/dbq bin/dbq-doctor bin/dbq-init bin/_dbq-lib.sh
```

## Credentials

**`dbq init` exits with code 2 and a message about needing a terminal**

Working as designed. `dbq init` refuses to run without a TTY so secrets never pass through an
agent transcript. Run it yourself, in a real terminal window:

```bash
dbq init --from-mcp
```

**This will not work from inside a Claude Code session, including with the `!` prefix.** `!`
pipes stdin rather than attaching a terminal, so the interactive prompt loop cannot run and
you will get this same message. Use Terminal, iTerm, or your IDE's terminal tab.

**`no credential for '<alias>'`** → `dbq init --alias <alias>`

**Permissions are `644`, must be `600`**

```bash
chmod 600 ~/.config/dbq/env ~/.config/dbq/my.cnf
```

`dbq init` sets this automatically; a manual edit or a copy across machines can lose it.

**Harvest found nothing**

`dbq init --from-mcp` reads `~/.claude.json` for servers with `MDB_MCP_CONNECTION_STRING` or
`MYSQL_HOST` in `env`. If the servers are configured at project scope, or in a `.mcp.json`,
harvest will not see them. Use plain `dbq init` and enter values manually.

## Connectivity

**`host not found — VPN connected?`**

Both `.chenmed.local` MySQL hosts and Atlas private-link endpoints need VPN. Confirm:

```bash
dig +short _mongodb._tcp.<cluster>.mongodb.net SRV
dig +short <host>.chenmed.local A
```

No answer → DNS/VPN. Note Atlas SRV records resolve to **non-standard ports** (observed
1037–1945 range); this is normal for private-link. Never hand-build a `--host host:27017`
command — always let `dbq` use the SRV URI.

**`timed out`** — VPN or firewall. Raise the budget while diagnosing:

```bash
DBQ_PING_TIMEOUT=45 dbq doctor
```

**`authentication failed`** — credential is stale or wrong: `dbq init --alias <alias>`.
Rotated Atlas passwords are the usual cause.

**`ERROR 2059 ... Authentication plugin 'mysql_clear_password' cannot be loaded`**

The server authenticates through PAM/LDAP and needs the password sent using
`mysql_clear_password`. The MySQL client refuses to load that plugin by default, because
cleartext is unsafe on an unencrypted connection. (Node-based MySQL drivers — including the
old MCP server — negotiate this silently, which is why the CLI surfaces a problem the MCP
server appeared not to have.)

Fix it per alias, in a real terminal:

```bash
dbq init --alias mysql-qa      # then press [a], confirm, and [t] to test
```

`[a]` writes two lines into that alias's `my.cnf` group:

```
enable-cleartext-plugin
ssl-mode = REQUIRED
```

**TLS is not optional here.** `enable-cleartext-plugin` alone would put the password on the
wire in plain text, so `dbq` always pairs it with `ssl-mode = REQUIRED`. If the server does
not support TLS, stop and raise it with the DBA rather than dropping the ssl-mode line.

These options are preserved when `dbq init` regenerates `my.cnf`, so the fix is one-time.
`[a]` again toggles it back off.

**`connected, but user lacks permission`** — the connection works; the account has no read
grant on that database. Not fixable in `dbq`. Skip the alias (`[s]`) and raise access
separately.

**Everything fails at once** — you are almost certainly off VPN. Check one host with `dig`
before debugging further.

## MCP cutover

**Tools still listed after removal**

Expected. MCP tool lists are established at session start; restart the session.

**Removed one by mistake — how do I get it back?**

`~/.config/dbq/mcp-rollback.json` holds the original configs verbatim.

```bash
python3 -c "import json;print(json.dumps(json.load(open('$HOME/.config/dbq/mcp-rollback.json'))['mcpServers']['mongodb-patient'],indent=2))"
```

Re-add with that JSON:

```bash
claude mcp add-json mongodb-patient '<json>' -s user
```

**No rollback file exists**

It is written by `dbq init --from-mcp` before harvesting. If you configured credentials
manually and then removed servers, there is no snapshot — recover from `~/.claude.json`
history, or reconstruct from the credentials in `~/.config/dbq/`.

**Never hand-edit `~/.claude.json`** to remove servers. A running session can overwrite the
file. Use `claude mcp remove <name> -s user`.

## Registry and aliases

**Added a row to `connections.conf` but `dbq --list` ignores it**

Format is strict: `alias|kind|env|mode|default_db|description`, pipes with no surrounding
spaces, `kind` exactly `mongo` or `mysql`. An unknown kind is skipped with a warning.

**Want a personal connection without touching git**

```bash
dbq init --add
```

Writes to `~/.config/dbq/connections.local.conf`, which loads after the shared registry and
overrides by alias name. To repoint a shared alias (say `medication` at nonprod), add a row
with the same alias there.

**Alias name rejected** — lowercase letters, digits, hyphens only; cannot be a reserved
command (`doctor`, `init`, `scratch`, `help`, `list`, `version`).

## Read-only guard

**A legitimate read was refused**

The guard is a regex over the query text and can misfire — e.g. a literal string containing
`DELETE`, or a collection named `...update...`. Report it rather than working around it; the
pattern lives in `MONGO_WRITE_RE` / `SQL_WRITE_RE` in `bin/dbq`.

**Need to write**

You almost certainly should not. Writes go through GraphQL mutations so the Phoenix eventing
engine emits domain events; direct writes bypass event emission, validation, audit trails,
and read-model projections. Use the `data-fix-scripts` skill. `DBQ_ALLOW_WRITE=1` exists for
genuinely local `rw` aliases only, and cannot override a `ro` alias at all.
