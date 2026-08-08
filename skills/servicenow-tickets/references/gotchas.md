---
skill: servicenow-tickets
---

# servicenow-tickets — gotchas

Append-only. Newest entry at the top. Never rewrite a previous entry — if one turns out to be
wrong, append a correction that supersedes it and say so.

> **Never record a session cookie, CSRF token, or anything from `~/.config/snq/session` here.**
> Describe API behaviour, not credentials.

Entry format:

```markdown
## YYYY-MM-DD — one-line summary

**Symptom:** what looked wrong, or what you expected and did not get.
**Cause:** what is actually going on.
**Handling:** what to do instead. Include a working command if there is one.
```

Worth an entry: a field the API silently leaves blank, a flag that looks like it works but
doesn't, a role/permission wall that reads like a session failure, a business rule that
overrides what you sent, display-value vs. sys_id traps, anything a human had to fix by hand
after the CLI reported success.

Not worth an entry: one-off typos. Only record what will still be true for the next agent.

---

<!-- Newest entries go directly below this line. -->

## 2026-08-07 — `inc create` writes only the fields you pass; the form's defaults do not apply

**Symptom:** Created INC0567552 with `--desc --details --priority 3`. The CLI reported success
and `inc get` looked fine. But **`impact` and `urgency` were blank** and **`caller_id` was
empty** — the human had to set all three by hand in the ServiceNow UI. `priority` did land.

**Cause:** Two separate things, both structural — not a bug in the create call.

1. **`caller_id`, `impact`, and `urgency` are UI-form defaults, not table defaults.** When a
   human opens the incident form, ServiceNow's client-side defaults populate caller with the
   logged-in user and pre-select impact/urgency. The REST Table API **bypasses the form
   entirely** — it writes exactly the JSON body you send and nothing else. `snq` sends only the
   `--flags` you passed (see the `create)` case in `bin/snq`), so every field you omit is
   created blank.
   - `opened_by` *is* set automatically (ServiceNow derives it from the session), which makes
     the ticket *look* correctly attributed in `inc get`. **`opened_by` is not `caller_id`.**
     Triage views and notifications read `caller_id`. Don't let `opened_by` fool you.
   - `assignment_group` *was* auto-filled (`Service Desk`) — so a server-side routing rule does
     exist. It covers group, not caller/impact/urgency. Don't generalize from it.

2. **`priority` is normally derived from `impact` × `urgency`.** Passing `--priority 3` directly
   through the API worked here, but it left the ticket internally inconsistent: P3 with no
   impact/urgency backing it. Observed matrix on this instance (read off real tickets):

   | impact | urgency | → priority |
   |---|---|---|
   | 2 - Medium | 2 - Medium | 3 - Moderate |
   | 2 - Medium | 3 - Low | 4 - Low |
   | 3 - Low | 3 - Low | 5 - Planning |

   So **P3 = Medium/Medium**. Setting impact+urgency is the correct way to get a priority; a
   business rule may recompute `priority` from them and silently overwrite whatever you passed.

**Handling:** On every `inc create`, pass impact and urgency explicitly and set the caller by
sys_id. Get your own sys_id from `snq whoami --json` → `result.user_sys_id` (the human-readable
`snq whoami` does **not** print it; only the JSON does).

```bash
CALLER=$(snq whoami --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["user_sys_id"])')

snq inc create --desc "..." --details "..." \
               --impact 2 --urgency 2 \
               --caller "$CALLER"
```

Then **read the ticket back and check the fields you care about** — `inc get`'s renderer skips
empty values entirely (`if v: print(...)` in `render_detail`), so a blank field is invisible
rather than shown as empty. Absence of a line means the field is unset, and that is easy to
scan past. This is exactly how the miss above survived a readback.

**Related trap (unverified — test before relying on it):** the create/update POST does not send
`sysparm_input_display_value=true`, so reference fields almost certainly require a **sys_id**,
not a display name. That means `--caller "Raynulfo Mata Negrette"`, `--group "Cloud Team"`, and
`--assign "Andry Leal"` are likely to fail or store garbage rather than resolve the name. Use
sys_ids for all three until someone confirms otherwise. Not tested here because verifying it
requires a write to a live ticket.

## 2026-08-07 — a 403 on `sys_audit` / `sys_history_line` is roles, not a dead session

**Symptom:** Trying to pull field-level change history for a ticket to see what changed and
when: `snq --table sys_audit inc list --query "documentkey=<sys_id>"` returns

```
snq: HTTP 403 — authenticated, but your ServiceNow roles don't permit this.
```

`sys_history_line` is worse — it returns HTTP 200 with the right row *count* but every field
`null`, so it looks like a parsing bug rather than a permission wall.

**Cause:** Ordinary `itil` users can read `incident` but not the audit tables. The null-valued
`sys_history_line` rows are ACL field-level filtering, not malformed JSON.

**Handling:** Don't try to reconstruct who-changed-what from the API on this account, and don't
re-auth chasing it — the session is fine. Ask the human to read the Activity stream in the UI,
or infer from current field values plus what the CLI actually sent. `sys_dictionary` is also
closed (returns zero rows), so field metadata — mandatory, read-only, default value, calculated
— is not introspectable either. Determine field behaviour empirically instead.
