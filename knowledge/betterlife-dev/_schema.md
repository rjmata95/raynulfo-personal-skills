---
alias: betterlife-dev
kind: postgres
env: dev
last_verified: 2026-09-23 (connected; tables still from migrations)
---

# betterlife-dev — schema

BetterLife fitness app data, owned by `better-life-service`. It is the `betterlife` database
on the shared Cloud SQL instance `landscaping-dev` (project `gs-landscaping-dev`, us-east1).
Landscaping's `landscaping` database lives on the same instance and is a separate alias.

This file was seeded from `better-life-service/drizzle/*.sql`, not from live reads. Replace it
with `dbq --schema` output after the first verified connection.

> **Structure only.** Field names, types, and indexes go here. Real user data does not.

## Read this before your first query

- **Every app table lives in schema `fitness`.** Enum types live in `public`. Always
  schema-qualify: `fitness.users`, not `users`.
- **Row-level security hides rows silently.** Almost every `fitness` table has
  `FORCE ROW LEVEL SECURITY` with the policy
  `tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid`.
  If the tenant is not set, a query returns **0 rows with no error**, which looks exactly like
  an empty table. Set the tenant in the same call:

  ```bash
  dbq betterlife-dev 'SELECT id, name FROM fitness.tenants'      # no policy: find the tenant
  dbq betterlife-dev "SET app.current_tenant = '<tenant-uuid>'; SELECT count(*) FROM fitness.workout_logs"
  ```

- **These two tables have no tenant policy:** `fitness.tenants` and `fitness.schema_migrations`
  (the migration ledger).

## Tables (schema `fitness`)

| Migration | Tables |
|---|---|
| `0001_baseline` | tenants, users, profiles, injuries, injury_rules, injury_stage_events, programs, program_anchors, blocks, deloads, session_types, session_notes, exercises, exercise_aliases, program_exercises, program_exercise_options, exercise_swaps, swap_fallbacks, f45_classes, plan_defaults, plans, plan_rules, workout_logs, set_logs, exercise_completions, soreness_reports, weigh_ins, food_logs, notes, documents, document_versions, decisions |
| `0005_session_recorder` | movement_patterns, equipment_types, grips, exercise_categories, exercise_advisories, workout_plan_items, workout_plan_item_sets |
| runner | schema_migrations |

`0002` adds RLS policies and the `bl_app_rls` role. `0003`, `0004`, and `0006` alter existing
tables.

## Roles

| Role | Use for dbq? | Notes |
|---|---|---|
| `bl_app` | **Yes, for now** | Runtime login role. Non-superuser, `NOBYPASSRLS`, so RLS applies. Has read/write grants; dbq's `ro` mode is what keeps the session read-only. |
| `betterlife` | No | Schema owner that runs DDL/migrations. RLS still applies (FORCE). |
| `landscaping_user` | **Never** | `cloudsqlsuperuser`: bypasses RLS and can write anything. |

No read-only role exists yet. A dedicated `SELECT`-only role would make dbq's `ro` guard a
second layer instead of the only one. It must be created in SQL, not with
`gcloud sql users create`, which grants `cloudsqlsuperuser`.
