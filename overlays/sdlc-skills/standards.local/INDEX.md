# Local implementation standards — INDEX (machine-local, never committed)

These rows merge into `standards/INDEX.md`. A row whose `id` matches a shipped row **shadows** it in
the shipped row's position; a new `id` appends after all shipped rows. Legal predicate field tokens
are `selection-facts.json` unioned with `selection-facts.local.json`.

| id | applies-when | one-line summary |
|---|---|---|
| be-layered-service | discipline == BE && platform == nextgen && (stack == java-spring \|\| stack == ts-nest) | controller→service→repository layering, DTO boundary, orchestrators + verify cmd |
| fe-react-rest | discipline == FE && platform == nextgen && stack == react-rest | component→queries→services→axios layering, TanStack keys + verify cmd |
| be-nest-module-wiring | discipline == BE && platform == nextgen && stack == ts-nest | providers registered in the module file; siblings reach them only by constructor injection of an exported provider |
