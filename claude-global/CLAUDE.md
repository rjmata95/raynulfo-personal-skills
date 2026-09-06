# Global Claude Code Instructions

## Communication Style

I'm a Technical Executive switching context multiple times an hour. I don't read code, but I understand concepts. Value my time: use only enough words for me to make informed decisions. If it won't steer my decision-making, don't say it. Tell me explicitly what you need from me to achieve my goal.

I'm visual. I like recommendations and TLDRs.

If you start being too verbose, I'll get mad and remind you to follow my communication style.

### User replies

- Lead with the answer or recommendation — not preamble, not a survey.
- TLDR first; detail only when I need it to decide.
- Tables, diffs, and visuals over paragraphs. **Bold the decision**; reasoning below it.
- Match length to the task. One-line ask → one-line answer.
- Never lead with a bare ID. Human name first, ID in parens, file:line: *"A&P editor (MN-PROB-007) — `05-problems.md:126`"*.
- For structure, comparison, or layout — build a throwaway `.html` and give me the path. Skip for small stuff.
- Full paths/URLs. No engagement bait.

### Agent-facing docs

**Agent-facing docs** (skills, rules, `AGENTS.md`, `CLAUDE.md`, handoffs, specs agents execute): read `writing-for-agents` before writing. User replies use **User replies** above only.

## Git Worktrees

**Collaborative repositories** (shared remote, team use): prefer a worktree at `<repo-root>/.worktrees/<slug>/` over checking out a branch in the main clone.

**Local-only or personal repositories:** ask before creating a worktree.

## PR Review

Use the **`/review-pr`** skill (Chenmed-SDLC bundle) for any PR or pre-push branch review. The full workflow — tiered parallel diff reads, requirement-artifact normalization, the three review lenses, the severity taxonomy, and draft-then-post-on-approval — lives in that skill, so it travels with the repo instead of this file.

## SDLC-skills fork

`CascadeProjects/skills/SDLC-skills` is a personal fork of an enterprise repo. Personal work
lands on `personal-branch`; `main` is a read-only mirror of enterprise main. Before porting
anything toward enterprise, cutting a `feat/*` port branch, or judging whether a change is safe
to share, use the **`upstreaming-sdlc-skills`** skill — the topology, the port procedure, the
company-laptop bridge, and the leak gate live there.

That repo's local standards overlay — `skills/_shared/standards.local/` and
`selection-facts.local.json` — is git-ignored on purpose, so it has no history and no backup
there. This repo is its backup. **After capturing or editing a local standard, run
`bin/sdlc-overlay backup` and commit here**; `restore` puts it back on a fresh clone or after a
bad `git clean`.
