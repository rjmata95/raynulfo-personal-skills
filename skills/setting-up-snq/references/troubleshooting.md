# `snq` troubleshooting

Ordered by how often each actually happens.

## 401 on a session captured seconds ago

Distinguish this from the idle timeout below by **session age**. If `snq doctor` says the session
was captured seconds or a couple of minutes ago and reads still 401, it is not expiry — telling
the user to re-run `snq auth` will loop forever.

ServiceNow returns:

```
{"error":{"message":"User is not authenticated",
          "detail":"Required to provide Auth information"},"status":"failure"}
```

Cause: `/api/now/` will not accept a session cookie on its own. The `g_ck` CSRF token
(`X-UserToken`) is required on **reads as well as writes** — it is the auth signal for a
browser-derived session, not a write-only guard. Any code path that sends `Cookie` without
`X-UserToken` gets a 401 no matter how fresh the cookie is.

Fixed in `_snq-lib.sh` (`snq_api` sends the header on every method) and in `snq-doctor`'s
connectivity probe. If it resurfaces, check that both places still send it — a doctor probe that
omits the header reports a perfectly good session as expired.

Note the 401 handler prints ServiceNow's own message. `"User is not authenticated"` on a fresh
session means this; a bare 401 on an old one means the timeout below.

## 401 on every command, right after a successful run

The session hit ServiceNow's ~30-minute idle timeout. Normal, not a bug.

```
snq: session expired or not authenticated (HTTP 401).
     Session age: 47m. ServiceNow drops idle sessions after ~30 min.
     Re-authenticate: snq auth
```

The user runs `snq auth`. Because the browser profile persists Okta's cookie, this is usually a
window that flashes open and closes with no typing. Agents: print the command, stop, don't loop.

Absolute session lifetime is ~8 hours regardless of activity, so a session captured in the
morning is dead by afternoon even under continuous use.

## `writes: DISABLED (no g_ck)`

The cookie was captured but the CSRF token wasn't. Reads work; every write fails.

Cause: the capture landed somewhere that isn't an authenticated ServiceNow *page*. `window.g_ck`
exists on `/navpage.do` and other UI pages, but **not** on a raw `/api/now/...` JSON response.

Fix: re-run `snq auth`. If it keeps happening, the instance may render a different landing shell —
check what `page.url()` ends up as in `bin/snq-auth` and whether `g_ck` is exposed there.

## `Browser is already in use for .../mcp-chrome-...`

The Playwright **MCP server** holds a lock on its own browser profile. `snq auth` uses a separate
profile (`~/.config/snq/browser-profile`) specifically to avoid this, so if you see it, something
is pointing at the MCP's profile directory.

Check `SNQ_CONFIG_DIR` isn't set to something odd, and that `PROFILE_DIR` in `bin/snq-auth`
resolves under `~/.config/snq/`.

## `playwright module missing`

```bash
npm install -g playwright
npx playwright install chromium
```

`snq auth` resolves `playwright` or `playwright-core` via node's resolution from the global root.
Only `snq auth` needs it — `snq inc list` and friends are pure `curl` + `python3`.

## 403 after a read succeeds

Not an auth problem. The session is valid; the account lacks the role. Writing to `incident`
requires `itil`.

This is an IT request, and it's the one thing this whole design can't route around — the browser
session carries exactly the permissions the human has, no more. That's the security property, not
a limitation to work around.

## `no records matched` when records definitely exist

Encoded-query syntax is unforgiving:

- `^` is AND, `^OR` is OR — a literal space is not a separator.
- `LIKE` for contains; `=` is exact and case-sensitive on some fields.
- Reference fields need dot-walking: `assigned_to.name=Andry Leal`, not `assigned_to=Andry Leal`.
- `--state` keywords map to `active=true`, `active=true^stateIN1,2,3`, `state=6`, `state=7`. A raw
  number goes through as `state=<n>`.

Debug by asking for JSON and checking what came back:

```bash
snq inc list --query "..." --json | python3 -m json.tool | head -40
```

## Session file has wrong permissions

`snq doctor` flags anything other than 600 on the session file or 700 on the config dir.

```bash
chmod 600 ~/.config/snq/session
chmod 700 ~/.config/snq ~/.config/snq/browser-profile
```

`snq auth` writes under `umask 077` and re-`chmod`s, so this only happens if something external
touched the file.

## The session file ended up in a git repo

Treat as urgent. It's a live production credential for a system holding PHI.

```bash
git -C <repo> ls-files | grep -E '(^|/)session$'    # confirm it's tracked
git -C <repo> rm --cached <path>                     # untrack
chmod 600 <path>                                     # or delete it
```

Then re-run `snq auth` to rotate — assume the old session is compromised. If it was ever pushed,
the token needs to be invalidated by ending the session in ServiceNow (log out from the browser
profile) rather than just deleting the file.

## Verifying without a live session

Everything except the live-read check is testable offline:

```bash
bash -n bin/snq bin/snq-auth bin/snq-doctor bin/_snq-lib.sh   # syntax
snq --help
snq doctor                     # exits 1 with problems listed, 0 when clean
snq inc list                   # should fail with the directed "no session" message
snq auth < /dev/null; echo $?  # must print the agent refusal and exit 2
```
