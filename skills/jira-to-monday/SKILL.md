---
name: jira-to-monday
description: Sync Jira user stories to a Monday.com team board by configured teams. Pulls active stories, reconciles against Monday items via Jira Link column, auto-creates missing items (subitems under tracked Epics), syncs status and release dates. Triggers on "sync teams", "team board sync", "sync jira monday", "jira to monday", "team sync".
---

# Jira → Monday team board sync

Reconciles Jira Stories in active development against a Monday board, team by team.
Jira is source of truth for what should exist; the **Jira Link column** is the canonical
Monday identifier.

## Before you run — load config

Config is **not** hardcoded in this skill. Resolve it in this order:

1. `$JIRA_TO_MONDAY_CONFIG` — absolute path to a JSON file (testing / CI)
2. `.claude/jira-to-monday.json` in the **current project root** (brain install)
3. `.claude/jira-to-monday.local.json` merged on top (secrets overlay; gitignored)
4. `~/.config/jira-to-monday/config.json` + optional `config.local.json` overlay

If none exist, stop and tell the user to copy an example:

```bash
mkdir -p ~/.config/jira-to-monday
cp ~/projects/skills/raynulfo-personal-skills/config/jira-to-monday.hector.example.json \
   ~/.config/jira-to-monday/config.json
# or for brain-only:
cp ~/projects/skills/raynulfo-personal-skills/config/jira-to-monday.ray.example.json \
   ~/projects/brain/.claude/jira-to-monday.json
```

**Merge rule:** User config may set `"extends": "board"`. When present, deep-merge
`config/jira-to-monday.board.json` from this repo (board ID, column IDs, status maps)
under the user file. Local overlay files merge last and win on key conflicts.

**Validate before sync:**
- Every team in `teams[]` has non-null `jiraTeamName` and `mondayDropdownId`
- `monday.boardId` resolves
- If `notifications.ringcentralWebhook` is null/missing, skip Step 7 (no error)

Shared board defaults live at `config/jira-to-monday.board.json` in
`raynulfo-personal-skills`. Examples: `jira-to-monday.hector.example.json` (Titans + FT2),
`jira-to-monday.ray.example.json` (FT3 + FT4).

## Contract: Jira Link as source of truth

For each Jira story, before marking **TO CREATE**, scan the team's Monday items (parents
**and** subitems) using column IDs from config (`monday.columns.jiraLink`,
`monday.columns.subitemJiraLink`):

1. Jira key in any parent Jira Link → exists, do NOT create
2. Jira key in any subitem Jira Link → exists, do NOT create
3. Not found → CREATE

Before **TO UPDATE**, locate the Monday item by Jira Link value (not by name).

**Board-wide dedup (mandatory):** Before CREATE, search the entire board with
`searchTerm: "DSC-XXXXX"`. If found anywhere → SKIP and log location.

## Execution mode

Ask unless the user already specified:

> Run in **dry-run** (report only) or **live** (apply changes)?

Default: **dry-run**.

## Tooling — Monday

Requires Monday MCP (`monday-mcp` in project `.mcp.json`; token in `MONDAY_API_TOKEN`).

| Operation | Tool |
|---|---|
| Board schema | `get_board_info` |
| Paginated items + filters | `get_board_items_page` (`includeSubItems: true`) |
| Create parent / subitem | `create_item` |
| Update columns | `change_item_column_values` |
| Delete / archive | `delete_item` / `archive_item` (stale only, user confirms) |

Use config values for `boardId`, column IDs, `defaultGroupId`, team dropdown filter
(`monday.columns.teamAssignment` + each team's `mondayDropdownId`).

## Tooling — Jira

Prefer **Atlassian MCP** when connected (`jira_search`, `jira_get_issue`).

If Atlassian MCP is unavailable (typical in brain), use **curl** against Jira DC 10.3
per `jira-bulk-operations` / `jira-cli` skills:

```bash
curl -s -G "https://jira.chenmed.com/rest/api/2/search" \
  --data-urlencode "jql=issuetype = Story AND team = \"${JIRA_TEAM}\" AND status in (...)" \
  --data-urlencode "fields=summary,status,assignee,team,duedate,customfield_11900,labels" \
  --data-urlencode "maxResults=50" \
  -H "Authorization: Bearer $JIRA_API_TOKEN" --insecure
```

Never guess JQL team names — read `jiraTeamName` from config per team.

## Execution steps

### Step 1: Get board info

Confirm `monday.boardId` is accessible; verify column IDs still match config.

### Step 2: Pull Monday items per configured team

For each entry in `config.teams[]`, filter `get_board_items_page`:

```
filters: [{"columnId": "<teamAssignment>", "compareValue": [<mondayDropdownId>], "operator": "any_of"}]
includeColumns: true
includeSubItems: true
columnIds: ["status", "<teamAssignment>", "<jiraLink>", "<releaseDate>"]
limit: 100
```

Paginate with `nextCursor`. Extract Jira keys from link columns and item names (DSC-XXXXX fallback).

### Step 2b: Epic map

For Monday parents with subitems + Jira link, call Jira to check `issue_type == Epic`.
Build `{ jiraEpicKey: mondayParentItemId }`.

### Step 3: Query Jira per team

For each team, JQL template:

```
issuetype = Story AND team = "<jiraTeamName>" AND status in (<activeStatuses from config>) AND labels != "<excludeLabel>"
```

Fields from `config.jira.jqlFields`. Paginate with `startAt`.

### Step 3b: Story-to-Epic map

For each Epic in the Epic map:

```
issuetype = Story AND "<epicLinkJqlField>" = <EPIC_KEY> AND status in (...)
```

Build `{ storyKey: epicKey }`.

### Step 4: Compare and reconcile

Per team, build **TO CREATE**, **TO UPDATE**, **STALE** lists per the Contract.

**Placement:** Story in Story-to-Epic map → subitem under Epic parent; else top-level in
`defaultGroupId`.

**Step 4c — validate stale (mandatory):** For each stale item with Jira link, fetch Jira status:
- Done → move to TO UPDATE (Ready for Prod / Ready for prod) — update-only rule
- Still active but missing from team query → flag "team reassignment suspected"
- Other → truly stale, user review; **never auto-delete**

### Step 4b: Release date validation

Pre-condition: Jira `duedate` required before CREATE.

```
Monday Release Date = Jira Due Date + 1 business day (skip weekends)
```

| Jira Due (day) | +1 lands on | Monday Release |
|---|---|---|
| Mon–Thu | Tue–Fri | Due + 1 day |
| Fri | Sat | Due + 3 days (next Mon) |
| Sat | Sun | Due + 2 days (next Mon) |
| Sun | Mon | Due + 1 day |

Flag: missing Jira due, missing Monday date, mismatch (report only in live), weekend violation.

Live mode: set empty Monday release dates from calculation; do NOT auto-fix mismatches.

### Step 5: Execute

**Dry-run:** report only.

**Live — before CREATE:**
- Investment Category (`customfield_11900`) must be set; if empty → ask user
- Unknown category → ask prefix + Issue Type
- No Jira due date → block CREATE

**Create top-level:** `create_item` with status, issue type, team dropdown, jira link, release date.

**Create subitem:** `create_item` with `parentItemId`, subitem link + release date columns.

**Update:** `change_item_column_values` for status (automatic, no confirmation).

**Stale:** present list; user chooses delete / archive / leave.

Status labels from `config.statusMapping` (parent vs subitem).

Investment prefixes/types from `config.investmentCategory`.

### Step 6: Summary report

```markdown
## Team Sync Report — [date]
### Mode: [DRY-RUN | LIVE]

### [team.label] (per configured team)
| Action | Jira Key | Summary | Jira Status | Monday Status | Category | Placement |
...

### Date Issues
...

### Summary
- Per-team counts + totals
```

Always link Jira keys: `[DSC-XXXXX](https://jira.chenmed.com/browse/DSC-XXXXX)`.

### Step 7: RingCentral notification (optional)

Only if `notifications.ringcentralWebhook` is set (local overlay — never commit URLs).

POST Adaptive Card summary via curl. Webhook failure → log, do not block report.

## Constraints

- NEVER create if Jira key exists anywhere on the board
- NEVER delete without explicit user confirmation
- NEVER modify items outside configured team dropdown values
- Auto-create/update in live mode (creates/updates need no confirmation; stale does)
- Always set Jira Link on create
- Epic stories under tracked Monday Epic → subitem, not top-level
- API failure → STOP and report; no silent retry
- JQL returns 0 → warn before flagging all Monday items stale

## Error handling

| Condition | Message |
|---|---|
| No config file | Print setup path from examples |
| Team missing `mondayDropdownId` | Name the team; block sync |
| Atlassian MCP down | Fall back to curl; if no token, stop |
| Monday MCP down | "Monday MCP not connected. Reconnect and retry." |
| Board not found | Report board ID from config |

## Install (brain-only, no global clutter)

```bash
ln -sfn ~/projects/skills/raynulfo-personal-skills/skills/jira-to-monday \
  ~/projects/brain/.claude/skills/jira-to-monday

cp ~/projects/skills/raynulfo-personal-skills/config/jira-to-monday.ray.example.json \
   ~/projects/brain/.claude/jira-to-monday.json
# Fill mondayDropdownId for FT3/FT4, then optionally:
# echo '{"notifications":{"ringcentralWebhook":"..."}}' > ~/projects/brain/.claude/jira-to-monday.local.json
```

Do **not** symlink into `~/.claude/skills/` unless the user explicitly wants it everywhere.

See `references/setup.md` for peer (Hector) install and adaptation checklist.
