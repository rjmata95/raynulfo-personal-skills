# Handoff — overlay lives out-of-tree via config (for the planning phase)
---
route: full
spec: docs/specs/2026-09-07-local-standards-overlay-spec.md
parent_work_item: DSC-27524
grounding: explored
ac_origin: this file — the spec lists distribution as OUT of scope; step 0 below is the surgical scope_delta that brings it in
slug: overlay-out-of-tree
domain: sdlc-skills
platform: nextgen
repos:
  - { name: Chenmed-SDLC-skills, platform: nextgen, grounding_status: confirmed }
---

<!-- This file is machine-local (.git/info/exclude). It plans personal-fork work that has not been
     agreed with enterprise. Mirror lives in raynulfo-personal-skills/overlays/sdlc-skills/handoffs/. -->

## Goal / Definition of Done

**Problem.** The local standards overlay is git-ignored, which closes the leak and opens a loss:
inside the working tree, `git clean -fdx` or a hard reset on a dirty tree deletes it permanently,
a fresh clone has none, two machines drift, a dead laptop takes it. It happened once already on
2026-09-07 (agent-run `git reset --hard && git clean -fd`; recovered from a transcript). For the
fork owner this is mitigated by `raynulfo-personal-skills/bin/sdlc-overlay`. For any team adopting
the bundle there is nothing, and the failure mode is silent permanent loss.

**Decision taken (2026-09-08, fork owner):** option C — make the overlay's location a config
value, so a team can point it at a directory inside its own private repo. The overlay then stops
being *uncommitted* and becomes *committed somewhere else*. The leak guarantee is unaffected: it
comes from the path being outside the tracked tree, not from the files being untracked.

**Rejected:** export/import commands (option B) — under C they reduce to `git` in the private repo.
The only residual use is moving between machines that do not share that repo, which is not worth
a second mechanism.

**Definition of Done**

1. `standards_local_dir` and `selection_facts_local` in `config.md` / `config.local.md` are
   **honoured by every reader**, code and prose. Today they are declared and ignored.
2. **Default unchanged**: with neither key set, behaviour is byte-identical to today — in-tree
   paths, `.gitignore` entries still apply, the suite passes as it does now.
3. With the keys pointing outside the repo, the full suite passes, `--with-provenance` reports
   `local` / `local-override` exactly as in-tree, and `capture-standard` authors to the configured
   location.
4. **The leak test fails loudly when the configured facts file is unreadable.** It must not print
   `OK: no local overlay on this machine` because a path was wrong. A guard that cannot find its
   token list has nothing to guard with, and must say so.
5. Spec AC-T5 becomes true instead of aspirational, and the spec's Out-of-Scope line about
   distribution is replaced by a scope_delta EXPANDED entry (step 0).

## Grounded contracts & dependencies

Verified by reading the code on 2026-09-08 at `personal-branch` @ `34fb234`.

| Fact | Where | Consequence for the plan |
|---|---|---|
| The two keys are declared with in-tree defaults | `skills/_shared/config.md:132-133` | Keep them; change readers, not the keys |
| Selector **hardcodes** `shared / "standards.local"` and `shared / "selection-facts.local.json"` | `skills/_shared/tools/select_standards.py:47-54` (`resolve_local_index_path`, `resolve_local_facts_path`) | The primary code change; everything else follows this |
| A config loader already exists: `config_parser.load(config_dir)` | `skills/_shared/tools/config_parser.py`; used by `check-config.py:16,95` | Reuse it. Do not add a second parser. Check how it handles a missing `config.local.md` — the selector must still run with no config at all |
| `${adr_repo_path}`-style expansion is the config idiom for derived paths | `config.md:16-28` | Out-of-tree values should accept the same expansion and `~` |
| Leak test reads the facts file at a **fixed** in-tree path and exits 0 when absent | `skills/_shared/validators/test-no-local-value-leaks.sh:8-9` | Must follow config, and DoD #4 applies |
| `check-index-vocabulary.py` / `check-selection-facts.py` take `--local-facts` **explicitly**; the suite runner passes the in-tree path | `run-validation-suite.sh` (4 references) | Runner must resolve through config, or the validators default through it |
| `test-local-overlay-ignored.sh` asserts the in-tree paths are git-ignored | 5 references | Still correct for the default; add the out-of-tree case, do not remove this |
| Reviewer prompts and implementer prompt resolve an id "across `standards/` then `standards.local/`" | `implementer-prompt.md`, `code-quality-reviewer-prompt.md`, `vibe-reviewer-prompt.md`, `review-pr/SKILL.md` | Prose: name the config key once, e.g. "the overlay directory (`standards_local_dir`)" — do not repeat a path |
| `capture-standard` writes `_shared/standards.local/9NN-<id>.md` | `capture-standard/SKILL.md` (8 refs), `shapes.md` (6 refs) | Prose: same single-naming rule. Author to the configured dir |
| `standard-graduation.md` moves files between the two dirs | 4 refs | Prose: same |
| Full inventory: **22 files** reference an overlay path | `grep -rn "standards\.local\|selection-facts\.local" skills/` | Split the plan by **code** (6 files: selector, 2 validators, leak test, suite runner, ignored-test) vs **prose** (16). Prose changes are one naming rule applied everywhere; code changes each need a test |

**Depends on:** nothing unmerged. All of the above is on `personal-branch`. Enterprise `main` gains
the selection engine when the two in-flight PRs merge (see memory: enterprise-unmerged PRs); this
work ports on top of PR #3.

## In-Scope / Out-of-Scope

**In:** config-driven overlay location in every reader; default-unchanged guarantee with a test
that proves it; leak test failing loudly on an unreadable configured path; a second suite pass in
CI-style with the overlay relocated to a temp dir, so the out-of-tree path is exercised on every
run, not only on machines that set it; spec scope_delta.

**Out:** syncing the overlay between machines (that is the private repo's job); `git` operations
on the private repo; migrating the fork owner's existing `sdlc-overlay backup/restore` script
(it keeps working; it becomes optional once config points at the mirror directly).

## Open decisions the planner must surface — do not pick silently

1. **Stack override in `config.local.md`** — rung 2 of `_shared/stack-resolution.md` is a bare
   per-machine `stack`. It is per-machine; a stack is per-repo. Undecided between:
   **(A)** delete rung 2; **(B)** `stack_overrides: [{repo, stack}]` matching the existing
   `repo_overrides` idiom, at rung 2; **(C)** same shape, moved below the read-the-repo rung.
   Fork owner has not chosen. Ask before touching `stack-resolution.md` or its five pointer sites.
2. **Relative-path base.** If a configured value is relative, relative to what — the bundle root,
   the config file, or cwd? The existing `${adr_repo_path}` idiom sidesteps this by being absolute
   after expansion. Recommend: require absolute-after-expansion and reject anything else at
   `check-config` time.
3. **Does `config.local.md` get a second key or a directory?** Two keys today (dir + facts file).
   One `overlay_dir` with fixed filenames inside is simpler and cannot drift into two locations.
   Trade: it is a config contract change to a key that shipped declared-but-unused, so the blast
   radius is small now and larger later. Recommend one key; decide before the code change.

## Open risks the planner must respect

- **The default must not move.** Any behaviour change for a machine with neither key set is a
  regression, and the enterprise reviewer will read it as one. Prove it with a test, not a claim.
- **Loud failure over quiet success** in every guard that reads the configured path. A missing
  path is a config error, not "no overlay".
- **The `.gitignore` entries stay.** They protect the default case. Relocating does not retire them.
- **Prose sprawl.** 16 prose files name the path. The fix is one sentence per file naming the
  config key, not a find-and-replace to a new literal that will be wrong again.
- **The leak test's token source moves with the facts file.** If config points somewhere the test
  cannot read, DoD #4.

## Security flags

None. No secrets, no PHI, no network. A misconfigured path is a correctness risk, not a
confidentiality one — the leak direction is unchanged.

## Planning approval

One complete-set review by an independent human/SME is required before Jira or implementation.
Fork owner reviews; this is personal-fork work until it ports.
