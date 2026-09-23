# Postgres patterns through `dbq`

`dbq <alias> '<sql>'`. The argument is plain SQL, run by `psql -c`. Before your first query
against an alias, read `knowledge/<alias>/`: it records per-database rules such as tenant
scoping.

## Output is TSV

`dbq` runs `psql -X -A -F '\t'`, which gives tab-separated output with a header row and a
`(N rows)` footer. `-X` skips `~/.psqlrc`, so the output looks the same on every machine.

```bash
dbq betterlife-dev 'SELECT id, name FROM fitness.tenants' | column -t -s $'\t'
```

## Schema-qualify every table

`--collections` lists tables as `schema.table`. Use the same form in queries and in
`--schema`. An unqualified `--schema` defaults to `public`.

```bash
dbq --collections betterlife-dev
dbq --schema betterlife-dev.fitness.workout_logs     # columns, indexes, foreign keys
```

## Session settings: SET in the same query

One `dbq` call is one session, and the statements in its query string share it. That is how
you set a variable a policy reads, such as a row-level-security tenant:

```bash
dbq betterlife-dev "SET app.current_tenant = '<tenant-uuid>'; SELECT count(*) FROM fitness.users"
```

The setting ends with the call. Every separate `dbq` call starts with none.

## Read-only is enforced twice

A `ro` alias fails in either of two places:

1. **Pre-flight regex.** It refuses writes and DDL (`INSERT` … `CLUSTER`, `COPY`, `MERGE`),
   psql meta-commands that touch the shell or filesystem (`\!` `\o` `\w` `\i` `\copy` `\g*`
   `\set`), and anything that names `transaction_read_only`, `READ WRITE`, or
   `session_authorization`. Because of that last rule, even `SHOW default_transaction_read_only`
   is refused. This is expected.
2. **Server-side.** The session opens with `default_transaction_read_only=on`, so the server
   rejects any write the regex misses (`nextval()`, a write inside a function). The error is
   `cannot execute … in a read-only transaction`.

This protection comes from `dbq`, not from the database role. A role such as BetterLife's
`bl_app` can write if you connect with it some other way.

Introspection meta-commands work: `\d fitness.users`, `\dt fitness.*`, `\dn`.

## Bound the result set

Always use `LIMIT`. `count(*)` first on anything unfamiliar.
