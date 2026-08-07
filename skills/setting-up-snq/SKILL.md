---
name: setting-up-snq
description: Install and configure the `snq` ServiceNow CLI on a machine, including the browser-based Okta SSO session capture. Use when snq is not installed, when `snq doctor` reports problems, when setting up a new laptop, when onboarding someone to snq, or when the user says "set up snq", "set up servicenow access", "get servicenow working", or asks why ServiceNow commands are failing with 401s.
---

# Setting up `snq`

Runs **once per machine**, then once per session for auth (which is a 5-second browser blink,
not a real setup step).

## The one rule you cannot break

**You must never run `snq auth`, and never handle the session token.**

`snq auth` is TTY-gated and exits 2 when an agent invokes it. That is deliberate: it performs an
interactive Okta login and writes a live production session token. Your job at that step is to
print the command and **stop**.

Also forbidden: reading `~/.config/snq/session`, echoing its contents, or scripting a browser to
harvest the session "to save the user time."

## Checklist

Create a TodoWrite item per step.

1. Diagnose
2. Install missing tools
3. Link the CLI onto PATH
4. Hand off for browser auth — **hard stop**
5. Verify
6. Link the skills

---

### 1. Diagnose

```bash
snq doctor          # or ./bin/snq doctor if not yet on PATH
```

Read the sections: TOOLS, CONFIG, SESSION, CONNECTIVITY, GIT HYGIENE. Parse the tail:

```
snq_doctor_problems=4
snq_doctor_session=absent
snq_doctor_writes=disabled
```

Everything below addresses a specific problem `doctor` reported. Don't do steps it says are
already fine.

### 2. Install missing tools

Only what TOOLS reports missing. All safe, non-secret — do these yourself.

**Check `doctor` before installing anything.** Playwright is frequently already present but
*nested* under `@playwright/cli/node_modules`, where a bare `require.resolve("playwright")`
cannot see it. `snq doctor` and `snq-auth` both probe that location, so a green
`playwright module` line means you need no install even if `npm ls -g` looked bare.

Likewise the browser: `snq auth` launches with `channel: 'chrome'`, using the system
**Google Chrome** if `/Applications/Google Chrome.app` exists. That sidesteps Playwright's
pinned-revision problem, where the module wants e.g. Chromium 1212 while the cache holds 1208.
Don't run `npx playwright install chromium` unless `doctor` reports no usable browser.

If genuinely missing:

```bash
npm install -g playwright              # the module
npx playwright install chromium        # only if there is no system Chrome
```

Point at a non-standard module location with `SNQ_PLAYWRIGHT_PATH=/path/to/node_modules`.

`curl` and `python3` ship with macOS. `node` is already present if the user runs any JS tooling.

Note: the repo's `.playwright-mcp/` directory and the Playwright MCP server are **unrelated** to
this — `snq auth` launches its own persistent-profile browser so it doesn't fight the MCP's
browser for a lock.

### 3. Link the CLI onto PATH

Symlink so git stays the source of truth:

```bash
ln -sfn <repo>/bin/snq ~/.local/bin/snq
```

Confirm `~/.local/bin` is on PATH. If not, tell the user which shell rc line to add — don't edit
their rc file unasked.

### 4. Browser auth — hand off and STOP

This is the step you cannot perform. Print exactly this and wait:

> Everything mechanical is done. The login is yours — it opens a browser for Okta SSO, and the
> session token it captures is something I shouldn't see.
>
> **Open a real terminal window** and run:
> ```
> snq auth
> ```
> A Chromium window opens on the ServiceNow homepage. Complete Okta if it asks (first run
> usually does; later runs are typically silent because the browser profile persists). When you
> land on the homepage it captures the session and closes itself.
>
> Then tell me and I'll verify.

**Why a persistent browser profile:** it lives at `~/.config/snq/browser-profile` (chmod 700) and
keeps Okta's own session cookie, so re-auth after the ~30-minute ServiceNow idle timeout usually
needs zero interaction. That is the entire ergonomic payoff of this design — without it, the user
would retype credentials several times a day.

### 5. Verify

After the user confirms:

```bash
snq doctor      # expect snq_doctor_problems=0, session=present, writes=enabled
snq whoami      # expect their name and "writes: enabled"
snq inc list --limit 3
```

Three outcomes worth distinguishing:

| Symptom | Meaning | Fix |
|---|---|---|
| `writes: DISABLED (no g_ck)` | Cookie captured, CSRF token wasn't | Re-run `snq auth`, ensure it lands on `/navpage.do` not a raw API URL |
| 401 on a read | Session already expired | Re-run `snq auth` |
| 403 after a successful read | Session fine; roles insufficient | Needs the `itil` role — an IT ask, not a setup bug |

Don't report success on the strength of `doctor` alone — run the actual `snq inc list` and
confirm records come back.

### 6. Link the skills

```bash
ln -sfn <repo>/skills/servicenow-tickets ~/.claude/skills/servicenow-tickets
ln -sfn <repo>/skills/setting-up-snq     ~/.claude/skills/setting-up-snq
```

For the brain specifically, the user prefers these symlinked into the brain's installed skills
directory so they're scoped there too:

```bash
ln -sfn <repo>/skills/servicenow-tickets ~/projects/brain/.claude/skills/servicenow-tickets
```

## What lives where

| Path | Contents | Git |
|---|---|---|
| `bin/snq`, `bin/snq-auth`, `bin/snq-doctor`, `bin/_snq-lib.sh` | The CLI | tracked |
| `config/instance.conf` | Instance hostname. **No secrets.** | tracked |
| `.env.example` | Documents variable shapes only | tracked |
| `~/.config/snq/session` | Live session cookie + CSRF token | **never** (chmod 600) |
| `~/.config/snq/browser-profile/` | Persistent Chromium profile w/ Okta cookie | **never** (chmod 700) |

The repo's `.gitignore` blocks `session`, `browser-profile/`, `cookies.json`, and
`storage-state.json` as a backstop. `snq doctor`'s GIT HYGIENE section re-checks this every run —
if it ever reports the session file inside the repo, treat that as urgent.

## Troubleshooting

See `references/troubleshooting.md`.
