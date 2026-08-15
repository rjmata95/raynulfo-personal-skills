# jira-to-monday — setup & adaptation

## What got standardized (peer skill → shared skill)

| Was hardcoded | Now lives in |
|---|---|
| Board 9074832017, column IDs | `config/jira-to-monday.board.json` |
| Titans / Feature Team 2 | User `teams[]` in local config |
| RingCentral webhook URL | `jira-to-monday.local.json` (gitignored) |
| Status / investment maps | Board defaults (shared) |
| MCP tool names only | Jira: MCP or curl fallback |

## Install — Ray (brain only)

```bash
ln -sfn ~/projects/skills/raynulfo-personal-skills/skills/jira-to-monday \
  ~/projects/brain/.claude/skills/jira-to-monday

cp ~/projects/skills/raynulfo-personal-skills/config/jira-to-monday.ray.example.json \
   ~/projects/brain/.claude/jira-to-monday.json
```

Brain already has `monday-mcp` in `.mcp.json` and `MONDAY_API_TOKEN` in `.env`.

**Still needed before first sync:**
1. Discover FT3/FT4 `mondayDropdownId` values via Monday `get_board_info` on column `dropdown_mkqqd7`
2. Confirm Jira team field values (`FT3` / `FT4` vs full names) with one test JQL query
3. Optional: RingCentral webhook in `.claude/jira-to-monday.local.json`

## Install — Hector (peer)

```bash
ln -sfn ~/projects/skills/raynulfo-personal-skills/skills/jira-to-monday \
  ~/.claude/skills/jira-to-monday   # or project-local symlink if he prefers

cp ~/projects/skills/raynulfo-personal-skills/config/jira-to-monday.hector.example.json \
   ~/.config/jira-to-monday/config.json

echo '{"notifications":{"ringcentralWebhook":"<his webhook>"}}' \
  > ~/.config/jira-to-monday/config.local.json
```

Hector likely has Atlassian MCP — skill will use it automatically. Monday MCP required in his project `.mcp.json`.

## Config merge example

`~/.config/jira-to-monday/config.json`:
```json
{ "extends": "board", "teams": [ ... ] }
```

Agent reads board defaults + user teams + local overlay for webhook.

## Adaptation checklist

- [ ] Monday MCP connected + token set
- [ ] Jira auth (`JIRA_API_TOKEN` or Atlassian MCP)
- [ ] User config with all `mondayDropdownId` filled
- [ ] Dry-run once before live
- [ ] Webhook in local overlay only (never committed)

## Files in this skill

| Path | Purpose |
|---|---|
| `SKILL.md` | Workflow |
| `references/setup.md` | This file |
| `../../config/jira-to-monday.board.json` | Shared board constants |
| `../../config/jira-to-monday.*.example.json` | Per-user team templates |
