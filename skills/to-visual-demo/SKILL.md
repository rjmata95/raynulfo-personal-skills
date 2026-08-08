---
name: to-visual-demo
description: Use when findings, a bug verdict, an investigation result, a comparison, or a recommendation must be delivered as a single self-contained interactive HTML page instead of prose — for a reader who wants a TLDR, side-by-side comparison, real numbers, and a recommendation, and who will not read paragraphs. Triggers on "make me a visual", "build an html", "show me don't tell me", "I'm a visual person", "too much text", "turn this into a demo/page".
---

# To visual demo

Turn a finding into **one self-contained `.html` file** the reader opens and *plays with*.
Not a report with pictures — a page whose interactive part is driven by **the real thing**
(the actual code, or the measured numbers), so the reader can disbelieve you and check.

Reader profile: no time, no patience, low context on your codebase. Wants TLDR, comparison,
numbers, recommendation. Every word earns its place.

## Reading order

The reader goes **verdict → recommendation → 3 tiles**, then often stops. Order the page for that,
not for how you investigated: everything below is *evidence for a call already made*, never a
build-up to it. The recommendation goes near the top.

## Non-negotiables

1. **TLDR first screen.** Verdict banner + the recommendation + 3 stat tiles, above the fold. If
   they read nothing else they still get the answer *and* what to do about it.
2. **Interactive, and honest.** Whatever the reader drives must be the real thing, and the page must
   say what it is. Free-text input always needs an unparseable-input state — never let it throw.
   Three shapes:

   | Finding | Demo drives | Honesty rule |
   |---|---|---|
   | Logic defect / two rules conflict | the rules, transcribed **verbatim** from source | cite `file:line` on the page |
   | Tradeoff / tuning / capacity | real constraints applied to measured data | label measured vs projected **inline, everywhere** |
   | Pure comparison, nothing to run | a toggle between the states | name the source of each state |

   For a tradeoff, add the knob that reveals *which constraint breaks first* (traffic multiplier,
   load factor). A static N-way toggle shows the options; the knob shows why one wins.
3. **Comparison over description.** Two states side by side, or a table with ✓/✗ per row. Never
   describe a difference you can show.
4. **Draw the story.** Anything with a path, sequence, or branch gets a **diagram** — it lands
   faster than any paragraph. Mermaid via CDN, wired in the template. Pick by question:
   *where does it go wrong* → `flowchart` with the bad edge red; *who calls whom* →
   `sequenceDiagram`; *what state* → `stateDiagram-v2`; *where's the data from* → `flowchart LR`.

   One diagram answering the *central* question beats three decorative ones; label only the arrow
   that matters. Three verified traps: Mermaid **cannot parse `var(--x)`** in `classDef`/`linkStyle`
   (the whole diagram becomes "Syntax error in text") — inject hex at runtime, as the template does;
   `linkStyle` indexes **every** link from 0, not just branches, so an off-by-one paints the
   *correct* edge red; and it needs a CDN fetch — hand-write the SVG if the page must work offline.
5. **Every number carries provenance and a caveat.** Where it came from, what's partial, what you
   could NOT verify. Unverified claims get labeled, not dropped.
6. **A recommendation, stated as a decision, near the top.** Bold the call. Include the "don't do X"
   if that's the real advice. Cost/tradeoff and reasoning go *under* it. If it needs the evidence
   below to make sense, it isn't written plainly enough yet.
7. **Render it and look at it.** Non-negotiable — see the loop below.

## Build

Copy `template.html`, fill the marked slots, delete unused blocks. Palette is baked in
(validated light+dark) — do not invent colors. Sections, in order:

| # | Block | Carries |
|---|---|---|
| 1 | Verdict banner | the one sentence that changes the reader's mind |
| 2 | **Recommendation** | the call, bolded, with cost/tradeoff — **above the fold, not at the end** |
| 3 | 3 stat tiles | the 3 questions the reader actually has, answered |
| 4 | Diagram | the path/sequence/branch, with the bad edge marked |
| 5 | Live demo | real logic + mode toggle (the comparison card sits *inside* this grid) |
| 6 | Comparison | signal-by-signal ✓/✗ |
| 7 | Data | numbers with source + partial-data caveat |
| 8 | Detail / diff | the code change, caveats, scope limits |

**Shape the demo to the finding.** The template's `sideA`/`sideB` are neutral on purpose —
rename them. If one side is wrong, mark it ✗. If two sides merely *disagree* and the fix is to
pick one, mark neither ✗ and let the recommendation choose. Add a 3rd mode when "not every case
diverges" is part of the point.

Word budget: banner ≤ 60 words, tile subtitle ≤ 15, prose block ≤ 80 (bullets excluded).
Over budget means cut. Accuracy wins over the budget — but cut first.

## The verify loop — do not skip

Layout and interaction bugs are invisible in source. Every page built this way has had at least one.

```bash
cd <dir> && python3 -m http.server 8749 &   # file:// is blocked in Playwright; cd must be same command
```
Port busy → fails silently and navigate errors confusingly. Check with `lsof -ti:8749` before and
after. Edited the file but nothing changed? Cache — append `?v=2`.

1. navigate → screenshot
2. **hover/click every interactive element**, screenshot each state
3. **dark mode**: `data-theme="light"` is hardcoded, so the media query is dead — flip it with
   `document.documentElement.setAttribute('data-theme','dark')` or the toggle
4. **resize to ~375px** — the template ships a 900px breakpoint; overflow shows up here
5. console clean? (ignore the favicon 404 — it always fires) → fix → re-render

**Screenshots:** Playwright MCP is pinned to the repo root — an absolute path outside it errors,
and a bare filename lands in the repo root. Pass a bare filename, then `mv` it to your tmp dir.
When done: kill the server, and delete stray `.png` and the whole `.playwright-mcp/` dir
(it also collects `.yml` snapshots and `.log` files) from the repo.

Assert, don't squint: `getComputedStyle` in `browser_evaluate` catches what a screenshot won't
(a var resolving to black, a collapsed height).

## Deliver

Give the **absolute path** and 3-5 bullets on what's in it and what to click. State what you
verified. Then the same verdict in one line of text — some readers never open the file.

## Common mistakes

| Mistake | Fix |
|---|---|
| Fake/mocked demo logic | Transcribe from source; cite `file:line` on the page |
| Prose paragraphs | Table, tile, or diff |
| Numbers with no source | Add source + caveat, or cut the number |
| Chart where a number would do | One big number beats a 1-bar chart — delete the split bar |
| Tooltip covers what it explains | Flip its direction; confirm by screenshot |
| Calling a disagreement a "bug" | Two correct-but-conflicting rules → neutral framing, no ✗ |
| Static prose the demo contradicts once touched | Derive that sentence from state, don't hardcode it |
| Rounding that hides a breach (`Math.round(0.33)`→"0% over") | Round toward the unfavorable side, or add a decimal |
| Shipped without rendering | Run the loop; you have layout bugs |
| Recommendation at the bottom | Move it under the verdict — the reader may stop before it |
| Diagram that decorates instead of explaining | One diagram, answering the central question, bad path marked |
| `--` inside an HTML comment | Terminates it early and the rest leaks as visible page text |
