# MySQL patterns through `dbq`

`dbq mysql-prod '<sql>'` / `dbq mysql-qa '<sql>'`. The argument is plain SQL.

| Alias | Host role | Default DB | Notes |
|---|---|---|---|
| `mysql-prod` | BIDW prod warehouse | `DASHBOARD_PROD` | Reporting/dashboard data. Read-only. |
| `mysql-qa` | DASH QA | `DASHBOARD_PROD` | QA data; schema can drift from prod. |

Both require VPN — the hosts are `.chenmed.local`.

## Output is TSV

`dbq` runs `mysql --batch --raw --column-names`: tab-separated, header row, no ASCII art.
That makes it pipeable:

```bash
dbq mysql-prod 'SELECT office_id, name FROM office LIMIT 5' | column -t -s $'\t'
dbq mysql-prod 'SELECT COUNT(*) AS n FROM office' | tail -1
```

`--raw` means no escaping of tabs/newlines inside values. If a column may contain either, ask
for JSON instead:

```sql
SELECT JSON_OBJECT('id', office_id, 'name', name) FROM office LIMIT 5
```

## Always bound your result set

```sql
SELECT * FROM patient_encounter LIMIT 100
```

Warehouse tables run to millions of rows. An unbounded `SELECT *` will flood context and can
sit on the server for minutes. Add `LIMIT` while exploring, every time.

## Learn the shape before querying

```bash
dbq --collections mysql-prod                  # SHOW TABLES
dbq --schema mysql-prod.office                # DESCRIBE + SHOW INDEX
```

For a quick sense of size and cost:

```sql
SELECT table_name, table_rows,
       ROUND(data_length/1024/1024) AS data_mb,
       ROUND(index_length/1024/1024) AS idx_mb
FROM information_schema.tables
WHERE table_schema = DATABASE()
ORDER BY data_length DESC
LIMIT 20
```

`table_rows` is an estimate for InnoDB — fine for triage, not for reporting.

## Aggregate on the server

Push work into SQL rather than pulling rows and counting yourself:

```sql
SELECT status, COUNT(*) AS n
FROM prescription_fact
GROUP BY status
ORDER BY n DESC
```

## EXPLAIN before blaming the database

```sql
EXPLAIN SELECT * FROM prescription_fact WHERE office_id = 123 AND status = 'ACTIVE'
```

`type: ALL` means a full scan. Check `key` — `NULL` means no index used. `rows` is the
estimated examine count.

## Other databases on the same server

The alias sets a default database, but the connection can see others if the user has grants:

```bash
dbq mysql-prod 'SHOW DATABASES'
DBQ_DB=OTHER_SCHEMA dbq mysql-prod 'SHOW TABLES'
dbq mysql-prod 'SELECT * FROM OTHER_SCHEMA.some_table LIMIT 5'   -- or qualify inline
```

## Long queries go in a file

```bash
cat > "$(dbq scratch)/office-rollup.sql" <<'EOF'
SELECT o.office_id, o.name, COUNT(e.encounter_id) AS encounters
FROM office o
LEFT JOIN patient_encounter e ON e.office_id = o.office_id
GROUP BY o.office_id, o.name
ORDER BY encounters DESC
LIMIT 25;
EOF

dbq --file mysql-prod "$(dbq scratch)/office-rollup.sql"
```

## Gotchas

- **Reads only.** `INSERT`, `UPDATE`, `DELETE`, `DROP`, `TRUNCATE`, `ALTER` are rejected before
  connecting. Writes go through GraphQL — see the `data-fix-scripts` skill.
- **`DASHBOARD_PROD` on the QA host.** The QA server's default database is also named
  `DASHBOARD_PROD`. The *name* does not tell you which environment you are in — the alias
  does. Double-check before drawing conclusions from row counts.
- **Warehouse lag.** BIDW is populated by ETL, so it trails the operational Mongo stores.
  A count that disagrees with Mongo may be timing, not a bug.
- **`NULL` in aggregates.** `COUNT(col)` skips nulls; `COUNT(*)` does not. A silent
  discrepancy between the two is usually the answer to "why don't these numbers match".
- **Implicit type coercion.** Comparing a `VARCHAR` id to a bare number
  (`WHERE code = 123`) makes MySQL coerce and quietly ignore the index. Quote it: `= '123'`.
- **Semicolons.** Optional for a single statement; required between statements. Multi-statement
  execution may be disabled — run them as separate `dbq` calls if one fails oddly.
