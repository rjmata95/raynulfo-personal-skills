---
name: fe-react-rest
applies-when: discipline == FE && platform == nextgen && stack == react-rest
source: null
on-missing-source: skip
---
# fe-react-rest

All backend traffic flows one way through three layers:
`component → queries/<domain>Service.ts → services/<domain>Service.ts → services/api.ts`.

**`services/api.ts`** is the single axios instance — it attaches the auth token, serializes params and
centralizes the error log, and is the only module importing axios. **`services/<domain>Service.ts`**
holds one typed function per endpoint, unwraps the response envelope and throws a normalized `Error`;
it imports no React and no query library. **`queries/<domain>Service.ts`** holds the TanStack Query v5
hooks — an `xKeys` factory, one `useX` per read, one per mutation with `onSuccess` invalidation — and
imports no axios. **Components** import only from `queries/` and read `{ data, isLoading, error }` off
the hook instead of wrapping the call in try/catch.

The layering is bidirectional and load-bearing: a component that fetches directly re-fetches on every
mount, ignores `staleTime`, and diverges from every other consumer of that resource.

**Query keys are hierarchical** (`all` / `lists` / `list(filters)` / `details` / `detail(id)`) so a
mutation invalidates at the narrowest level covering the affected reads — update calls `setQueryData`
on the detail key plus `invalidateQueries` on `lists()`; create calls `lists()` only.

**Render every state** — loading, error and empty, not only the happy path. Props are explicitly
typed. Keyboard navigation, ARIA labels/roles and focus management are DoD items.

**Verify:** `npx vitest run` — read the full output and exit code, coverage meets the floor
(`coverage_fe`, default 85% — `config.md`). Tests query by role/label, drive with `userEvent`, and mock
at the service layer (MSW or `vi.mock`). Run lint and an a11y check (`axe-core`); where a Figma frame
is referenced, compare the rendered UI against it.

See `910-fe-react-rest.reference.md` for the layer skeletons and the mutation-render-gate trap.

Why: this is the runtime partner of the plan's frontend decision for a React app consuming a **REST**
envelope. A frontend consuming GraphQL uses `fe-nextgen` instead; the two are alternatives.
