# Scenario dispatch — prompt shape, tabulation, sandbox notes

## Prompt shape (one subagent per rep, model `sonnet`)

```
You are the <role> running <skill> step <n> for <story>.
Guidance you must follow is in <GUIDANCE_DIR>: read <file list> (treat them as the skill text
governing you). Load a file ONLY when the guidance tells you to on the branch you are on.
Inputs: <FIXTURES paths>. You may read <real repo path> read-only; do not modify it.
State of the run: <the exact mid-state that tempts the failure>.
Question: <what exactly do you do now / produce>. Be concrete and literal — exact files and
their content, exact calls with arguments, exact status you return. If any of that is not
determinable from the guidance, say precisely what is missing. Do not ask me questions; make
your best call and state assumptions. Dry run — do not run or edit anything.
Write your full answer to <OUT>/<scenario>-<rep>.md, ending with a `## Files loaded` table —
one row per guidance file opened: `| path | words |` — so load per scenario can be tabulated.
Return only a 3-line summary:
(1) <the key choice>, (2) <the key value or shape>, (3) <STOP / status / question raised>.
```

Keep the prompt identical across baseline and after runs except `GUIDANCE_DIR`, `OUT`, and the
fixture version.

## Scenario kinds that find the most

| Kind | Tempts |
|---|---|
| Author from a source the enum forgot | invented cite shapes, silent STOPs |
| Freeze a plan/table from an accepted artifact | zero rows, invented steps, missing defaults |
| Mid-loop at the last allowed red | unbounded loops, escalate with no home, unknown status |
| First run, no cache/ledger | bootstrap ambiguity, "not determinable" commands |
| No-trigger story | disclosed files loaded for nothing, questions asked for nothing |

## Tabulation

Per scenario, one row per rep: shape produced · could not determine · invented · asked · status.
Then a summary row: `<n>/<reps>` for each column. The handoff carries the before and after
summary rows side by side.

## Sandbox notes (Claude Code)

- Fixtures and outputs go under `$TMPDIR` (`~/.claude/jobs/*` is write-denied).
- Run the repo's validation suite with the sandbox disabled and an **absolute** script path; a
  sandboxed `mktemp` fails and some test scripts then misbehave — one resolved its temp dir to
  `$PWD` and removed it on exit. Commit before running any individual test script.
- Worktree sessions refuse `git -C`, compound git invocations, and shell loops that call `bash`;
  use plain commands from the worktree and put validator loops in a script file.
- At most 20 subagents run at once; a dispatch past the cap errors instead of queueing, so record
  which reps failed and re-dispatch them once slots free.
- Wait for a batch with a background `until` loop on the output count, not with sleeps.
