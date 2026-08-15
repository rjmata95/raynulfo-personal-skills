---
name: meeting-notes
description: Turn a raw anarlog meeting export sitting in the brain's meetings/inbox-raw/ into a structured note (summary, decisions with owners, action items with owners and dates, open questions, related-note links, YAML frontmatter) filed under meetings/ in ~/projects/brain. Use when a new file appears in meetings/inbox-raw/, when the user says "process this meeting", "digest the anarlog export", or references a raw transcript export from anarlog.
---

# Meeting notes

Digests a raw anarlog JSON export (transcript, per-channel speaker data, and optionally a
memo/summary if the user configured one) into a structured, queryable note in the brain — the
same raw-vs-digested split the brain already uses for `research-raw/` → `research/`.

Upstream of this skill: `anarlog-sync <meeting-id>` (in `raynulfo-personal-skills/bin/`) exports
a finished anarlog meeting to `~/projects/brain/meetings/inbox-raw/<meeting-id>.json`. This skill
picks up from there. It never talks to anarlog itself — no CLI calls, no MCP, no SQLite.

## Checklist

1. Locate input
2. Read the template
3. Reconstruct speaker-labeled transcript
4. Draft the structured note
5. Link related notes
6. Write, index, and clean up

### 1. Locate input

If not given a path, look in `~/projects/brain/meetings/inbox-raw/` for `.json` files. If
there's more than one unprocessed file, ask which to do first rather than silently batching all
of them.

### 2. Read the template

Read `~/projects/brain/templates/meeting-note.md` first — it is the canonical shape (frontmatter
fields, section order). Do not invent a different structure.

### 3. Reconstruct speaker-labeled transcript

The export's flat `transcripts[0].text` has no speaker labels — build them yourself from three
fields in the same object:

- `participants[]` — `human_id` → `display_name` (skip entries with an empty display_name).
- `transcripts[0].words[]` — each word has a `channel`: **0 is always the local mic (you), 1 is
  always system audio** (everything coming out of the speakers/headphones — a Zoom/Meet call's
  other side, a video, etc.). There are never more than these two raw channels.
- `transcripts[0].speaker_hints[]` — entries where `type` is `user_speaker_assignment` carry a
  JSON string in `value` like `{"human_id":"...","channel":0}`. Parse these to get a
  channel → human_id map, then resolve to a display name via `participants[]`.

Group consecutive same-channel words into turns and render as `<name>: <text>`, e.g.:
```
Ray: Hey, this is a quick test meeting...
youtuber: The Garmin Circus, Garmin's long awaited answer...
```
If a channel has no `user_speaker_assignment` hint (the user never assigned anyone in the app),
label it `Speaker 0` / `Speaker 1` — don't guess a real name from content.

**The hard ceiling — say this in the Summary whenever it applies, don't paper over it:**
channel 1 is a single mixed audio feed. On a call with exactly one other person, its label is
reliable. On a call with two or more other people, everyone on "the other side" lands on the
same channel, indistinguishable from each other — the note can say "the other participants"
but must not attribute a specific line to a specific one of them without other evidence (they
say their own name, or it's obvious from context who's who). Same logic for a shared
conference-room mic, except there both you and everyone else are on the *same* single channel,
so channel alone gives no separation at all — treat that case as unlabeled and rely on the
existing diarization caveat below.

### 4. Draft the structured note

From the speaker-labeled transcript (and the memo/summary, if present), produce:

- **Summary** — 3-6 sentences: what the meeting was actually about and how it landed.
- **Decisions** — one bullet per decision, each with an owner. Omit the section if none were made.
- **Action Items** — checkbox list, each with an owner and a date if one was stated or clearly
  implied (e.g. "by end of week" resolves against the meeting's own date). Never invent an owner
  or date that wasn't actually in the transcript.
- **Open Questions** — anything raised but left unresolved.
- **Related Notes** — search `projects/`, `people/ones/`, and `people/teams/*/members/` for
  anything the meeting plausibly connects to (attendee names, project names mentioned). Link with
  relative markdown links. If nothing matches, write "none" — don't force a link.

Frontmatter: `date`, `title`, `type` (`1:1` | `standup` | `planning` | `incident-review` |
`external` | `other`), `attendees`, `project` (slug, omit if not project-specific),
`anarlog_meeting_id` (the raw filename's basename, before `.json`).

**Diarization caveat:** beyond the channel ceiling in step 3, a shared conference-room mic (one
channel, everyone on it) is the least reliable case of all — no channel split to lean on at all.
If speaker attribution anywhere looks inconsistent or contradictory, say so in the Summary
instead of presenting a guessed owner/attribution as fact.

### 5. Link related notes

Only *link to* other files. Per the brain's append-only rules, never auto-append a pointer into
`projects/<slug>/notes.md`, `people/ones/*.md`, or any other append-only file — if a cross-link
belongs there too, tell the user and let them add it (or add it yourself only if they say to).

### 6. Write, index, and clean up

- Save to `~/projects/brain/meetings/YYYY-MM-DD-<slug>.md` (date from the meeting itself, slug
  from the title).
- Add a reverse-chronological line to `~/projects/brain/meetings/_index.md`:
  `- [<title>](<date>-<slug>.md) — <type> — <one-line summary>`
- Delete the raw file from `inbox-raw/` once the structured note is written — the raw export is
  optional once digested, same as `research-raw/` sources.
- If the note surfaces something that affects a project's `status.md` (a new blocker, a deadline)
  or belongs in someone's `people/ones/<x>.md` 1:1 log, mention it to the user — don't edit either
  file without being asked; both have their own rhythms this skill shouldn't override.
