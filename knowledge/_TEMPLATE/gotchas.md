---
alias: <alias>
---

# <alias> — gotchas

Append-only. Newest entry at the top. Never rewrite a previous entry — if one turns out to be
wrong, append a correction that supersedes it and say so.

> **Structure only — never PHI.** Describe shapes and causes, not patient data. Use
> `<placeholder>` for identifiers in example queries.

Entry format:

```markdown
## YYYY-MM-DD — one-line summary

**Symptom:** what looked wrong, or what you expected and did not get.
**Cause:** what is actually going on.
**Handling:** what to do instead. Include a working query if there is one.
```

Worth an entry: a field far emptier than expected, a missing or mis-ordered index, multiple
document shapes in one collection, the same concept named differently across collections,
undocumented enum values, counts that disagree between sources, environment-specific
behaviour, or naming that actively misleads.

Not worth an entry: your own typos and one-off mistakes. Only record what will still be true
for the next agent.

---

<!-- Newest entries go directly below this line. -->
