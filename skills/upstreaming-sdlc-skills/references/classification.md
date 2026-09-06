# Classification — what crosses and what does not

Every path on a port branch is **shared**, **quarantine**, or **unclassified**. Unclassified
fails the gate: classify it here, then re-run.

`check-upstream-clean.py` holds the literal patterns. This file holds the policy and the
reasoning, so a judgement call on something new has a precedent to follow.

## Quarantine — never crosses

**Personal stacks.** The enterprise runs `java-cqrs` and `react-graphql` on nextgen and
`java-spring` on legacy. `ts-nest` and `react-rest` are personal-project stacks and exist in
the fork only.

| Path | Note |
|---|---|
| `skills/_shared/standards/180-be-layered-service-ts-nest.reference.md` | whole file |
| `skills/_shared/standards/190-fe-react-rest.md` | whole file |
| `skills/_shared/standards/190-fe-react-rest.reference.md` | whole file |
| `skills/_shared/standards/INDEX.md` | the `fe-react-rest` row, and `\|\| stack == ts-nest` in the `be-layered-service` predicate |
| `skills/_shared/selection-facts.json` | `"ts-nest"` and `"react-rest"` in the `stack` enum |

The **mechanism** around these is shared and is the main reason to upstream at all: `stack` as a
selection fact, the stack predicate column in `INDEX.md`, `select_standards.py` filtering on it,
and `180-be-layered-service.md` with its `java-spring` reference. Ship the mechanism with the
enterprise stack values only.

**Dogfood execution artifacts.** `sdlc/**` holds plans and execution state produced by running
the pipeline against the fork itself. None of it exists on the mirror. It is process exhaust,
and its Jira keys pair enterprise ticket numbers with work the enterprise never commissioned.

**Fork identity.** Anything naming the fork or the tooling that runs it: `rjmata95`,
`personal-branch`, the `bridge` remote, `Co-Authored-By: Claude`, `Claude-Session:`,
`claude.ai/code/session`, `Generated with [Claude Code]`. Commit trailers count — they travel in
the message, not the tree, and the gate reads both.

**Machine-local config.** `config.local.md`, `repo-sources.local.tsv`, `.claude/`, `.worktrees/`.
All already git-ignored; the gate re-checks in case an ignore rule is lost.

## Scrub sites — shared files carrying quarantine content

These files go upstream, but each holds quarantine lines that must be dropped in the port. The
list came from running the gate against `personal-branch`; re-run it after any large merge to
find new ones.

| File | What to drop |
|---|---|
| `skills/_shared/config.md` | the Jira Cloud auth and `Subtask` spelling paragraphs |
| `skills/_shared/tools/sync_jira_status.py` | `JIRA_EMAIL` deployment inference and the Basic-auth branch |
| `skills/_shared/tools/config_parser.py`, `find_or_create_subtask.py` | the same auth-mode switch |

The stack rows are gone as of the local-standards overlay: `ts-nest` and `react-rest` now live in
`skills/_shared/standards.local/`, which is git-ignored and therefore cannot appear in a port branch
at all. `test-no-local-value-leaks.sh` in SDLC-skills fails the suite if one creeps back.

## Plausibility quarantine — technically clean, still does not cross

**Jira Cloud support.** The Cloud auth path is genuinely well built: it is env-gated on
`$JIRA_EMAIL`, defaults to the Server/DC Bearer PAT when unset, and leaks no personal data. It
still stays behind, because the enterprise runs Jira Server/DC and a contribution adding Cloud
support invites the question of who needed it. Covers `config_parser.py`'s auth-mode switch, the
`Subtask` vs `Sub-task` spelling, `test-jira-auth-mode.py`, and the Cloud paragraphs in
`config.md`.

This is the category to reason from when something new is clean on content but odd on motive.
The test: *would a reviewer at the enterprise wonder why we built this?* If yes, it waits.

## Shared — the point of the exercise

Everything in the `main..personal-branch` delta not listed above, including the whole
work-facts / standards-selection mechanism, the spec and review skills (`review-spec`,
story-bearing `draft-spec`, validity-then-quality `review-pr`), and every validator and fixture
under `skills/_shared/validators/` that is not stack-specific.

## Review-by-hand

`docs/specs/**` and `docs/plans/**` exist on the mirror, so they are not quarantine by default —
but a spec written for a capability is only shareable when that capability is. The gate warns on
each one; confirm the paired capability is going up in the same port branch, and that the
document names no personal stack, repo or Jira key that does not belong to the enterprise.

## Adding an entry

When new work lands on `personal-branch`, decide its class immediately and record it here plus,
if it needs a pattern, in `check-upstream-clean.py`. Say which of the four categories it falls
in and why in one line — the reasoning is what makes the next call easy.
