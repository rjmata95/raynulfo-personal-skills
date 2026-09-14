---
name: optimizing-skill-context
description: Use when a skill, shared reference, or agent doc must be reviewed or rewritten for goal clarity, context load, or inconsistent agent output — before any edit, and before claiming the rewrite works.
---

# Optimizing skill context

Baseline Sonnet-class subagents on the current text, classify what they could not determine or
invented, rewrite, re-run the same scenarios, compare. This skill is the recipe and the bar; the
writing levers live in `writing-for-agents` and `superpowers:writing-skills` (required background).

## The bar

Every agent the doc serves must be able to name three things from the text alone:

| Piece | Question the text must answer | Failure smell |
|---|---|---|
| **Goal** | What shape is the output? Which fields, which entry per what? | Agents invent a shape; each run differs |
| **Standard** | How do we do it here? | Rules restated in several files, drifting |
| **Exit condition** | How does the agent know it is done without a human? | "Not determinable from the guidance"; loops with no bound; escalate with no home |

Judge the doc against these before judging its prose.

## Recipe

1. **Map the chain.** List every file the feature loads per phase (design, plan, implement, review),
   which are always-loaded and which are disclosed, and where the same meaning appears twice.
2. **Pick a guinea pig.** A real repo plus a real artifact (prototype, spec, plan) the feature is
   for. Write 2–4 fixtures in `$TMPDIR/<slug>/fixtures/`: the input each phase would receive.
3. **RED — baseline.** Snapshot the current files to `$TMPDIR/<slug>/baseline/`. For each phase
   write one scenario that tempts the failure (a mid-loop state, a missing value, a source the enum
   forgot). Dispatch **3 reps for authoring scenarios, 5 for loop/decision scenarios**, model
   `sonnet`, using `references/scenario-dispatch.md`. Read every output; tabulate per scenario:
   what shape they produced, what they could not determine, what they invented, what they asked.
4. **Classify each failure by form** (`writing-skills` § Match the Form to the Failure): missing
   shape → recipe or template slot; value agents invent → a default in the SSOT; state lost across
   dispatches → a file ledger; rule skipped under pressure → rationalization table; behaviour that
   depends on a condition → predicate the agent can evaluate without loading the disclosed file.
5. **GREEN — rewrite.** One SSOT holding goal + standard + exit condition; every hook becomes
   trigger + pointer; every packet an agent actually receives (implementer prompt, dispatch
   template) gets a structural slot for the new material; coined words replaced by pretrained
   ones. Update fixtures to the new shape.
6. **Re-run the same scenarios** into `$TMPDIR/<slug>/after/`. Variance is the metric: reps should
   converge on the same shape. Close each residual "not determinable" with a default or a slot.
7. **Test the no-trigger path** (3 reps): a story the feature does not apply to. Confirm the agent
   opens no disclosed file, asks nothing, writes at most one recorded skip line.
8. **Ship.** Run the repo validators (`references/scenario-dispatch.md` § Sandbox), commit before
   any test script runs, write the handoff with the before/after table and the disposition of any
   prior review, open the PR.

**Done when:** every scenario's after-run converges, the no-trigger run loads nothing, validators
pass, and the handoff carries both tables.

## Common mistakes

- GREEN fixtures still in the old shape: agents flag the fixture and the run measures nothing.
- Letting subagents return full outputs. Have them write to a file and return three lines.
- Prohibitions where a recipe was needed: "never invent a serve step" made agents refuse to write
  any capture code; a four-line recipe made them write the right one.
- Growing the always-loaded hook. Cost lands on every run; the SSOT loads only when it fires.
