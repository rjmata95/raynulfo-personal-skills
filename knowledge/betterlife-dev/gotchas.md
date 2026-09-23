---
alias: betterlife-dev
---

# betterlife-dev — gotchas

Append-only. Newest entry at the top. Never rewrite a previous entry — if one turns out to be
wrong, append a correction that supersedes it and say so.

Entry format:

```markdown
## YYYY-MM-DD — one-line summary

**Symptom:** what looked wrong, or what you expected and did not get.
**Cause:** what is actually going on.
**Handling:** what to do instead. Include a working query if there is one.
```

---

<!-- Newest entries go directly below this line. -->

## 2026-09-23 — two tenants share the name "Better Life Household"

**Symptom:** `fitness.tenants` returns two rows with the same `name`, and a query can come
back empty under one of them.
**Cause:** Two distinct tenant UUIDs. On 2026-09-23 the live workout data sat under only one
of them.
**Handling:** Choose the tenant by `id`, not by `name`. When unsure, run the query once per
tenant.

## 2026-09-23 — the dev database is shut down every night

**Symptom:** `dbq doctor` or a query times out or reports `connection refused` in the evening
or early morning.
**Cause:** Cloud Scheduler jobs `dev-db-stop` / `dev-db-start` stop the `landscaping-dev`
instance from about 22:05 to 05:00 ET (`landscaping-infrastructure/terraform/modules/scheduler/main.tf`).
**Handling:** Retry after 05:00 ET. It is not a credentials problem.

## 2026-09-23 — laptop connections need the public IP and an allowlisted client IP

**Symptom:** A connection to the host in the Secret Manager DSN (`172.26.0.3`) times out.
**Cause:** That is the private VPC IP, reachable only from Cloud Run. Dev also has a public IP,
but Cloud SQL accepts only client IPs on its authorized-networks list. That list is managed
by hand with `gcloud`, and Terraform ignores it.
**Handling:** Use the public IP as the host. If it still times out, add your IP to the
instance's authorized networks, or run the Cloud SQL Auth Proxy
(`gs-landscaping-dev:us-east1:landscaping-dev`) and point the alias at `127.0.0.1`.

## 2026-09-23 — a tenant-less query returns 0 rows, not an error

**Symptom:** `SELECT count(*) FROM fitness.users` returns `0`.
**Cause:** FORCE row-level security filters on `app.current_tenant`. If it is unset, no rows
match.
**Handling:** `SET app.current_tenant = '<uuid>';` in the same `dbq` call. Get tenant IDs from
`fitness.tenants`, which has no policy.
