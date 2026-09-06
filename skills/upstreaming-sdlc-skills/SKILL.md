---
name: upstreaming-sdlc-skills
description: Port a dogfooded improvement from the personal SDLC-skills fork to the enterprise repo without leaking personal-only content. Use when working on the SDLC-skills repo and the task is to upstream/contribute/port a change to enterprise, cut a port branch, sync main from enterprise, rebase personal-branch, judge whether something is safe to share, or set up the company-laptop bridge remote.
---

# Upstreaming SDLC-skills

`SDLC-skills` is dogfooded in a personal fork and selectively contributed back to the
enterprise repo. Two kinds of content live side by side in that fork, and this skill exists
to keep them apart.

- **Shared** — process improvements worth contributing (the stack-selection mechanism,
  validators, spec/review skills). These are the point of the exercise.
- **Quarantine** — content that reveals the fork exists or serves projects the enterprise
  does not have (personal stack standards, Jira Cloud support, dogfood execution artifacts,
  Claude commit trailers, personal remotes and branch names).

Read [`references/classification.md`](references/classification.md) before deciding what a
given change is. Run `check-upstream-clean.py` before every push of a port branch — the
gate, not your reading of the diff, is what says a branch is clean.

## Topology

The personal repo `rjmata95/SDLC-skills` is the transport. The personal laptop cannot reach
the enterprise repo; the company laptop reaches both.

```
curity-tech/SDLC-skills          <-- enterprise; company laptop only
    |  ^
    |  |  (2) company laptop pushes port branch, opens PR
    v  |
  main |                          "mirror" — enterprise main, verbatim
    |  |
    v  |
rjmata95/SDLC-skills             <-- personal repo; the bridge
    |
    +-- main                     mirror. Read-only on the personal laptop.
    +-- personal-branch          dogfood. Everything, quarantine included.
    +-- feat/<name>              port branch. Cut from main. Gated. Short-lived.
```

Three rules hold the whole thing together:

1. **`main` is a mirror.** It is written only by the company laptop pushing enterprise main.
   The personal laptop fetches it and never commits to it.
2. **A port branch is cut from `main`, never merged from `personal-branch`.** Content crosses
   by hand; history never does.
3. **`personal-branch` rebases onto `main`.** Never merge. Rebasing keeps the personal delta a
   clean linear list, which is what makes `git diff main..personal-branch` an honest audit.

## Porting a capability (personal laptop)

1. **Refresh the mirror.**
   ```
   git fetch origin
   git switch main && git reset --hard origin/main
   ```

2. **Cut the port branch.** Name it the way the enterprise repo names branches — `feat/<slug>`,
   with a slug describing the capability. The branch name is visible on their PR.
   ```
   git switch -c feat/<slug> main
   ```

3. **Port by state, not by history.** Squash-merges on `personal-branch` make commits
   unportable, and cherry-picking would drag quarantine across anyway. Instead, diff the
   capability's paths and apply them by hand:
   ```
   git diff main..personal-branch -- <paths for this capability>
   ```
   Apply hunk by hunk, dropping every quarantine hunk. Where a shared file carries both —
   `INDEX.md` rows, `selection-facts.json` stack values, `config.md` keys — take the mechanism
   and leave the personal rows behind.

4. **Run the gate.** From the SDLC-skills repo root:
   ```
   python3 ~/.claude/skills/upstreaming-sdlc-skills/check-upstream-clean.py
   ```
   It exits non-zero on any quarantine hit and on any path it cannot classify. An unclassified
   path is a real finding: decide what it is, then record the decision in
   `references/classification.md` so the next run knows.

5. **Commit once, clean.** One commit, message in the enterprise repo's style, no
   `Co-Authored-By` or `Claude-Session` trailers, no reference to the fork.

6. **Push and hand off.**
   ```
   git push origin feat/<slug>
   ```

## Handing off (company laptop)

**One-time bridge setup.** In the enterprise clone, add the personal repo as a second remote
whose refspec makes fetching `personal-branch` impossible:

```
git remote add bridge git@github.com:rjmata95/SDLC-skills.git
git config --replace-all remote.bridge.fetch '+refs/heads/main:refs/remotes/bridge/main'
git config --add         remote.bridge.fetch '+refs/heads/feat/*:refs/remotes/bridge/feat/*'
git config remote.bridge.tagOpt --no-tags
```

Always push to either remote with an explicit refspec, so no branch travels by accident:
`git push <remote> <local>:refs/heads/<remote-branch>`.

**Send a port branch upstream.** Take the branch's *content* and leave its commit behind, so
authorship, trailers and dates are all corporate:

```
git fetch bridge
git fetch origin
git switch -c feat/<slug> origin/main
git read-tree -u --reset bridge/feat/<slug>   # index+worktree := port branch content
git status                                    # confirm the change set is what you expect
git commit -m "<enterprise-style message>"
git push origin feat/<slug>
```
Then open the PR against `curity-tech/SDLC-skills` `main`.

**Mirror enterprise main back down**, after the PR merges or any time their main moves:
```
git fetch origin
git push bridge origin/main:refs/heads/main
```

## Syncing back (personal laptop)

After the mirror moves:
```
git fetch origin
git switch main && git reset --hard origin/main
git switch personal-branch && git rebase main
```
The rebase drops the commits that landed upstream and leaves the personal delta. Confirm with
`git diff --stat main..personal-branch` — it should shrink by exactly what was ported.

## Guardrails

Install the pre-push hook once per clone so the gate runs whether or not an agent remembers to.
It is local to `.git/hooks/`, so it never ships:
```
cp ~/.claude/skills/upstreaming-sdlc-skills/references/pre-push-hook.sh \
   <sdlc-skills-clone>/.git/hooks/pre-push
chmod +x <sdlc-skills-clone>/.git/hooks/pre-push
```
It gates pushes of `feat/*` and refuses any push to `main`, and lets `personal-branch` through
untouched.

Keep these true at all times:

- Personal work lands on `personal-branch`. Verify the current branch before committing in
  SDLC-skills.
- The company laptop fetches only `main` and `feat/*` from `bridge`, by refspec, and pushes
  only with an explicit refspec.
- Every port branch passes `check-upstream-clean.py` before it is pushed.
- When a new capability is built on `personal-branch`, classify it in
  `references/classification.md` while it is fresh. Classification written later is
  classification guessed.
