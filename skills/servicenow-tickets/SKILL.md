---
name: servicenow-tickets
description: Read, create, update, comment on, and resolve ServiceNow incident tickets through the `snq` CLI, which authenticates by reusing a browser-captured Okta SSO session. Use whenever the user mentions a ServiceNow ticket, an INC number, "open a ticket", "file an incident", "check the status of INC...", ITSM, service desk, change requests, or asks who a ticket is assigned to. Also use when a production incident in the brain needs a corresponding ServiceNow record.
---

# ServiceNow tickets via `snq`

ChenMed's ServiceNow (`chenmed.service-now.com`) sits behind Okta SAML. Its REST API accepts
only Basic auth or an OAuth bearer token — neither of which a federated SSO account can
produce without IT registering an OAuth client. `snq` sidesteps that: the human logs in once
through a real browser, and the CLI reuses that session.

## The one rule you cannot break

**Never run `snq auth`, and never read the session file.**

`snq auth` is TTY-gated and exits 2 for agents, by design — it drives an interactive login and
handles a live production session token. When a session is missing or expired, your job is to
print the command and **stop**.

Also forbidden:
- Reading `~/.config/snq/session` (or `cat`/`grep`/`source`-ing it).
- Echoing `SNQ_COOKIE` or `SNQ_USER_TOKEN` anywhere — transcript, file, ticket, commit.
- Copying the session file into the brain repo or any git working tree.
- Reconstructing a session by scripting a browser yourself.

`snq doctor` tells you everything you need about session state without exposing a secret.

## Orientation

```bash
snq doctor     # setup + session state; prints no secrets, safe to run anytime
snq whoami     # who the session belongs to, and whether writes are enabled
```

Parse the machine-readable tail of `doctor` rather than eyeballing it:

```
snq_doctor_problems=0
snq_doctor_session=present
snq_doctor_writes=enabled
```

If `snq_doctor_session=absent` or `snq_doctor_writes=disabled`, go to
[When the session is dead](#when-the-session-is-dead).

## Reading

```bash
snq inc list                                   # 20 most recent
snq inc list --state active --priority 1       # active P1s
snq inc list --state open --group "DSC Support"
snq inc list --assigned-to "Andry Leal" --limit 50
snq inc get INC0012345                         # full detail, one record
snq inc list --json                            # raw JSON for further processing
```

`--state` takes a keyword (`active`, `open`, `resolved`, `closed`) or a raw numeric state.
For anything the flags don't cover, pass a ServiceNow encoded query straight through:

```bash
snq inc list --query "active=true^priority<=2^assignment_groupLIKEDSC" --limit 50
```

Encoded-query syntax: `^` is AND, `^OR` is OR, `LIKE` is contains, `IN` takes a comma list.
Dot-walk references with `assigned_to.name=...`.

## Writing

Writes need the CSRF token (`g_ck`) that `snq auth` captures alongside the cookie. If it's
missing, every write fails with a directed error — that's the token, not your syntax.

```bash
snq inc create --desc "Eventing engine 3.4.0 readiness probe regression" \
               --details "Five services on 3.4.0 lack health group config." \
               --priority 3

snq inc update  INC0012345 --priority 2 --state 2
snq inc comment INC0012345 "Rolled back to 3.3.12; monitoring."   # customer-visible
snq inc worknote INC0012345 "Internal: suspect commit 3bec534."   # internal only
snq inc resolve INC0012345 --note "Config patch deployed via ArgoCD."
```

`comment` is customer-visible; `worknote` is internal. Pick deliberately — the distinction is
what stakeholders see. `resolve` requires `--note`; ServiceNow rejects empty close notes.

Any field the flags don't cover:

```bash
snq inc update INC0012345 --field cmdb_ci=medication-query --field u_root_cause="memory leak"
```

## Confirm before you write

Creating, resolving, or reassigning a ticket is outward-facing — other people get notified and
it lands in an audit trail under the user's name. Show the exact command and get an explicit
go-ahead before the first write in a session. Reads need no confirmation.

Once the user has approved a specific batch ("comment on these five"), carry it out without
re-asking per ticket.

## When the session is dead

ServiceNow drops idle sessions after ~30 minutes and caps absolute lifetime around 8 hours.
A dead session produces:

```
snq: session expired or not authenticated (HTTP 401).
     Re-authenticate: snq auth
```

Print exactly this and stop:

> Your ServiceNow session expired. Re-auth is yours to run — it opens a browser for Okta and I
> can't (and shouldn't) drive it.
>
> **In a terminal:**
> ```
> snq auth
> ```
> The browser profile persists, so this is usually just a window that opens and closes without
> asking for anything. Then tell me and I'll pick up where I left off.

Do not retry the failed command in a loop, and do not try to refresh the session yourself.

## Other tables

`snq` defaults to `incident` but `--table` reaches anything the Table API exposes and your
roles allow:

```bash
snq --table change_request inc list --state open
snq --table sc_req_item    inc list --limit 10
snq --table problem        inc get PRB0001234
```

The `inc` verb name is a wart when combined with `--table`; the field flags still apply.

## Cross-referencing the brain

When a ServiceNow incident corresponds to an incident folder under `incidents/`, record the INC
number in that incident's `README.md` frontmatter so the two systems stay linked. The brain
stays the analytical record; ServiceNow is the operational one. Don't duplicate a full timeline
into ServiceNow work notes — link instead.

## Roles

Reads generally work for any authenticated user. Writing to `incident` needs the `itil` role.
A 403 after a successful read means roles, not session — say so plainly rather than suggesting
re-auth.

## Setup

Not installed, or `snq doctor` reports problems? That's the `setting-up-snq` skill.
