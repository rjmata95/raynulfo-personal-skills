---
alias: tenant-mgmt
kind: mongo
env: prod
last_verified: 2026-08-07
---

# tenant-mgmt — schema

Tenant management cluster: tenants, roles, user groups, permissions, profiles, action items,
and authentication config. This is where the tenant IDs used everywhere else are defined.

> **Structure only — never PHI.** User profiles here identify real employees — record field
> names and types, not values.

## This alias is a cluster, not a database

There is no database named `tenant-mgmt`. Name the database explicitly:

```bash
dbq --collections tenant-mgmt                     # lists databases
DBQ_DB=tenant-query dbq --collections tenant-mgmt
```

## Databases

Verified 2026-08-07 via `listDatabases` — 13 databases.

| Database | Role |
|---|---|
| `tenant-cmd` | Tenants, write side (event-sourced) |
| `tenant-query` | Tenant read projection — **prefer for investigation** |
| `role-cmd` / `-query` | Roles |
| `user-group-cmd` / `-query` | User groups |
| `user-permissions-query` | Effective user permissions (read projection) |
| `user-profile-query` | User profiles (read projection) |
| `user-action-items-cmd` / `-query` | User action items — relevant to DDI/DAI action-item reporting |
| `tenant-authentication-config-cmd` / `-query` | Per-tenant auth configuration |
| `tenant-mgmt-tg1-prod` | Cluster-level/tenant-group store |

**CQRS split.** Prefer `<service>-query`; `-cmd` holds event-sourced aggregate state.

## Why this cluster matters

Every other cluster's queries are filtered by `tenantId`. This is where those tenants are
defined, so it is the place to confirm a tenant ID or resolve a market/tenant relationship.

PROD tenant: `5740b0c5-a442-4e04-b961-2a1a0b5dc399` (allowed in documentation — identifies a
tenant, not a person).

## Conventions

- **Hyphenated names need bracket syntax** — `db["some-collection"]`.
- `user-action-items-query` is the read side behind DDI/DAI action-item counts — see
  `reference/external-systems.md` in the brain for the reporting script.
- **Read-only.** Writes go through GraphQL via the `data-fix-scripts` skill.

## Not yet documented

Collection-level field maps are not filled in. Derive one with:

```bash
DBQ_DB=tenant-query dbq --collections tenant-mgmt
DBQ_DB=tenant-query dbq --schema tenant-mgmt.<collection> 500
```
