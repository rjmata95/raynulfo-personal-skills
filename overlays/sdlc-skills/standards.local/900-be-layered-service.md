---
name: be-layered-service
applies-when: discipline == BE && platform == nextgen && (stack == java-spring || stack == ts-nest)
source: null
on-missing-source: skip
---
# be-layered-service (local — adds the ts-nest stack)

The layering contract is unchanged. Read `_shared/standards/180-be-layered-service.md` in full — that
file is the standard. This one exists only to widen it to a stack that is not in the shipped bundle,
and to carry that stack's idiom pointer.

**Verify:** the stack's suite — `./mvnw test` (java-spring) or `npm test` (ts-nest). Read the full
output and exit code; confirm the new tests ran and coverage meets the floor (`coverage_unit`, default
80% — `config.md`).

| Pointer | Target |
|---|---|
| java-spring idiom | ../standards/180-be-layered-service-java-spring.reference.md |
| ts-nest idiom | 900-be-layered-service-ts-nest.reference.md |

Why: one standard id for layered services, widened locally, rather than a forked contract per stack.
Shadowing by id is what keeps the shipped tree free of a stack only this machine runs.
