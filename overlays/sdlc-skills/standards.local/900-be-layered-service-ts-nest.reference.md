---
parent: be-layered-service
work: —
---
# be-layered-service — ts-nest idiom

NestJS on the Fastify adapter, Drizzle for data access, Postgres underneath. Nest's module system is
what carries the layering: one module per domain, exporting its service.

## Layering

- **Repository** — a provider owning Drizzle queries for one table family. It returns rows or domain
  objects and holds no business rules. Nothing outside it imports the Drizzle schema for writes.
- **Service** — `@Injectable()`, business logic and validation, owns the transaction. Cross-domain
  workflows get an orchestrator service that injects the fine-grained ones, so modules never import
  each other in a cycle.
- **Controller** — `@Controller()`, one service call per route, DTO in and DTO out.

## DTOs and validation

`nestjs-zod` is the boundary: the schema comes from the published contracts package, and
`createZodDto()` turns it into the DTO class the controller declares. A global `ZodValidationPipe`
enforces it. The schema in the contracts package is the single source of truth — transcribe it, do not
restate the shape by hand in the service.

Enums persist as strings. Transactional money is integer minor units (`bigint`), never a float.

## Response envelope

One global interceptor applies the envelope
(`{ status, data, error{code,message}, timestamp, path, method, traceId }`), and one global exception
filter maps typed exceptions to it. Exclusions from the envelope (health probes, `/mcp`) are explicit
and tested, never incidental.

## Transactions and tenant scope

Drizzle's transaction callback is the unit of work. Where rows are protected by Postgres RLS, the
transaction sets the tenant GUC first —
`set_config('app.current_tenant', $1, true)` — and every statement in that transaction inherits it.
See `data-prod-safety` for the obligation this satisfies.

## Verify

```bash
npm test              # unit + component suites
npm run lint
```

Read the full output and exit code; confirm the new tests ran and coverage meets `coverage_unit`.

## Common traps

- A controller importing the repository directly, skipping the service.
- Hand-writing a DTO shape instead of deriving it from the contracts schema — the two drift silently.
- Running a query outside the transaction that set the tenant GUC, so RLS sees no tenant.
- Business logic inside a Drizzle query builder.
- Floats for money.
